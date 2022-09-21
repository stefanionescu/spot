library constant_product_factory_abi;

dep errors;
dep events;
dep constants;
dep data_structures;

use std::{contract_id::ContractId, identity::Identity};

abi ConstantProductFactory {
    ////////////
    // Read Only
    ////////////
    /// Return the contract owner
    #[storage(read)]fn get_owner() -> Identity;
    /// Return the current proposed owner
    #[storage(read)]fn get_proposed_owner() -> Identity;
    /// Return the factory registry contract ID
    #[storage(read)]fn get_factory_registry() -> ContractId;
    /// Return the swap fee charged on this pool type
    #[storage(read)]fn get_swap_fee() -> u16;
    /// Return the protocol fee charged on this pool type
    #[storage(read)]fn get_protocol_fee() -> u16;
    /// Return the protocol fee receiver
    #[storage(read)]fn get_protocol_fee_receiver() -> ContractId;
    /// Return the address of the pool contract for a pair of tokens
    #[storage(read)]fn get_pool(tokenA: ContractId, tokenB: ContractId) -> ContractId;
    /// Return whether a pool is already registered
    #[storage(read)]fn is_pool_used(pool: ContractId) -> bool;

    //////////
    // Actions
    //////////
    /// Initialize the contract
    #[storage(read, write)]fn constructor(has_owner: bool, factory_registry: ContractId, swap_fee: u16, protocol_fee: u16, protocol_fee_receiver: ContractId);
    /// Propose a new owner for the contract
    #[storage(read, write)]fn propose_owner(owner: Identity) -> bool;
    /// Claim contract ownership
    #[storage(read, write)]fn claim_ownership() -> Identity;
    /// Set a new factory registry
    #[storage(read, write)]fn set_factory_registry(factory_registry: ContractId) -> bool;
    /// Set the swap fee
    #[storage(read, write)]fn set_swap_fee(swap_fee: u16) -> bool;
    /// Set the protocol fee
    #[storage(read, write)]fn set_protocol_fee(protocol_fee: u16) -> bool;
    /// Set the protocol fee receiver
    #[storage(read, write)]fn set_protocol_fee_receiver(protocol_fee_receiver: ContractId) -> bool;
    /// Add a new constant product pool
    #[storage(read, write)]fn add_pool(tokenA: ContractId, tokenB: ContractId, pool: ContractId) -> ContractId;
}
