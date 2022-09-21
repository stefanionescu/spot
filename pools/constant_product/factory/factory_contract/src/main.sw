contract;

//////////
// Imports
//////////
use std::{
    address::*,
    storage::*,
    result::*,
    reentrancy::*,
    chain::auth::*,
    context::{*, call_frames::*},
    vec::Vec,
    logging::log,
    option::Option,
    revert::require,
    identity::Identity,
    contract_id::ContractId,
    constants::{ZERO_B256, BASE_ASSET_ID}
};

use constant_product_factory_abi::errors::*;
use constant_product_factory_abi::events::*;
use constant_product_factory_abi::constants::*;
use constant_product_factory_abi::data_structures::*;
use constant_product_factory_abi::{ConstantProductFactory};

use abi_core::pool::{Pool};

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
    // The factory registry contract ID
    factory_registry: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // The total fee charged on all swaps
    swap_fee: u16 = 0,
    // The portion of the pool fee that goes to the protocol
    protocol_fee: u16 = 0,
    // The account/contract that receives the fees accumulated by all constant product pools
    protocol_fee_receiver: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // Deployed pools
    deployed_pools: StorageMap<TokenPair, ContractId> = StorageMap {},
    // Already used pool contract IDs
    used_pools: StorageMap<ContractId, bool> = StorageMap {}
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
    require(storage.owner.is_some(), AccessControlError::NoContractOwnerSet);

    let caller: Result<Identity, AuthError> = msg_sender();
    require(caller.unwrap() == storage.owner.unwrap(), AccessControlError::CallerNotContractOwner);
}

/// Checks that the method caller is either the factory registry or the contract owner
///
/// # Reverts
///
/// * When the method caller is not the factory registry or the contract owner
#[storage(read)]fn only_owner_or_factory_registry() {
    let caller: Result<Identity, AuthError> = msg_sender();

    require(
        storage.owner.is_some() && storage.owner.unwrap() == caller.unwrap() || caller.unwrap() == Identity::ContractId(storage.factory_registry),
        AccessControlError::CallerNotOwnerOrFactoryRegistry
    );
}

///////////////////
// Internal Methods
///////////////////
/// Checks if there's already a registered pool for a specific token pair
//
/// # Arguments
///
/// * `tokenA` The first token in the pair
/// * `tokenB` The second token in the pair
#[storage(read)]fn pair_exists(tokenA: ContractId, tokenB: ContractId) -> bool {
    if (tokenA == tokenB) {
        false
    } else {
        let token_pair_A: TokenPair = TokenPair {
            tokenA: tokenA,
            tokenB: tokenB
        };
        let token_pair_B: TokenPair = TokenPair {
            tokenA: tokenB,
            tokenB: tokenA
        };

        if (storage.deployed_pools.get(token_pair_A) == BASE_ASSET_ID && storage.deployed_pools.get(token_pair_B) == BASE_ASSET_ID) {
          false
        } else {
          true
        }
    }
}

