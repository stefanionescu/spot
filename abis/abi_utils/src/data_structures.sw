library data_structures;

use std::{identity::Identity, contract_id::ContractId, storage::StorageMap, vec::Vec, u256::U256};

// Generic
///////////////////////////
// Data Package
///////////////////////////
pub struct DataPackage {
    /// Vector of identities
    identities: Vec<Identity>,
    /// Vector of contract IDs
    contract_ids: Vec<ContractId>,
    /// Vector of amounts/values
    amounts: Vec<U256>,
    /// Vector of bools/flags
    flags: Vec<bool>
}

// Tokens
////////////////////
// Token with Amount
////////////////////
pub struct TokenAmount {
    /// The token returned
    token: ContractId,
    /// The amount of tokens returned
    amount: u64
}
