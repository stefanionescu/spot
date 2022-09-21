contract;

//////////
// Imports
//////////
use std::{
    address::*,
    storage::*,
    result::*,
    chain::auth::*,
    context::{*, call_frames::*},
    logging::log,
    option::Option,
    revert::require,
    contract_id::ContractId,
    identity::Identity,
    constants::{ZERO_B256, BASE_ASSET_ID}
};

use factory_registry_abi::errors::*;
use factory_registry_abi::events::*;
use factory_registry_abi::constants::*;
use factory_registry_abi::{FactoryRegistry};

use abi_core::pool_factory::{PoolFactory};

///////////
/// Storage
///////////
storage {
    // Whether the contract has already been initialized
    is_initialized: bool = false,
    // The contract owner
    owner: Option<Identity> = Option::None,
    // Newly proposed contract owner
    proposed_owner: Option<Identity> = Option::None,
    // Whitelisted factories
    whitelisted_factories: StorageMap<b256, bool> = StorageMap {}
}

/////////////////
// Access Control
/////////////////
/// Checks that the method caller is the contract owner
///
/// # Reverts
///
/// * When the contract does not have an owner
/// * When the method caller is not the contract owner
#[storage(read)]fn only_owner() {
    let contract_owner = storage.owner;

    let caller: Result<Identity, AuthError> = msg_sender();
    require(caller.unwrap() == contract_owner.unwrap(), AccessControlError::CallerNotContractOwner);
}

