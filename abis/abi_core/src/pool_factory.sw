library pool_factory;

use abi_utils::data_structures::{DataPackage};
use std::{identity::Identity, contract_id::ContractId};

abi PoolFactory {
    ////////////
    // Read Only
    ////////////
    /// Return the swap fee charged on this pool type
    #[storage(read)]fn get_swap_fee() -> u16;
    /// Return the protocol fee charged on this pool type
    #[storage(read)]fn get_protocol_fee() -> u16;
    /// Return the protocol fee receiver
    #[storage(read)]fn get_protocol_fee_receiver() -> ContractId;
    /// Return whether a pool is already registered
    #[storage(read)]fn is_pool_used(pool: ContractId) -> bool;
    /// Return the address of the pool contract for a pair of tokens
    #[storage(read)]fn get_pool(tokenA: ContractId, tokenB: ContractId) -> ContractId;

    //////////
    // Actions
    //////////
    /// Set the protocol fee
    #[storage(read, write)]fn set_protocol_fee(fee: u16) -> bool;
    /// Set the protocol fee receiver
    #[storage(read, write)]fn set_protocol_fee_receiver(fee_receiver: Identity) -> bool;
    /// Start ramping A up or down for a specific (stable) pool
    #[storage(read, write)]fn start_ramp_a(tokenA: ContractId, tokenB: ContractId, next_A: u64, ramp_end_time: u64) -> bool;
    /// Stop ramping A up or down for a specific (stable) pool
    #[storage(read, write)]fn stop_ramp_a(tokenA: ContractId, tokenB: ContractId) -> bool;
    /// Remove a pool from a factory registry
    #[storage(read, write)]fn remove_pool(tokenA: ContractId, tokenB: ContractId) -> bool;
}
