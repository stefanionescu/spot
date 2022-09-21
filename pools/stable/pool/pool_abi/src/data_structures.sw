library data_structures;

use std::{
    u128::U128,
    contract_id::ContractId
};

/// A pair of tokens
pub struct TokenPair {
    tokenA: ContractId,
    tokenB: ContractId
}

/// Reserve data for a constant sum pool
pub struct PoolReserves {
    reserve0: U128,
    reserve1: U128,
    d_last: U128
}

/// Swap, protocol and `MAX - swap` fees
pub struct Fees {
    swap_fee: u16,
    protocol_fee: u16,
    max_less_swap_fee: u16,
    max_less_protocol_fee: u16
}

/// Used to return mint fee update related data
pub struct LPUpdate {
    total_supply: u64,
    d: u64
}
