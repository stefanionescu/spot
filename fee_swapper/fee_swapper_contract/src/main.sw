contract;

//////////
// Imports
//////////
use std::{
    math::*,
    token::*,
    result::*,
    address::*,
    storage::*,
    reentrancy::*,
    chain::auth::*,
    context::{*, call_frames::*},
    vec::Vec,
    u128::U128,
    logging::log,
    option::Option,
    identity::Identity,
    contract_id::ContractId,
    revert::{require, revert},
    constants::{ZERO_B256, BASE_ASSET_ID}
};

use fee_swapper_abi::errors::*;
use fee_swapper_abi::events::*;
use fee_swapper_abi::constants::*;
use fee_swapper_abi::{FeeSwapper};
use fee_swapper_abi::data_structures::*;

use router_abi::{Router};
use router_abi::data_structures::{Path, ExactInputSingleParams, ExactInputParams};

use factory_registry_abi::{FactoryRegistry};

use abi_core::pool_factory::{PoolFactory};
use abi_core::pool::{Pool};

use abi_utils::data_structures::{DataPackage};

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
    // The router contract ID
    router: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // The factory registry contract ID
    factory_registry: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // The fee receiver contract ID
    fee_receiver: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // The token that all other fee tokens should be swapped to
    end_token: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // The max amount of different tokens to burn (to get back underlying reserves) or swap to the `end_token` in a single transaction
    batch_limit: u8 = 2,
    // Bridges set up for each fee token to be swapped to the `end_token`
    bridges: StorageMap<ContractId, Vec<Bridge>> = StorageMap {}
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
    require(contract_owner.is_some(), AccessControlError::NoContractOwnerSet);

    let caller: Result<Identity, AuthError> = msg_sender();
    require(caller.unwrap() == contract_owner.unwrap(), AccessControlError::CallerNotContractOwner);
}

/////////////////
// Internal Logic
/////////////////
/// Check if a pool has two specific tokens in it
///
/// # Arguments
///
/// * `pool` The pool to check
/// * `token0` The first token
/// * `token1` The second token
#[storage(read)]fn has_tokens(pool: ContractId, token0: ContractId, token1: ContractId) -> bool {
    let pool_contract                = abi(Pool, pool.into());
    let pool_assets: Vec<ContractId> = pool_contract.get_assets();

    let mut found_token0: bool = false;
    let mut found_token1: bool = false;

    let mut i: u64             = 0;

    while (i < pool_assets.len()) {
        if (pool_assets.get(i).unwrap() == token0) {
            found_token0 = true;
        }

        if (pool_assets.get(i).unwrap() == token1) {
            found_token1 = true;
        }

        if (found_token0 == true && found_token1 == true) {break;}

        i += 1;
    }

    (found_token0 == true && found_token1 == true)
}

/// Perform a single bridge swap
///
/// # Arguments
///
/// * `single_swap_input` The swap parameters
/// * `fee_token` The token to swap
/// * `amount_to_swap` The amount of fee tokens to swap
///
/// # Reverts
///
/// * When `amount_to_swap` is zero
/// * When `fee_receiver` does not get any new `end_token`
#[storage(read, write)]fn single_bridge_swap(single_swap_input: ExactInputSingleParams, fee_token: ContractId, amount_to_swap: u64) -> u64 {
    require(amount_to_swap > 0, SwapError::NothingToSwap);

    let mut end_token_received: u64 = 0;

    // Fetch the `end_token` balance for `fee_receiver`
    let end_token_balance: u64 = balance_of(storage.fee_receiver, storage.end_token);

    // Send fee tokens to the router
    let fee_token_balance: u64 = balance_of(contract_id(), fee_token);

    if (fee_token_balance >= amount_to_swap) {
        transfer(amount_to_swap, fee_token, Identity::ContractId(storage.router));

        // Call router to swap
        let router_id: b256 = storage.router.into();
        let router_contract = abi(Router, router_id);
        router_contract.swap_exact_input_single(single_swap_input);

        // Check that the `fee_receiver`'s balance of `end_token` increased
        end_token_received = balance_of(storage.fee_receiver, storage.end_token) - end_token_balance;
        require(end_token_received > 0, SwapError::FeeReceiverNoEndTokenIncrease);
    }

    end_token_received
}

