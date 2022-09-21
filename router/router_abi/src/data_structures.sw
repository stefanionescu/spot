library data_structures;

use abi_utils::data_structures::DataPackage;
use std::{identity::Identity, contract_id::ContractId, vec::Vec};

////////////
// Swap Path
////////////
pub struct Path {
    /// Factory in which the pool is registered
    factory: ContractId,
    /// Pool in the path
    pool: ContractId,
    /// Extra data associated with the path
    data: DataPackage
}

////////////////////////////
// Exact Input Single Params
////////////////////////////
pub struct ExactInputSingleParams {
    /// The amount of tokens to swap
    amount_in: u64,
    /// The minimum amount of tokens to receive
    amount_out_minimum: u64,
    /// Factory in which the pool is registered
    factory: ContractId,
    /// The pool used to swap
    pool: ContractId,
    /// The token to swap
    token_in: ContractId,
    /// Extra data associated with the swap
    data: DataPackage
}

/////////////////////
// Exact Input Params
/////////////////////
pub struct ExactInputParams {
    /// The amount of tokens to swap
    amount_in: u64,
    /// The minimum amount of tokens to receive
    amount_out_minimum: u64,
    /// The token to swap
    token_in: ContractId,
    /// The swap path
    path: Vec<Path>
}

//////////////
// Token Input
//////////////
pub struct TokenInput {
    /// The token
    token: ContractId,
    /// The token amount
    amount: u64
}
