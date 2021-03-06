
{-# LANGUAGE QuasiQuotes, ScopedTypeVariables #-}

module Main where

import           Control.Monad.IO.Class (MonadIO, liftIO)
import           Control.Monad (when, void, forever)
import           Control.Concurrent (forkIO, threadDelay)
import           Control.Concurrent.MVar

import           Data.Monoid ((<>))
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Read as T
import qualified Data.Aeson as Aeson
import           Data.Aeson ((.=))

import           System.Environment (getEnv)

import           Data.Pool (Pool, createPool, withResource)
import qualified Database.PostgreSQL.Simple as PG
import           Database.PostgreSQL.Simple.SqlQQ (sql)

import           Web.Scotty
import           Network.Wai.Middleware.Cors



const_HTTP_PORT :: Int
const_HTTP_PORT = 8000

const_curencies :: [Text]
const_curencies = ["BTC", "LTC", "XMR", "DASH"]

main :: IO ()
main = do
  pgConn <- PG.ConnectInfo
    <$> getEnv "RDS_HOSTNAME"
    <*> (read <$> getEnv "RDS_PORT")
    <*> getEnv "RDS_USERNAME"
    <*> getEnv "RDS_PASSWORD"
    <*> getEnv "RDS_DB_NAME"

  -- create pool & check PG connection
  pg <- createPool (PG.connect pgConn) PG.close 1 (fromInteger 20) 5
  [[True]] <- withResource pg $ flip PG.query_ [sql| select true |]

  -- refresh config in a loop
  ico_config <- liftIO newEmptyMVar
  void $ forkIO $ forever $ do
    [[res]] <- withResource pg $ flip PG.query_ [sql| select ico_info() |]
    void $ tryTakeMVar ico_config
    putMVar ico_config res
    threadDelay $ 1000 * 1000

  logInfo "HTTP" const_HTTP_PORT
  scotty const_HTTP_PORT $ httpServer pg ico_config


-- TODO:
-- - cache
-- - check limits in invoice

httpServer :: Pool PG.Connection -> MVar Aeson.Value -> ScottyM ()
httpServer pg ico_config = do
  let corsPolicy = simpleCorsResourcePolicy
  middleware $ cors (const $ Just corsPolicy)

  get "/" $ text "Ok"

  get "/config" $ liftIO (readMVar ico_config) >>= json

  get "/info/:ethAddr" $ do
    ethAddr <- T.toLower <$> param "ethAddr"
    when (not $ validEth ethAddr) $ httpError "Invalid ETH address"
    sendAnalytics pg "info" ethAddr

    [[res]] <- liftAndCatchIO $ withResource pg
      $ \c -> PG.query c [sql| select addr_info(?) |] [ethAddr]
    json (res :: Aeson.Value)

  post "/invoice/:curr/:ethAddr" $ do
    liftIO $ threadDelay $ 1500 * 1000 -- small delay to throttle DB load

    currency <- T.toUpper <$> param "curr"
    when (not $ currency `elem` const_curencies)
      $ httpError "Invalid currency code"

    ethAddr  <- T.toLower <$> param "ethAddr"
    when (not $ validEth ethAddr) $ httpError "Invalid ETH address"
    sendAnalytics pg ("invoice/" <> currency) ethAddr

    res <- liftAndCatchIO $ withResource pg $ \c -> PG.query c
      [sql| select create_invoice(?, ?) |]
      (currency, ethAddr)

    case res of
      [[Just jsn]] -> json (jsn :: Aeson.Value)
      [[Nothing]]  -> httpError "Sudden lack of free addresses"
      _  -> do
        logError "invoice: unexpected query result" res
        raise "Unexpected query result"


-----------
-- Utility
-----------

sendAnalytics :: Pool PG.Connection -> Text -> Text -> ActionM ()
sendAnalytics pg tag addr = do
  cid <- param "cid" `rescue` \_ -> return ""
  when (cid /= "") $ do
    void $ liftAndCatchIO $ withResource pg
      $ \c -> PG.execute c
        [sql| insert into analytics_event (cid, tag, addr) values (?,?,?) |]
        [cid , tag, addr]


validEth :: Text -> Bool
validEth eth = case T.hexadecimal eth of
  Right (_ :: Integer, "")
    -> "0x" `T.isPrefixOf` eth && T.length eth == 42
  _ -> False


logInfo :: (MonadIO m, Show a) => Text -> a -> m ()
logInfo m a = liftIO $ T.putStrLn $ m <> " >> " <> T.pack (show a)

logError :: (MonadIO m, Show a) => Text -> a -> m ()
logError m a = liftIO $ T.putStrLn $ "ERROR: " <> m <> " >> " <> T.pack (show a)

httpError :: Text -> ActionM ()
httpError msg = json (Aeson.object ["error" .= msg]) >> finish
