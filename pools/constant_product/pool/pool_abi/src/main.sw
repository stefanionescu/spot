library constant_product_pool_abi;

dep errors;
dep events;
dep constants;
dep data_structures;

use data_structures::{PoolReserves};
use abi_utils::data_structures::{DataPackage};

use std::{
    contract_id::ContractId,
    identity::Identity,
    u128::U128,
    vec::Vec
};

abi ConstantProductPool {
    ////////////
    // Read Only
    ////////////
    /// Return an identifier for the pool type
    fn get_pool_id() -> u64;
    /// Return the LP token's name
    fn name() -> str[13];
    /// Return the LP token's symbol
    fn symbol() -> str[7];
    /// Return the amount of decimals the pool's LP token has
    fn decimals() -> u8;
    /// Return an array of tokens supported by the pool
    #[storage(read)]fn get_assets() -> Vec<ContractId>;
    /// Return the factory contract ID
    #[storage(read)]fn get_factory() -> ContractId;
    /// Return the amount of out tokens that someone would get by swapping `amount_in` `token_in`
    #[storage(read)]fn get_amount_out(data: DataPackage) -> u64;
    /// Return the amount of in tokens that someone would get by swapping `amount_out` `token_out`
    #[storage(read)]fn get_amount_in(data: DataPackage) -> u64;
    /// Return the cumulative price for `token0`
    #[storage(read)]fn get_price_cumulative0() -> U128;
    /// Return the cumulative price for `token1`
    #[storage(read)]fn get_price_cumulative1() -> U128;
    /// Return the last recorded value for `k`
    #[storage(read)]fn get_k_last() -> u64;
    /// Return the amounts of token0 and token1 held by the pool and the last timestamp when they were updated
    #[storage(read)]fn get_reserves() -> PoolReserves;

    //////////
    // Actions
    //////////
    /// Initialize the contract
    #[storage(read, write)]fn constructor(factory: ContractId, token0: ContractId, token1: ContractId);
    /// Mint LP tokens for a custom recipient
    #[storage(read, write)]fn mint(data: DataPackage) -> u64;
    /// Burn LP tokens and send the withdrawn liquidity to a custom recipient
    #[storage(read, write)]fn burn(data: DataPackage) -> Vec<u64>;
    /// Burn LP tokens, withdraw a single token and send it to a custom recipient
    #[storage(read, write)]fn burn_single(data: DataPackage) -> u64;
    /// Swap one token for another
    #[storage(read, write)]fn swap(data: DataPackage) -> u64;
    /// Swap one token for another, flashloan style
    #[storage(read, write)]fn flashswap(data: DataPackage, context: DataPackage) -> u64;
}
