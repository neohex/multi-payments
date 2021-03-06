create type currency_code as enum
  ( 'BTC', 'LTC', 'DASH', 'XMR', 'ETH', 'ETC', 'TIME', 'SNM');


create table ico_config
  ( snm_total_limit int8 not null default 444000000
  , snm_ico_limit int8 not null default 331360000
  , snm_per_eth int8 not null default 2824
  , time_address text not null default
    '0x6531f133e6deebe7f2dce5a0441aa7ef330b4e53'
  , time_transfer_topic text not null default
    '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
  -- snm_address text not null default
  -- snm_transfer_topic text not null default
  , analytics_tid text not null default 'UA-97005266-1'
  );
insert into ico_config default values;


create table currency_limit
  ( currency currency_code unique not null
  , soft_limit int8 not null
  , hard_limit int8 not null
  );

insert into currency_limit values
  ('LTC', 40000, 50000)
, ('ETC', 65000, 75000)
, ('XMR', 20000, 30000)
, ('DASH', 7000, 8000)
, ('TIME', 5000, 6500)
;
