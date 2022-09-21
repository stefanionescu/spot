library fee_swapper_abi;

dep errors;
dep events;
dep constants;
dep data_structures;

use std::{identity::Identity, contract_id::ContractId, vec::Vec};

use data_structures::Bridge;

abi FeeSwapper {
    ////////////
    // Read Only
    ////////////
    /// Return the contract owner
    #[storage(read)]fn get_owner() -> Identity;
    /// Return the current proposed owner
    #[storage(read)]fn get_proposed_owner() -> Identity;
    /// Return the bridges used to swap a specific fee token to the end token
    #[storage(read)]fn get_bridges(token: ContractId) -> Vec<Bridge>;
    /// Return the ID of the router contract
    #[storage(read)]fn get_router() -> ContractId;
    /// Return the ID of the fee receiver contract
    #[storage(read)]fn get_fee_receiver() -> ContractId;
    /// Return the token to which all other fee tokens are swapped
    #[storage(read)]fn get_end_token() -> ContractId;
    /// Return the batch limit
    #[storage(read)]fn get_batch_limit() -> u8;

    //////////
    // Actions
    //////////
    /// Initialize the contract
    #[storage(read, write)]fn constructor(router: ContractId, factory_registry: ContractId, fee_receiver: ContractId, end_token: ContractId, batch_limit: u8);
    /// Propose a new owner for the contract
    #[storage(read, write)]fn propose_owner(owner: Identity) -> bool;
    /// Claim contract ownership
    #[storage(read, write)]fn claim_ownership() -> Identity;
    /// Change the router contract ID
    #[storage(read, write)]fn set_router(router: ContractId) -> bool;
    /// Change the fee receiver contract ID
    #[storage(read, write)]fn set_fee_receiver(fee_receiver: ContractId) -> bool;
    /// Set a bridge token for a specific fee token
    #[storage(read, write)]fn set_bridge(bridge_position: u8, factory: ContractId, fee_token: ContractId, bridge_token: ContractId, token_in: ContractId) -> bool;
    /// Remove a bridge for a specific fee token
    #[storage(read, write)]fn remove_bridge(fee_token: ContractId, bridge_position: u8) -> bool;
    /// Burn LP tokens and redeem underlying reserves
    #[storage(read, write)]fn redeem_fees(lp_tokens: Vec<ContractId>) -> bool;
    /// Swap fee tokens to the end token
    #[storage(read, write)]fn swap_fees(tokens: Vec<ContractId>, amounts: Vec<u64>) -> Vec<u64>;
}