/// Perform a multi bridge swap
///
/// # Arguments
///
/// * `multi_swap_input` The swap parameters
/// * `fee_token` The token to swap
/// * `amount_to_swap` The amount of fee tokens to swap
///
/// # Reverts
///
/// * When `amount_to_swap` is zero
/// * When `fee_receiver` does not get any new `end_token`
#[storage(read, write)]fn multi_bridge_swap(multi_swap_input: ExactInputParams, fee_token: ContractId, amount_to_swap: u64) -> u64 {
    require(amount_to_swap > 0, SwapError::NothingToSwap);

    let mut end_token_received: u64 = 0;

    // Fetch the end token balance for `fee_receiver`
    let end_token_balance: u64 = balance_of(storage.fee_receiver, storage.end_token);

    // Send fee tokens to the router
    let fee_token_balance: u64 = balance_of(contract_id(), fee_token);

    if (fee_token_balance >= amount_to_swap) {
        transfer(amount_to_swap, fee_token, Identity::ContractId(storage.router));

        // Call router to swap
        let router_id: b256 = storage.router.into();
        let router_contract = abi(Router, router_id);
        router_contract.swap_exact_input(multi_swap_input);

        // Check that the `fee_receiver`'s balance of `end_token` increased
        end_token_received = balance_of(storage.fee_receiver, storage.end_token) - end_token_balance;
        require(end_token_received > 0, SwapError::FeeReceiverNoEndTokenIncrease);
    }

    end_token_received
}

