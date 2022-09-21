library constants;

use std::u128::U128;

pub const MAX_FEE: u16                    = 10_000;

pub const LP_TOKEN_NAME: str[13]          = "Spot LP Token";
pub const LP_TOKEN_SYMBOL: str[7]         = "SPOT-LP";
pub const LP_TOKEN_DECIMALS: u8           = 6;

pub const MINIMUM_LIQUIDITY: u64          = 1_000;

pub const POOL_ID: u64                    = 2;

pub const ZERO_U128: U128                 = ~U128::new();

pub const MAX_CALLBACK_PARAM_ARRAY_LENGTH = 10;

pub const MAX_LOOP_LIMIT: u64             = 256;

pub const COINS: u64                      = 2;

pub const POOL_PRECISION_DECIMALS: u64    = 6;

pub const A_PRECISION: u64                = 100;
pub const MAX_A: u64                      = 1_000_000;
pub const MAX_A_CHANGE: u64               = 10;
pub const MIN_A_CHANGE_DURATION: u64      = 86400;

pub const ONE_U128                        = ~U128::from(0, 1);
pub const TWO_U128                        = ~U128::from(0, 2);
pub const THREE_U128                      = ~U128::from(0, 3);
pub const FOUR_U128                       = ~U128::from(0, 4);