//////////////////////
// Core Implementation
//////////////////////
impl FactoryRegistry for Contract {
    /////////////
    // Initialize
    /////////////
    /// Instantiate the contract
    ///
    /// # Reverts
    ///
    /// * When the contract is already initialized
    #[storage(read, write)]fn constructor() {
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);

        storage.owner = Option::Some(msg_sender().unwrap());
        storage.is_initialized = true;

        log(Initialize {
            owner: storage.owner.unwrap()
        });
    }

    ////////////
    // Ownership
    ////////////
    /// Propose a new contract owner
    ///
    /// # Arguments
    ///
    /// * `owner` The newly proposed contract owner
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    #[storage(read, write)]fn propose_owner(owner: Identity) -> bool {
        only_owner();

        if (owner == storage.owner.unwrap()) {
            storage.proposed_owner = Option::None;
        } else {
            storage.proposed_owner = Option::Some(owner);
        }

        log(ProposeOwner {
            proposed_owner: owner
        });

        true
    }

    /// Claim contract ownership
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the proposed contract owner
    /// * When there is no proposed contract owner
    #[storage(read, write)]fn claim_ownership() -> Identity {
        let caller: Result<Identity, AuthError> = msg_sender();
        require(storage.proposed_owner.is_some() && caller.unwrap() == storage.proposed_owner.unwrap(), AccessControlError::CallerNotProposedOwner);

        storage.owner          = Option::Some(storage.proposed_owner.unwrap());
        storage.proposed_owner = Option::None;

        log(ClaimOwnership {
            owner: storage.owner.unwrap()
        });

        storage.owner.unwrap()
    }

    ///////////////
    // Modify State
    ///////////////
    /// Whitelist a factory
    ///
    /// # Arguments
    ///
    /// * `factory` The address of the factory to whitelist
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    #[storage(read, write)]fn add_to_whitelist(factory: b256) -> bool {
        only_owner();

        storage.whitelisted_factories.insert(factory, true);

        log(AddToWhitelist {
            factory: factory
        });

        true
    }

    /// Remove a factory from whitelist
    ///
    /// # Arguments
    ///
    /// * `factory` The address of the factory to whitelist
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    #[storage(read, write)]fn remove_from_whitelist(factory: b256) -> bool {
        only_owner();

        storage.whitelisted_factories.insert(factory, false);

        log(RemoveFromWhitelist {
            factory: factory
        });

        true
    }

    /// Set the protocol fee for a factory
    ///
    /// # Arguments
    ///
    /// * `factory` The factory to set the protocol fee for
    /// * `fee` The fee to set in the factory
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the factory is not whitelisted
    /// * When the `fee` is higher than or equal to MAX_FEE
    /// * When setting the fee returns `false` from the `factory`
    #[storage(read, write)]fn set_protocol_fee(factory: b256, fee: u16) -> bool {
        only_owner();

        require(storage.whitelisted_factories.get(factory) == true, ParamError::NotWhitelisted);
        require(fee < MAX_FEE, ParamError::InvalidProtocolFee);

        let pool_factory               = abi(PoolFactory, factory);
        let set_fee_confirmation: bool = pool_factory.set_protocol_fee(fee);

        require(set_fee_confirmation, FactoryError::CannotSetProtocolFee);

        log(SetProtocolFee {
            factory: factory,
            fee: fee
        });

        set_fee_confirmation
    }

    /// Set the protocol fee receiver for a factory
    ///
    /// # Arguments
    ///
    /// * `factory` The factory to set the protocol fee for
    /// * `fee_receiver` The fee receiver to set in the factory
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the `factory` is not whitelisted
    /// * When the `fee_receiver` is null or this contract
    /// * When setting the `fee_receiver` returns `false` from the `factory`
    #[storage(read, write)]fn set_protocol_fee_receiver(factory: b256, fee_receiver: Identity) -> bool {
        only_owner();

        require(storage.whitelisted_factories.get(factory) == true, ParamError::NotWhitelisted);
        require(fee_receiver != Identity::Address(~Address::from(ZERO_B256)) && fee_receiver != Identity::ContractId(BASE_ASSET_ID), ParamError::NullReceiver);
        require(fee_receiver != Identity::ContractId(contract_id()), ParamError::ReceiverCannotBeThisContract);

        let pool_factory                        = abi(PoolFactory, factory);
        let set_fee_receiver_confirmation: bool = pool_factory.set_protocol_fee_receiver(fee_receiver);

        require(set_fee_receiver_confirmation, FactoryError::CannotSetProtocolFeeReceiver);

        log(SetProtocolFeeReceiver {
            factory: factory,
            fee_receiver: fee_receiver
        });

        set_fee_receiver_confirmation
    }

    /// Remove a pool from a factory registry
    ///
    /// # Arguments
    ///
    /// * `factory` The factory where the target pool is registered
    /// * `tokenA` The first token in the pair
    /// * `tokenB` The second token in the pair
    ///
    /// # Reverts
    ///
    /// * When the `factory` is not whitelisted
    /// * When any check on the pool or factory side fails
    #[storage(read, write)]fn remove_pool(factory: b256, tokenA: ContractId, tokenB: ContractId) -> bool {
        only_owner();

        require(storage.whitelisted_factories.get(factory) == true, ParamError::NotWhitelisted);

        let pool_factory = abi(PoolFactory, factory);
        pool_factory.remove_pool(tokenA, tokenB)
    }

    /// Start ramping A up or down for a specific (stable) pool
    ///
    /// # Arguments
    ///
    /// * `factory` The factory where the target pool is registered
    /// * `tokenA` The first token in the pair
    /// * `tokenB` The second token in the pair
    /// * `next_A` The future value for `A`
    /// * `ramp_end_time` The timestamp when ramping A finalizes
    ///
    /// # Reverts
    ///
    /// * When the pool is not registered in the factory
    /// * When the `factory` is not whitelisted
    /// * When any check on the pool or factory side fails
    #[storage(read, write)]fn start_ramp_a(factory: b256, tokenA: ContractId, tokenB: ContractId, next_A: u64, ramp_end_time: u64) -> bool {
        only_owner();

        require(storage.whitelisted_factories.get(factory) == true, ParamError::NotWhitelisted);

        let pool_factory = abi(PoolFactory, factory);
        pool_factory.start_ramp_a(tokenA, tokenB, next_A, ramp_end_time)
    }

    /// Stop ramping A up or down for a specific (stable) pool
    ///
    /// # Arguments
    ///
    /// * `factory` The factory where the target pool is registered
    /// * `tokenA` The first token in the pair
    /// * `tokenB` The second token in the pair
    ///
    /// # Reverts
    ///
    /// * When any check on the pool or factory side fails
    /// * When the `factory` is not whitelisted
    #[storage(read, write)]fn stop_ramp_a(factory: b256, tokenA: ContractId, tokenB: ContractId) -> bool {
        only_owner();

        require(storage.whitelisted_factories.get(factory) == true, ParamError::NotWhitelisted);

        let pool_factory = abi(PoolFactory, factory);
        pool_factory.stop_ramp_a(tokenA, tokenB)
    }

    //////////
    // Getters
    //////////
    /// Return the current contract owner
    #[storage(read)]fn get_owner() -> Identity {
        let contract_owner: Option<Identity> = storage.owner;
        if contract_owner.is_some() {
            contract_owner.unwrap()
        } else {
            Identity::Address(~Address::from(ZERO_B256))
        }
    }

    /// Return the current proposed contract owner
    #[storage(read)]fn get_proposed_owner() -> Identity {
        let proposed_contract_owner: Option<Identity> = storage.proposed_owner;
        if proposed_contract_owner.is_some() {
            proposed_contract_owner.unwrap()
        } else {
            Identity::Address(~Address::from(ZERO_B256))
        }
    }

    /// Return whether a factory is whitelisted or not
    ///
    /// # Arguments
    ///
    /// * `factory` The factory to query for
    #[storage(read)]fn is_whitelisted(factory: b256) -> bool {
        storage.whitelisted_factories.get(factory)
    }
}
