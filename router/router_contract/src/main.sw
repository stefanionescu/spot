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
    chain::auth::*,
    context::{*, call_frames::*},
    vec::Vec,
    logging::log,
    identity::Identity,
    contract_id::ContractId,
    revert::{require, revert},
    constants::{ZERO_B256, BASE_ASSET_ID}
};

use router_abi::{Router};
use router_abi::errors::*;
use router_abi::events::*;
use router_abi::constants::*;
use router_abi::data_structures::*;

use abi_core::pool::{Pool};
use abi_core::pool_factory::{PoolFactory};

use abi_utils::data_structures::{DataPackage};

use factory_registry_abi::{FactoryRegistry};

///////////
/// Storage
///////////
storage {
    // Whether the contract has already been initialized
    is_initialized: bool = false,
    // The ID of the factory registry contract
    factory_registry: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000)
}

//////////////////////
// Core Implementation
//////////////////////
impl Router for Contract {
    /////////////
    // Initialize
    /////////////
    /// Instantiate the contract
    ///
    /// # Arguments
    ///
    /// * `factory_registry` The ID of the factory registry contract
    ///
    /// # Reverts
    ///
    /// * When the contract is already initialized
    /// * When the factory registry ID is null
    #[storage(read, write)]fn constructor(factory_registry: ContractId) {
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);
        require(factory_registry != BASE_ASSET_ID, ParamError::NullFactoryRegistry);

        storage.factory_registry = factory_registry;
        storage.is_initialized  = true;

        log(Initialize {
            factory_registry: factory_registry
        });
    }

    ///////////////
    // Modify State
    ///////////////
    /// Swaps token A to token B directly
    ///
    /// # Arguments
    ///
    /// * `params` All the swap parameters packed in a single struct
    ///
    /// # Reverts
    ///
    /// * When the amount to swap is null
    /// * When the minimum amount to receive is null
    /// * When the factory or the pool IDs are null
    /// * When the factory is not whitelisted in the `factory_registry`
    /// * When the pool to swap in is not registered in the factory
    /// * When this contract cannot transfer tokens to the pool
    /// * When the amount of tokens received is smaller than `amount_out_minimum`
    #[storage(read, write)]fn swap_exact_input_single(params: ExactInputSingleParams) -> u64 {
        require(params.amount_in > 0, InputErrors::NullAmountIn);
        require(params.amount_out_minimum > 0, InputErrors::NullMinAmountOut);
        require(params.factory != BASE_ASSET_ID, InputErrors::NullFactory);
        require(params.pool != BASE_ASSET_ID, InputErrors::NullPool);
        require(balance_of(contract_id(), params.token_in) >= params.amount_in, BalanceError::NotEnoughTokensToSwap);

        let factory_registry_id: b256 = storage.factory_registry.into();
        let factory_registry_contract = abi(FactoryRegistry, factory_registry_id);
        let factory_contract         = abi(PoolFactory, params.factory.into());

        require(factory_registry_contract.is_whitelisted(params.factory.into()), WhitelistError::FactoryNotRegistered);
        require(factory_contract.is_pool_used(params.pool), WhitelistError::PoolNotRegistered);

        let balance_pre_transfer: u64 = balance_of(params.pool, params.token_in);
        transfer(params.amount_in, params.token_in, Identity::ContractId(params.pool));
        require(balance_of(params.pool, params.token_in) - params.amount_in == balance_pre_transfer, TransferError::CannotTransferToPool);

        let pool_contract = abi(Pool, params.pool.into());
        let amount_out    = pool_contract.swap(params.data);
        require(params.amount_out_minimum <= amount_out, OutputErrors::TooLittleReceived);

        amount_out
    }

    /// Swaps token A to token B indirectly by using multiple hops
    ///
    /// # Arguments
    ///
    /// * `params` All the swap parameters packed in a single struct
    ///
    /// # Reverts
    ///
    /// * When the amount to swap is null
    /// * When the minimum amount to receive is null
    /// * When any of the `factory` or `pool` IDs are null
    /// * When any of the factories are not whitelisted in the `factory_registry`
    /// * When any of the pools in the path is not registered in their associated factories
    /// * When this contract cannot transfer tokens to the first pool
    /// * When the amount of tokens received in the end is smaller than `amount_out_minimum`
    #[storage(read, write)]fn swap_exact_input(params: ExactInputParams) -> u64 {
        require(params.amount_in > 0, InputErrors::NullAmountIn);
        require(params.amount_out_minimum > 0, InputErrors::NullMinAmountOut);
        require(balance_of(contract_id(), params.token_in) >= params.amount_in, BalanceError::NotEnoughTokensToSwap);
        require(params.path.len() > ONE, InputErrors::InvalidPathLength);

        let factory_registry_contract = abi(FactoryRegistry, storage.factory_registry.into());

        let mut path_index: u64    = 0;
        let mut amount_out: u64    = 0;
        let mut converted_id: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000;

        while (path_index < params.path.len()) {
            let current_path: Path = params.path.get(path_index).unwrap();
            require(current_path.factory != BASE_ASSET_ID, InputErrors::NullFactory);
            require(current_path.pool != BASE_ASSET_ID, InputErrors::NullPool);

            let factory_contract = abi(PoolFactory, current_path.factory.into());
            require(factory_contract.is_pool_used(current_path.pool), WhitelistError::PoolNotRegistered);

            if (path_index == 0) {
                let balance_pre_transfer: u64 = balance_of(current_path.pool, params.token_in);
                transfer(params.amount_in, params.token_in, Identity::ContractId(current_path.pool));
                require(balance_of(current_path.pool, params.token_in) - params.amount_in == balance_pre_transfer, TransferError::CannotTransferToPool);
            }

            let pool_contract = abi(Pool, converted_id);
            amount_out        = pool_contract.swap(current_path.data);

            path_index += 1;
        }

        require(params.amount_out_minimum <= amount_out, OutputErrors::TooLittleReceived);

        amount_out
    }

    /// Add liquidity into a pool
    ///
    /// # Arguments
    ///
    /// * `token_input` An array of tokens & amounts to LP
    /// * `factory` The factory contract in which the pool is registered
    /// * `pool` The pool to LP into
    /// * `min_liquidity` The minimum amount of LP tokens to get back
    /// * `data` The data used to LP in the pool
    ///
    /// # Reverts
    ///
    /// * When the `factory` or the `pool` are null
    /// * When `min_liquidity` is null
    /// * When the `token_input` has less than two elements
    /// * When the factory is not whitelisted in the `factory_registry`
    /// * When the pool to add liquidity in is not registered in the `factory`
    /// * When any of the specified tokens cannot be transferred to the pool contract
    /// * When the amount of minted liquidity is smaller than `min_liquidity`
    #[storage(read, write)]fn add_liquidity(token_input: Vec<TokenInput>, factory: ContractId, pool: ContractId, min_liquidity: u64, data: DataPackage) -> u64 {
        require(factory != BASE_ASSET_ID, InputErrors::NullFactory);
        require(pool != BASE_ASSET_ID, InputErrors::NullPool);
        require(min_liquidity > 0, InputErrors::NullMinLiquidity);
        require(token_input.len() > ONE, InputErrors::InvalidTokenInputLength);

        let factory_registry_id: b256 = storage.factory_registry.into();
        let factory_registry_contract = abi(FactoryRegistry, factory_registry_id);
        let factory_contract         = abi(PoolFactory, factory.into());

        require(factory_registry_contract.is_whitelisted(factory.into()), WhitelistError::FactoryNotRegistered);
        require(factory_contract.is_pool_used(pool), WhitelistError::PoolNotRegistered);

        let mut path_index: u64                 = 0;
        let mut current_token_input: TokenInput = TokenInput {
            token: ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
            amount: 0
        };

        while (path_index < token_input.len()) {
            current_token_input = token_input.get(path_index).unwrap();

            let balance_pre_transfer: u64 = balance_of(pool, current_token_input.token);
            transfer(current_token_input.amount, current_token_input.token, Identity::ContractId(pool));
            require(balance_of(pool, current_token_input.token) - current_token_input.amount == balance_pre_transfer, TransferError::CannotTransferToPool);

            path_index += 1;
        }

        let pool_contract  = abi(Pool, pool.into());
        let liquidity: u64 = pool_contract.mint(data);

        require(min_liquidity <= liquidity, OutputErrors::NotEnoughLiquidityMinted);

        liquidity
    }

    /// Burn LP tokens and get back liquidity
    ///
    /// # Arguments
    ///
    /// * `pool` The pool to withdraw from
    /// * `liquidity` The amount of LP tokens to burn
    /// * `data` The data used to withdraw from the pool
    /// * `min_withdrawals` The minimum amounts of tokens to get back
    ///
    /// # Reverts
    ///
    /// * When the `pool` is null
    /// * When `liquidity` is zero
    /// * When LP tokens cannot be transferred to the pool
    /// * When any element in `withdrawn_amounts` is smaller than the amount of that associated token withdrawn from the pool
    #[storage(read, write)]fn burn_liquidity(pool: ContractId, liquidity: u64, data: DataPackage, min_withdrawals: Vec<u64>) -> Vec<u64> {
        require(pool != BASE_ASSET_ID, InputErrors::NullPool);
        require(liquidity > 0, InputErrors::NullLiquidity);

        let balance_pre_transfer: u64 = balance_of(pool, pool);
        transfer(liquidity, pool, Identity::ContractId(pool));
        require(balance_of(pool, pool) - liquidity == balance_pre_transfer, TransferError::CannotTransferToPool);

        let mut path_index: u64         = 0;
        let pool_contract               = abi(Pool, pool.into());
        let withdrawn_amounts: Vec<u64> = pool_contract.burn(data);

        require(withdrawn_amounts.len() == min_withdrawals.len(), OutputErrors::IncorrectWithdrawnLen);

        while (path_index < min_withdrawals.len()) {
            require(min_withdrawals.get(path_index).unwrap() <= withdrawn_amounts.get(path_index).unwrap(), OutputErrors::TooLittleReceived);
            path_index += 1;
        }

        withdrawn_amounts
    }

    /// Burn LP tokens and get back liquidity in a single token (by swapping to that token in the background)
    ///
    /// # Arguments
    ///
    /// * `pool` The pool to withdraw from
    /// * `liquidity` The amount of LP tokens to burn
    /// * `data` The data used to withdraw from the pool
    /// * `min_withdrawal` The minimum amount of tokens to get back
    ///
    /// # Reverts
    ///
    /// * When `liquidity` is null
    /// * When LP tokens cannot be transferred to the pool
    /// * When the withdrawn amount is smaller than `min_withdrawal`
    #[storage(read, write)]fn burn_liquidity_single(pool: ContractId, liquidity: u64, data: DataPackage, min_withdrawal: u64) -> u64 {
        require(pool != BASE_ASSET_ID, InputErrors::NullPool);
        require(liquidity > 0, InputErrors::NullLiquidity);

        let balance_pre_transfer: u64 = balance_of(pool, pool);
        transfer(liquidity, pool, Identity::ContractId(pool));
        require(balance_of(pool, pool) - liquidity == balance_pre_transfer, TransferError::CannotTransferToPool);

        let pool_contract         = abi(Pool, pool.into());
        let withdrawn_amount: u64 = pool_contract.burn_single(data);

        require(min_withdrawal <= withdrawn_amount, OutputErrors::TooLittleReceived);

        withdrawn_amount
    }

    /// Recover tokens sent by mistake to this contract
    ///
    /// # Arguments
    ///
    /// * `token` The token to recover
    /// * `amount` The amount of tokens to recover
    /// * `recipient` The token recipient
    fn sweep(token: ContractId, amount: u64, recipient: Identity) -> bool {
        transfer(amount, token, recipient);
        true
    }
}
