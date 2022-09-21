library pool;

use abi_utils::data_structures::{DataPackage, TokenAmount};
use std::{identity::Identity, contract_id::ContractId, vec::Vec};

/// Spot pool ABI
abi Pool {
    ////////////
    // Read Only
    ////////////
    /// Return an identifier for the pool type
    #[storage(read)]fn get_pool_id() -> u64;
    /// Return an array of tokens supported by the pool
    #[storage(read)]fn get_assets() -> Vec<ContractId>;
    /// Return the factory contract ID
    #[storage(read)]fn get_factory() -> ContractId;
    /// Return the amount of decimals that the pool's LP token has
    #[storage(read)]fn decimals() -> u8;
    /// Return the amplification parameter
    #[storage(read)]fn get_a() -> u64;

    //////////
    // Actions
    //////////
    /// Mint LP tokens for a custom recipient
    #[storage(read, write)]fn mint(data: DataPackage) -> u64;
    /// Burn LP tokens and send the withdrawn liquidity to a custom recipient
    #[storage(read, write)]fn burn(data: DataPackage) -> Vec<u64>;
    /// Burn LP tokens, withdraw a single token and send it to a custom recipient
    #[storage(read, write)]fn burn_single(data: DataPackage) -> u64;
    /// Swap one token for another
    #[storage(read, write)]fn swap(data: DataPackage) -> u64;
    /// Start ramping A up or down
    #[storage(read, write)]fn start_ramp_a(next_A: u64, ramp_end_time: u64) -> bool;
    /// Stop ramping A up or down
    #[storage(read, write)]fn stop_ramp_a() -> bool;
}
