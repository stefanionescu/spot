library router_abi;

dep errors;
dep events;
dep constants;
dep data_structures;

use data_structures::*;
use abi_utils::data_structures::{DataPackage};
use std::{identity::Identity, contract_id::ContractId, vec::Vec};

abi Router {
    //////////
    // Actions
    //////////
    /// Initialize the contract
    #[storage(read, write)]fn constructor(factory_registry: ContractId);
    /// Swaps token A to token B directly
    #[storage(read, write)]fn swap_exact_input_single(params: ExactInputSingleParams) -> u64;
    /// Swaps token A to token B indirectly by using multiple hops
    #[storage(read, write)]fn swap_exact_input(params: ExactInputParams) -> u64;
    /// Add liquidity into a pool
    #[storage(read, write)]fn add_liquidity(token_input: Vec<TokenInput>, factory: ContractId, pool: ContractId, min_liquidity: u64, data: DataPackage) -> u64;
    /// Burn LP tokens and get back liquidity
    #[storage(read, write)]fn burn_liquidity(pool: ContractId, liquidity: u64, data: DataPackage, min_withdrawals: Vec<u64>) -> Vec<u64>;
    /// Burn LP tokens and get back liquidity in a single token (by swapping to that token in the background)
    #[storage(read, write)]fn burn_liquidity_single(pool: ContractId, liquidity: u64, data: DataPackage, min_withdrawal: u64) -> u64;
    /// Recover tokens sent by mistake to the router
    fn sweep(token: ContractId, amount: u64, recipient: Identity) -> bool;
}