impl ConstantProductFactory for Contract {
    /////////////
    // Initialize
    /////////////
    /// Instantiate the contract
    ///
    /// # Arguments
    ///
    /// * `has_owner` Whether the contract should have an initial owner or not
    /// * `factory_registry` The contract ID of the factory registry contract
    ///
    /// # Reverts
    ///
    /// * When the contract has already been initialized
    /// * When the factory registry contract ID is null
    #[storage(read, write)]fn constructor(has_owner: bool, factory_registry: ContractId, swap_fee: u16, protocol_fee: u16, protocol_fee_receiver: ContractId) {
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);
        require(N_TOKENS == 2, ParamError::InvalidNTokens);
        require(factory_registry != BASE_ASSET_ID, ParamError::NullContractID);
        require(swap_fee > 0 && swap_fee <= MAX_SWAP_FEE, ParamError::InvalidSwapFee);
        require(protocol_fee < MAX_PROTOCOL_FEE, ParamError::InvalidProtocolFee);
        require(protocol_fee_receiver != BASE_ASSET_ID, ParamError::InvalidProtocolFeeReceiver);
        require(protocol_fee_receiver != contract_id(), ParamError::ReceiverCannotBeThisContract);

        let mut current_owner: Identity = Identity::Address(~Address::from(ZERO_B256));

        if (has_owner) {
            storage.owner = Option::Some(msg_sender().unwrap());
            current_owner = msg_sender().unwrap();
        }

        storage.is_initialized        = true;
        storage.factory_registry       = factory_registry;
        storage.swap_fee              = swap_fee;
        storage.protocol_fee          = protocol_fee;
        storage.protocol_fee_receiver = protocol_fee_receiver;

        log(Initialize {
            owner: current_owner,
            factory_registry: factory_registry,
            swap_fee: swap_fee,
            protocol_fee: protocol_fee,
            protocol_fee_receiver: protocol_fee_receiver
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
        require(storage.owner.is_some(), AccessControlError::NoContractOwnerSet);

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
    /// Set a new factory registry
    ///
    /// # Arguments
    ///
    /// * `factory_registry` The ID of the factory registry contract
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner or the current factory registry contract
    /// * When the newly proposed factory registry contract ID is null or this contract
    #[storage(read, write)]fn set_factory_registry(factory_registry: ContractId) -> bool {
        only_owner_or_factory_registry();
        require(factory_registry != BASE_ASSET_ID, ParamError::NullContractID);
        require(factory_registry != contract_id(), ParamError::FactoryRegistryCannotBeThisContract);

        storage.factory_registry = factory_registry;

        log(SetFactoryRegistry {
            factory_registry: factory_registry
        });

        true
    }

    /// Set the SWAP fee
    ///
    /// # Arguments
    ///
    /// * `swap_fee` The new fee charged by the protocol on all constant product pools
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner or the current factory registry contract
    /// * When the swap fee is zero or higher than `MAX_SWAP_FEE`
    #[storage(read, write)]fn set_swap_fee(swap_fee: u16) -> bool {
        only_owner_or_factory_registry();

        require(swap_fee > 0 && swap_fee <= MAX_SWAP_FEE, ParamError::InvalidSwapFee);

        storage.swap_fee = swap_fee;

        log(SetSwapFee {
            swap_fee: swap_fee
        });

        true
    }

    /// Set the protocol fee
    ///
    /// # Arguments
    ///
    /// * `protocol_fee` The portion of the `swap_fee` that goes to the protocol
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner or the current factory registry contract
    /// * When the protocol fee is higher than `MAX_PROTOCOL_FEE`
    #[storage(read, write)]fn set_protocol_fee(protocol_fee: u16) -> bool {
        only_owner_or_factory_registry();

        require(protocol_fee < MAX_PROTOCOL_FEE, ParamError::InvalidProtocolFee);

        storage.protocol_fee = protocol_fee;

        log(SetProtocolFee {
            protocol_fee: protocol_fee
        });

        true
    }

    /// Set the protocol fee receiver
    ///
    /// # Arguments
    ///
    /// * `protocol_fee_receiver` The new protocol fee receiver
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner or the current factory registry contract
    /// * When the newly proposed protocol fee receiver is null or this contract
    #[storage(read, write)]fn set_protocol_fee_receiver(protocol_fee_receiver: ContractId) -> bool {
        only_owner_or_factory_registry();

        require(protocol_fee_receiver != BASE_ASSET_ID, ParamError::InvalidProtocolFeeReceiver);
        require(protocol_fee_receiver != contract_id(), ParamError::ReceiverCannotBeThisContract);

        storage.protocol_fee_receiver = protocol_fee_receiver;

        log(SetProtocolFeeReceiver {
            protocol_fee_receiver: protocol_fee_receiver
        });

        true
    }

    /// Add a new constant product pool in the factory registry
    ///
    /// # Arguments
    ///
    /// * `tokenA` The first token in the pair
    /// * `tokenB` The second token in the pair
    /// * `pool` The ID of the already deployed pool for the two tokens
    ///
    /// # Reverts
    ///
    /// * When the two tokens are identical
    /// * When there's already a pool registered for the token pair
    /// * When reentrancy is detected
    /// * When `pool` is null
    /// * When the pool ID returned from the `pool` is different than `POOL_ID`
    /// * When the amount of registered tokens in the `pool` is different than `N_TOKENS`
    /// * When the registered tokens are identical
    /// * When either `tokenA` or `tokenB` cannot be found in the registered tokens vector
    #[storage(read, write)]fn add_pool(tokenA: ContractId, tokenB: ContractId, pool: ContractId) -> ContractId {
        require(tokenA != tokenB, PoolAdditionError::InvalidTokenPair);
        require(pool != BASE_ASSET_ID, PoolAdditionError::NullPoolID);

        reentrancy_guard();
        require(!pair_exists(tokenA, tokenB), PoolAdditionError::PoolAlreadySet);

        // TODO: CHECK POOL CONTRACT BINARY

        let pool_contract = abi(Pool, pool.into());
        require(pool_contract.get_pool_id() == POOL_ID, PoolAdditionError::InvalidPoolID);

        require(pool_contract.decimals() <= MAX_DECIMALS, PoolAdditionError::InvalidDecimalNumber);
        require(contract_id() == pool_contract.get_factory(), PoolAdditionError::FactoryMismatch);

        let registered_tokens: Vec<ContractId> = pool_contract.get_assets();
        require(registered_tokens.len() == N_TOKENS, PoolAdditionError::InvalidNTokens);

        let registered_token_one: ContractId = registered_tokens.get(0).unwrap();
        let registered_token_two: ContractId = registered_tokens.get(1).unwrap();

        require(registered_token_one != registered_token_two, PoolAdditionError::InvalidRegisteredTokens);
        require(registered_token_one == tokenA || registered_token_one == tokenB, PoolAdditionError::InvalidFirstRegisteredToken);
        require(registered_token_two == tokenA || registered_token_two == tokenB, PoolAdditionError::InvalidSecondRegisteredToken);

        let token_pair: TokenPair = TokenPair {
            tokenA: registered_token_one,
            tokenB: registered_token_two
        };
        storage.deployed_pools.insert(token_pair, pool);
        storage.used_pools.insert(pool, true);

        log(AddPool {
            tokenA: tokenA,
            tokenB: tokenB,
            pool: pool
        });

        pool
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

    /// Return the factory registry contract ID
    #[storage(read)]fn get_factory_registry() -> ContractId {
        storage.factory_registry
    }

    /// Return the swap fee charged on this pool type
    #[storage(read)]fn get_swap_fee() -> u16 {
        storage.swap_fee
    }

    /// Return the protocol fee charged on this pool type
    #[storage(read)]fn get_protocol_fee() -> u16 {
        storage.protocol_fee
    }

    /// Return the protocol fee receiver
    #[storage(read)]fn get_protocol_fee_receiver() -> ContractId {
        storage.protocol_fee_receiver
    }

    /// Return the address of the pool contract for the two tokens
    #[storage(read)]fn get_pool(tokenA: ContractId, tokenB: ContractId) -> ContractId {
        if (tokenA == tokenB) {
            BASE_ASSET_ID
        } else {
            let token_pair: TokenPair = TokenPair {
                tokenA: tokenA,
                tokenB: tokenB
            };
            storage.deployed_pools.get(token_pair)
        }
    }

    /// Return whether a pool is already registered
    ///
    /// # Arguments
    ///
    /// * `pool` The pool to query for
    #[storage(read)]fn is_pool_used(pool: ContractId) -> bool {
        storage.used_pools.get(pool)
    }
}
