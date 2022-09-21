library data_structures;

use std::{contract_id::ContractId};

/// A pair of tokens
pub struct TokenPair {
    tokenA: ContractId,
    tokenB: ContractId
}
