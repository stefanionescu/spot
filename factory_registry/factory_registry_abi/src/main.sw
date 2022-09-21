library factory_registry_abi;

dep errors;
dep events;
dep constants;

use std::{identity::Identity, contract_id::ContractId};

abi FactoryRegistry {
    ////////////
    // Read Only
    ////////////
    /// Return the contract owner
    #[storage(read)]fn get_owner() -> Identity;
    /// Return the current proposed owner
    #[storage(read)]fn get_proposed_owner() -> Identity;
    /// Return whether a factory is whitelisted or not
    #[storage(read)]fn is_whitelisted(factory: b256) -> bool;

    //////////
    // Actions
    //////////
    /// Initialize the contract
    #[storage(read, write)]fn constructor();
    /// Propose a new owner for the contract
    #[storage(read, write)]fn propose_owner(owner: Identity) -> bool;
    /// Claim contract ownership
    #[storage(read, write)]fn claim_ownership() -> Identity;
    /// Whitelist a factory
    #[storage(read, write)]fn add_to_whitelist(factory: b256) -> bool;
    /// Remove a factory from whitelist
    #[storage(read, write)]fn remove_from_whitelist(factory: b256) -> bool;
    /// Set the protocol fee for a factory
    #[storage(read, write)]fn set_protocol_fee(factory: b256, fee: u16) -> bool;
    /// Set the protocol fee receiver for a factory
    #[storage(read, write)]fn set_protocol_fee_receiver(factory: b256, fee_receiver: Identity) -> bool;
    /// Remove a pool from a factory registry
    #[storage(read, write)]fn remove_pool(factory: b256, tokenA: ContractId, tokenB: ContractId) -> bool;
    /// Start ramping A up or down for a specific pool
    #[storage(read, write)]fn start_ramp_a(factory: b256, tokenA: ContractId, tokenB: ContractId, next_A: u64, ramp_end_time: u64) -> bool;
    /// Stop ramping A up or down for a specific pool
    #[storage(read, write)]fn stop_ramp_a(factory: b256, tokenA: ContractId, tokenB: ContractId) -> bool;
}