//////////////////////
// Core Implementation
//////////////////////
impl FeeSwapper for Contract {
    /////////////
    // Initialize
    /////////////
    /// Instantiate the contract
    ///
    /// # Arguments
    ///
    /// * `router` The contract ID for the protocol's router
    /// * `factory_registry` The ID of the factory registry contract
    /// * `fee_receiver` The contract ID for the fee receiver (contract that gets `end_token`)
    /// * `end_token` The token that all other fee tokens are swapped to
    /// * `batch_limit` The max amount of different LP tokens to burn (to get back underlying reserves) or max amount of different fee tokens to swap in a single transaction
    ///
    /// # Reverts
    ///
    /// * When the contract is already initialized
    /// * When the `router` ID is null
    /// * When the `factory_registry` ID is null
    /// * When the `fee_receiver` ID is null
    /// * When the `end_token` is the ID of this contract
    /// * When the `batch_limit` is smaller than `TWO_U8` or higher than `MAX_BATCH_LIMIT`
    #[storage(read, write)]fn constructor(router: ContractId, factory_registry: ContractId, fee_receiver: ContractId, end_token: ContractId, batch_limit: u8) {
        require(MAX_BATCH_LIMIT >= TWO_U8, ParamError::InvalidMaxBatchLimit);
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);
        require(router != BASE_ASSET_ID, ParamError::NullRouter);
        require(factory_registry != BASE_ASSET_ID, ParamError::NullFactoryRegistry);
        require(fee_receiver != BASE_ASSET_ID, ParamError::NullFeeReceiver);
        require(end_token != contract_id(), ParamError::InvalidEndToken);
        require(batch_limit >= TWO_U8 && batch_limit <= MAX_BATCH_LIMIT, ParamError::InvalidBatchLimit);
        require(MAX_BRIDGES > 1, ParamError::InvalidMaxBridges);

        storage.is_initialized  = true;
        storage.router          = router;
        storage.factory_registry = factory_registry;
        storage.fee_receiver    = fee_receiver;
        storage.end_token       = end_token;
        storage.batch_limit     = batch_limit;
        storage.owner           = Option::Some(msg_sender().unwrap());

        log(Initialize {
            owner: storage.owner.unwrap(),
            router: storage.router,
            factory_registry: factory_registry,
            fee_receiver: storage.fee_receiver,
            end_token: storage.end_token,
            batch_limit: storage.batch_limit
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

    /// Change the router contract ID
    ///
    /// # Arguments
    ///
    /// * `router` The new router contract ID
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the `router` is null
    #[storage(read, write)]fn set_router(router: ContractId) -> bool {
        only_owner();
        require(router != BASE_ASSET_ID, ParamError::NullRouter);

        storage.router = router;

        log(SetRouter {
            router: router
        });

        true
    }

    /// Change the fee receiver contract ID
    ///
    /// # Arguments
    ///
    /// * `fee_receiver` The new fee receiver contract ID
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the `fee_receiver` is null
    #[storage(read, write)]fn set_fee_receiver(fee_receiver: ContractId) -> bool {
        only_owner();

        require(fee_receiver != BASE_ASSET_ID, ParamError::NullFeeReceiver);

        storage.fee_receiver = fee_receiver;

        log(SetFeeReceiver {
            fee_receiver: fee_receiver
        });

        true
    }

    /// Set a bridge token for a specific fee token
    ///
    /// # Arguments
    ///
    /// * `bridge_position` The order in which this `bridge_token` will be used
    /// * `factory` The ID of the factory in which there's a pool containing the `fee_token` and the `bridge_token`
    /// * `fee_token` The fee token for which to set up a bridge
    /// * `bridge_token` The ID of the token to use
    /// * `token_in` The token to swap in the bridge pool
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the `factory` is this contract or null
    /// * When the `fee_token` is this contract
    /// * When the `bridge_position` is above or equal to `MAX_BRIDGES`
    /// * When the `fee_token` is the same as the `bridge_token`
    /// * When `token_in` is the `end_token`
    /// * When `token_in` is not the `fee_token` in case `bridge_position` is zero
    /// * When there's no pool between `fee_token` and `bridge_token`
    /// * When the `factory` that holds the bridge pool  is not whitelisted in the `factory_registry`
    /// * When any bridge in an index prior to `bridge_position` is not set (there's a gap between bridges)
    /// * When `bridge_token` has already been used for `fee_token`
    #[storage(read, write)]fn set_bridge(bridge_position: u8, factory: ContractId, fee_token: ContractId, bridge_token: ContractId, token_in: ContractId) -> bool {
        only_owner();

        require(factory != BASE_ASSET_ID && factory != contract_id(), ParamError::InvalidFactory);
        require(fee_token != contract_id(), ParamError::InvalidFeeToken);
        require(bridge_position <= MAX_BRIDGES - 1, ParamError::InvalidBridgePosition);
        require(fee_token != bridge_token, ParamError::BridgeSameAsFeeToken);
        require(token_in != storage.end_token, ParamError::TokenInCannotBeEndToken);

        if (bridge_position == 0) {
            require(fee_token == token_in, ParamError::InvalidTokenIn);
        }

        let mut i: u64                       = 0;
        let default_bridge: Bridge           = Bridge {
            factory: contract_id(),
            pool: contract_id(),
            token_in: contract_id()
        };

        if (storage.bridges.get(fee_token).len() == 0) {
            while (i < MAX_BRIDGES) {
                storage.bridges.get(fee_token).push(default_bridge);
                i += 1;
            }
        }

        let bridges: Vec<Bridge> = storage.bridges.get(fee_token);

        let factory_id: b256        = factory.into();
        let factory_contract        = abi(PoolFactory, factory_id);
        let bridge_pool: ContractId = factory_contract.get_pool(fee_token, bridge_token);

        require(bridge_pool != BASE_ASSET_ID, BridgeError::NoPoolForBridgeToken);

        let factory_registry_contract     = abi(FactoryRegistry, storage.factory_registry.into());
        require(factory_registry_contract.is_whitelisted(factory.into()), BridgeError::FactoryNotRegistered);

        i = 0;
        while (i < bridge_position) {
            require(
                bridges.get(i).unwrap().factory != contract_id() &&
                bridges.get(i).unwrap().token_in != contract_id(),
                BridgeError::PreviousBridgeNotSet
            );
            require(bridges.get(i).unwrap().pool != bridge_pool, BridgeError::SameBridgeTwice);

            i += 1;
        }

        i += 1;
        while (i < MAX_BRIDGES) {
            require(bridges.get(i).unwrap().pool != bridge_pool, BridgeError::SameBridgeTwice);
            i += 1;
        }

        let new_bridge: Bridge = Bridge {
            factory: factory,
            pool: bridge_pool,
            token_in: token_in
        };
        storage.bridges.get(fee_token).insert(bridge_position, new_bridge);

        log(SetBridge {
            bridge_position: bridge_position,
            fee_token: fee_token,
            bridge_token: bridge_token,
            bridge_pool: bridge_pool,
            factory: factory,
            token_in: token_in
        });

        true
    }

    /// Remove a bridge for a specific fee token
    ///
    /// # Arguments
    ///
    /// * `fee_token` The fee token for which to remove the bridge
    /// * `bridge_position` The position of the bridge that will get removed
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the contract owner
    /// * When the `fee_token` is this contract
    /// * When the `bridge_position` is above or equal to `MAX_BRIDGES`
    /// * When no bridge has been set before for `fee_token`
    #[storage(read, write)]fn remove_bridge(fee_token: ContractId, bridge_position: u8) -> bool {
        only_owner();

        require(fee_token != contract_id(), ParamError::InvalidFeeToken);
        require(bridge_position <= MAX_BRIDGES - 1, ParamError::InvalidBridgePosition);
        require(storage.bridges.get(fee_token).len() == MAX_BRIDGES, BridgeError::UninitializedBridges);

        let mut i                    = 0;
        let default_bridge: Bridge   = Bridge {
            factory: contract_id(),
            pool: contract_id(),
            token_in: contract_id()
        };

        while (i < MAX_BRIDGES || storage.bridges.get(fee_token).get(bridge_position).unwrap().factory != contract_id()) {
            storage.bridges.get(fee_token).remove(bridge_position);
            storage.bridges.get(fee_token).push(default_bridge);

            i += 1;
        }

        log(RemoveBridge {
            fee_token: fee_token,
            bridge_position: bridge_position
        });

        true
    }

    /// Burn LP tokens and redeem underlying reserves
    ///
    /// # Arguments
    ///
    /// * `lp_tokens` The array of LP tokens to burn and withdraw liquidity with
    ///
    /// # Reverts
    ///
    /// * When `lp_tokens`'s length is zero or above MAX_BATCH_LIMIT
    /// * When reentrancy is detected
    /// * When there are leftover LP tokens in this contract after trying to burn them and withdraw liquidity
    /// * When no underlying amount of tokens were received from burning LP tokens
    #[storage(read, write)]fn redeem_fees(lp_tokens: Vec<ContractId>) -> bool {
        require(lp_tokens.len() > 0, ParamError::NullVector);
        require(lp_tokens.len() <= MAX_BATCH_LIMIT, LPError::LPVectorTooLong);

        reentrancy_guard();

        // Prepare all local vars
        let mut i: u64                       = 0;
        let mut j: u64                       = 0;
        let mut lp_token_balance: u64        = 0;
        let mut underlying_amounts: Vec<u64> = ~Vec::new();
        let mut pool_assets: Vec<ContractId> = ~Vec::new();

        let router_contract                  = abi(Router, storage.router.into());

        let mut min_withdrawals: Vec<u64>    = ~Vec::new();
        let data_package: DataPackage        = DataPackage {
            identities: ~Vec::new(),
            contract_ids: ~Vec::new(),
            amounts: ~Vec::new(),
            flags: ~Vec::new()
        };

        data_package.identities.push(Identity::ContractId(contract_id()));

        // If there's no bridge yet for this fee token, initialize them all to null
        while (i < MAX_TOKENS_PER_POOL) {
            min_withdrawals.push(1);
        }

        i = 0;

        // Start to loop through all LP tokens
        while (i < lp_tokens.len()) {
            lp_token_balance = balance_of(contract_id(), lp_tokens.get(i).unwrap());

            // If an LP token balance is non null
            if (lp_token_balance > 0) {
                let pool_id: b256 = lp_tokens.get(i).unwrap().into();
                let pool_contract = abi(Pool, pool_id);
                pool_assets       = pool_contract.get_assets();

                j = 0;
                // Record current token balances for all tokens in the current pool we loop through
                while (j < pool_assets.len()) {
                    underlying_amounts.push(balance_of(contract_id(), pool_assets.get(j).unwrap()));
                    j += 1;
                }

                // Burn LP tokens using the router and withdraw liquidity
                transfer(lp_token_balance, lp_tokens.get(i).unwrap(), Identity::ContractId(storage.router));
                require(balance_of(contract_id(), lp_tokens.get(i).unwrap()) == 0, LPError::LeftoverLPTokens);
                router_contract.burn_liquidity(lp_tokens.get(i).unwrap(), lp_token_balance, data_package, min_withdrawals);

                j = 0;
                // Check that we received a non null amount of each token in the current pool
                while (j < pool_assets.len()) {
                    require(balance_of(contract_id(), pool_assets.get(j).unwrap()) - underlying_amounts.get(j).unwrap() > 0, LPError::NoUnderlyingReceived);
                    j += 1;
                }

                // Wipe local vars
                pool_assets.clear();
                underlying_amounts.clear();
            }

            // Continue looping
            i += 1;
        }

        log(RedeemFees {
            lp_tokens: lp_tokens
        });

        true
    }

    /// Swap fee tokens to the end token
    ///
    /// # Arguments
    ///
    /// * `tokens` The fee tokens to swap
    /// * `amounts` The amounts of tokens to swap
    ///
    /// * Reverts
    ///
    /// * When the amount of fee tokens to swap is zero
    /// * When the `tokens` and `amounts` arrays have different lengths
    /// * When reentrancy is detected
    /// * When the amount of tokens to swap is higher than this contract's balance of that specific token
    /// * When the bridge path doesn't have at least one element (or two in case of multi bridge paths)
    /// * When a bridge path does not end up swapping to the `end_token`
    #[storage(read, write)]fn swap_fees(tokens: Vec<ContractId>, amounts: Vec<u64>) -> Vec<u64> {
        require(tokens.len() > 0, ParamError::NullVector);
        require(tokens.len() == amounts.len(), ParamError::MismatchedVectorLengths);

        reentrancy_guard();

        // Prepare all local vars
        let mut i: u64                                    = 0;
        let mut amount_to_transfer: u64                   = 0;
        let mut out_amounts: Vec<u64>                     = ~Vec::new();
        let data_package: DataPackage                     = DataPackage {
            identities: ~Vec::new(),
            contract_ids: ~Vec::new(),
            amounts: ~Vec::new(),
            flags: ~Vec::new()
        };
        let mut single_swap_input: ExactInputSingleParams = ExactInputSingleParams {
            amount_in: 0,
            amount_out_minimum: 1,
            factory: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            pool: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            token_in: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            data: data_package
        };
        let mut multi_swap_input: ExactInputParams        = ExactInputParams {
            amount_in: 0,
            amount_out_minimum: 1,
            token_in: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            path: ~Vec::new()
        };
        let mut path: Path                                = Path {
            factory: BASE_ASSET_ID,
            pool: BASE_ASSET_ID,
            data: data_package
        };

        // Start looping through all fee tokens
        while (i < tokens.len()) {
            // Check if the fee token is the end token and if yes, simply transfer to `fee_receiver`
            if (tokens.get(i).unwrap() == storage.end_token) {
                // Get the total amount of `end_token` to transfer
                amount_to_transfer = balance_of(contract_id(), storage.end_token);

                // Transfer the tokens to the `fee_receiver` (if the amount is not null)
                if (amount_to_transfer > 0) {
                    transfer(amount_to_transfer, storage.end_token, Identity::ContractId(storage.fee_receiver));
                }

                // Record the amount of tokens that were transferred
                out_amounts.push(amount_to_transfer);
            } else {
                // Check that there's at least one bridge
                let bridges: Vec<Bridge> = storage.bridges.get(tokens.get(i).unwrap());
                require(bridges.get(ZERO_U64).unwrap().factory != contract_id(), SwapError::NoBridgePath);

                // In case there's a single bridge
                if (bridges.get(ONE_U64).unwrap().factory == contract_id()) {
                    // Check that the pool has both the `fee_token` and the `end_token` in it
                    require(has_tokens(bridges.get(ZERO_U64).unwrap().pool, storage.end_token, tokens.get(i).unwrap()), SwapError::CannotSwapToEndToken);

                    // Set up `data_package` and `single_swap_input`
                    data_package.contract_ids.push(tokens.get(i).unwrap());
                    data_package.identities.push(Identity::ContractId(storage.fee_receiver));

                    single_swap_input = ExactInputSingleParams {
                        amount_in: amounts.get(i).unwrap(),
                        amount_out_minimum: ONE_U64,
                        factory: bridges.get(ZERO_U64).unwrap().factory,
                        pool: bridges.get(ZERO_U64).unwrap().pool,
                        token_in: tokens.get(i).unwrap(),
                        data: data_package
                    };

                    out_amounts.push(single_bridge_swap(single_swap_input, tokens.get(i).unwrap(), amounts.get(i).unwrap()));
                } else {
                    // Handle the multi bridge path
                    // Loop through all bridges and create the path
                    let mut j: u64 = 0;

                    multi_swap_input.amount_in          = amounts.get(i).unwrap();
                    multi_swap_input.token_in           = tokens.get(i).unwrap();
                    multi_swap_input.amount_out_minimum = ONE_U64;

                    while (j < bridges.len() && bridges.get(j).unwrap().factory != contract_id()) {
                        // For the last bridge, check that `end_token` and `token_in` are there
                        if (j + 1 == bridges.len() || bridges.get(j + 1).unwrap().factory == contract_id()) {
                            require(has_tokens(bridges.get(j).unwrap().pool, storage.end_token, bridges.get(j).unwrap().token_in), SwapError::CannotSwapToEndToken);
                        }

                        // Need to make sure the first token to swap is the fee token we currently loop through
                        if (j == 0) {
                            require(tokens.get(i).unwrap() == bridges.get(ZERO_U64).unwrap().token_in, SwapError::InvalidStartingToken);
                        }

                        // Set `token_in` in the `data_package` `contract_ids` and either the next pool in the path or the `fee_receiver` in the `identities`
                        data_package.contract_ids.push(bridges.get(j).unwrap().token_in);

                        if (j == bridges.len() - 1 || bridges.get(j + 1).unwrap().factory == contract_id()) {
                            data_package.identities.push(Identity::ContractId(storage.fee_receiver));
                        } else {
                            data_package.identities.push(Identity::ContractId(bridges.get(j + 1).unwrap().pool));
                        }

                        // Set the `data_package` in the `path`
                        path.data = data_package;

                        // Set the `factory` and `pool` in the `path`
                        path.factory = bridges.get(j).unwrap().factory;
                        path.pool    = bridges.get(j).unwrap().pool;

                        // Push the `path` in `multi_swap_input`
                        multi_swap_input.path.push(path);

                        // Clear out `contract_ids` and `identities` from `data_package`
                        data_package.identities.clear();
                        data_package.contract_ids.clear();

                        j += 1;
                    }

                    out_amounts.push(multi_bridge_swap(multi_swap_input, tokens.get(i).unwrap(), amounts.get(i).unwrap()));
                }

                // Wipe local vars
                data_package.identities.clear();
                data_package.contract_ids.clear();

                path             = Path {
                    factory: BASE_ASSET_ID,
                    pool: BASE_ASSET_ID,
                    data: data_package
                };

                multi_swap_input = ExactInputParams {
                    amount_in: 0,
                    amount_out_minimum: 1,
                    token_in: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
                    path: ~Vec::new()
                };
            }

            // Continue looping through fee tokens
            i += 1;
        }

        log(SwapFees {
            tokens: tokens,
            in_amounts: amounts,
            out_amounts: out_amounts
        });

        out_amounts
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

    /// Return the bridges used to swap a specific fee token to the target token
    #[storage(read)]fn get_bridges(token: ContractId) -> Vec<Bridge> {
        storage.bridges.get(token)
    }

    /// Return the ID of the router contract
    #[storage(read)]fn get_router() -> ContractId {
        storage.router
    }

    /// Return the ID of the fee receiver contract
    #[storage(read)]fn get_fee_receiver() -> ContractId {
        storage.fee_receiver
    }

    /// Return the token to which all other fee tokens are swapped
    #[storage(read)]fn get_end_token() -> ContractId {
        storage.end_token
    }

    /// Return the batch limit
    #[storage(read)]fn get_batch_limit() -> u8 {
        MAX_BATCH_LIMIT
    }
}
