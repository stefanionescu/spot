library constants;

use std::u128::U128;

pub const MAX_FEE: u16                    = 10_000;

pub const LP_TOKEN_NAME: str[13]          = "Spot LP Token";
pub const LP_TOKEN_SYMBOL: str[7]         = "SPOT-LP";
pub const LP_TOKEN_DECIMALS: u8           = 6;

pub const MINIMUM_LIQUIDITY: u64          = 1_000;

pub const POOL_ID: u64                    = 1;

pub const ZERO_U128: U128                 = ~U128::new();

pub const MAX_CALLBACK_PARAM_ARRAY_LENGTH = 10;
