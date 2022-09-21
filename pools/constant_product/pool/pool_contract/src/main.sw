contract;

//////////
// Imports
//////////
use std::{
    address::*,
    storage::*,
    token::*,
    result::*,
    math::*,
    reentrancy::*,
    chain::auth::*,
    context::{*, call_frames::*},
    logging::log,
    vec::Vec,
    u128::U128,
    identity::Identity,
    contract_id::ContractId,
    revert::{require, revert},
    constants::{ZERO_B256, BASE_ASSET_ID}
};

use constant_product_pool_abi::errors::*;
use constant_product_pool_abi::events::*;
use constant_product_pool_abi::constants::*;
use constant_product_pool_abi::data_structures::*;
use constant_product_pool_abi::{ConstantProductPool};

use abi_core::callee::{Callee};
use abi_core::pool_factory::{PoolFactory};
use abi_utils::data_structures::{DataPackage};

///////////
/// Storage
///////////
storage {
    // Whether the contract has already been initialized
    is_initialized: bool = false,
    // Token with ID 0 from the pool
    token0: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // Token with ID 1 from the pool
    token1: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    // Total supply of LP tokens
    total_supply: u64 = 0,
    // Accumulator for `token0` historical price
    price0_cumulative_last: U128 = ~U128::new(),
    // Accumulator for `token1` historical price
    price1_cumulative_last: U128 = ~U128::new(),
    // Last value for `k`
    k_last: u64 = 0,
    // Last recorded reserve for `token0`
    reserve0: U128 = ~U128::new(),
    // Last recorded reserve for `token1`
    reserve1: U128 = ~U128::new(),
    // Last block timestamp when reserves were updated
    block_timestamp_last: u64 = 0,
    // The constant product factory ID
    factory: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000)
}

///////////////////
// Internal Methods
///////////////////
/// Calculate and return the non optimal mint fee for providing liquidity
///
/// # Arguments
///
/// * `amount0` The amount of `token0` that was added in the pool
/// * `amount1` The amount of `token1` that was added in the pool
/// * `reserve0` The latest recorded reserve for `token0`
/// * `reserve1` The latest recorded reserve for `token1`
#[storage(read)]fn get_non_optimal_mint_fee(amount0: U128, amount1: U128, reserve0: U128, reserve1: U128) -> Vec<U128> {
    let mut fees: Vec<U128> = ~Vec::new();

    if (reserve0.as_u64().unwrap() == 0 || reserve1.as_u64().unwrap() == 0) {
        fees.push(~U128::new());
        fees.push(~U128::new());
        fees
    } else {
        let amount1_optimal: U128 = (amount0 * reserve1) / reserve0;
        let fee_split: Fees       = get_pool_fees();

        if (amount1_optimal.as_u64().unwrap() <= amount1.as_u64().unwrap()) {
            fees.push(~U128::new());
            fees.push((~U128::from(0, (fee_split.swap_fee)) * (amount1 - amount1_optimal)) / ~U128::from(0, (2 * MAX_FEE)));
        } else {
            let amount0_optimal: U128 = (amount1 * reserve0) / reserve1;
            fees.push((~U128::from(0, (fee_split.swap_fee)) * (amount0 - amount0_optimal)) / ~U128::from(0, (2 * MAX_FEE)));
        }

        fees
    }
}

/// Distribute the protocol's fee portion (in the form of LP tokens) and return the new total supply of LP tokens and a recomputed `k` value
///
/// # Arguments
///
/// * `reserve0` The latest recorded reserve for `token0`
/// * `reserve1` The latest recorded reserve for `token1`
#[storage(read, write)]fn distribute_protocol_fee(reserve0: u64, reserve1: u64) -> LPUpdate {
    let mut computed_k: U128  = ~U128::new();
    let mut update: LPUpdate  = LPUpdate {
        total_supply: storage.total_supply,
        k: 0
    };

    let root_reserves: u64 = (reserve0 * reserve1).sqrt();

    if (storage.k_last != 0) {
        computed_k = ~U128::from(0, root_reserves);
        update.k   = computed_k.as_u64().unwrap();

        if (computed_k > ~U128::from(0, storage.k_last)) {
            let fee_split: Fees   = get_pool_fees();
            let numerator: U128   = ~U128::from(0, storage.total_supply) * (computed_k - ~U128::from(0, storage.k_last)) * ~U128::from(0, fee_split.protocol_fee);
            let denominator: U128 = ~U128::from(0, fee_split.max_less_protocol_fee) * computed_k + ~U128::from(0, fee_split.protocol_fee) * ~U128::from(0, storage.k_last);
            let liquidity: U128   = numerator / denominator;

            if (liquidity != ZERO_U128) {
                let fee_recipient: ContractId = get_protocol_fee_receiver();
                update.total_supply           = update.total_supply + liquidity.as_u64().unwrap();
                mint_to_contract(liquidity.as_u64().unwrap(), fee_recipient);

                log(DistributeProtocolFee {
                    recipient: fee_recipient,
                    liquidity: liquidity.as_u64().unwrap()
                });
            }
        }
    }

    update
}

/// Update reserve and cumulative price data
///
/// # Arguments
///
/// * `balance0` The pool's balance of `token0`
/// * `balance1` The pool's balance of `token1`
/// * `reserve0` The latest recorded reserve for `token0`
/// * `reserve1` The latest recorded reserve for `token1`
#[storage(read, write)]fn update_reserves_and_cumulative_prices(balance0: u64, balance1: u64, reserve0: U128, reserve1: U128) {
    // TODO: fetch the block timestamp
    let block_timestamp: u64 = 1;

    if (block_timestamp != storage.block_timestamp_last && reserve0 != ZERO_U128 && reserve1 != ZERO_U128) {
        let elapsed_time: U128         = ~U128::from(0, (block_timestamp - storage.block_timestamp_last)) ;
        storage.price0_cumulative_last = storage.price0_cumulative_last + (reserve1 / reserve0 * elapsed_time);
        storage.price1_cumulative_last = storage.price1_cumulative_last + (reserve0 / reserve1 * elapsed_time);
    }

    storage.reserve0             = ~U128::from(0, balance0);
    storage.reserve1             = ~U128::from(0, balance1);
    storage.block_timestamp_last = block_timestamp;

    log(Sync {
        reserve0: balance0,
        reserve1: balance1
    });
}

/// Return the amount of tokens that need to be swapped in order to receive `amount_out` tokens
///
/// # Arguments
///
/// * `amount_out` The amount of tokens to receive
/// * `reserve_amount_in` The current reserve for the `amount_in` token
/// * `reserve_amount_out` The current reserve for the token to swap to
#[storage(read)]fn _get_amount_in(amount_out: U128, reserve_amount_in: U128, reserve_amount_out: U128) -> U128 {
    let fee_split: Fees = get_pool_fees();
    (reserve_amount_in * amount_out * ~U128::from(0, MAX_FEE)) / ((reserve_amount_out - amount_out) * ~U128::from(0, fee_split.max_less_swap_fee)) + ~U128::from(0, 1)
}

/// Return the amount of tokens received by swapping `amount_in` tokens
///
/// # Arguments
///
/// * `amount_in` The amount of tokens to swap
/// * `reserve_amount_in` The current reserve for the `amount_in` token
/// * `reserve_amount_out` The current reserve for the token to swap to
#[storage(read)]fn _get_amount_out(amount_in: U128, reserve_amount_in: U128, reserve_amount_out: U128) -> U128 {
    require(amount_in > ~U128::new(), SwapError::NullAmountIn);
    let fee_split: Fees          = get_pool_fees();
    let amount_in_with_fee: U128 = amount_in * ~U128::from(0, fee_split.max_less_swap_fee);

    (amount_in_with_fee * reserve_amount_out) / (reserve_amount_in * ~U128::from(0, MAX_FEE) + amount_in_with_fee)
}

/// Return the swap, protocol and `MAX - swap` fees
#[storage(read)]fn get_pool_fees() -> Fees {
    let factory_id: b256  = storage.factory.into();
    let factory_contract  = abi(PoolFactory, factory_id);
    let swap_fee: u16     = factory_contract.get_swap_fee();
    let protocol_fee: u16 = factory_contract.get_protocol_fee();

    let fees: Fees = Fees {
        swap_fee: swap_fee,
        protocol_fee: protocol_fee,
        max_less_swap_fee: MAX_FEE - swap_fee,
        max_less_protocol_fee: MAX_FEE - protocol_fee
    };

    fees
}

/// Return the protocol fee receiver set for this pool type in the factory
#[storage(read)]fn get_protocol_fee_receiver() -> ContractId {
    let factory_id: b256                  = storage.factory.into();
    let factory_contract                  = abi(PoolFactory, factory_id);
    let protocol_fee_receiver: ContractId = factory_contract.get_protocol_fee_receiver();

    protocol_fee_receiver
}

//////////////////////
// Core Implementation
//////////////////////
impl ConstantProductPool for Contract {
    /////////////
    // Initialize
    /////////////
    /// Instantiate the contract
    ///
    /// # Arguments
    ///
    /// * `factory` The ID of the constant product pool factory
    /// * `token0` The token with ID 0 that's traded in the pool
    /// * `token1` The token with ID 1 that's traded in the pool
    ///
    /// # Reverts
    ///
    /// * When the contract is already initialized
    /// * When the factory ID is null
    /// * When the two tokens are identical
    #[storage(read, write)]fn constructor(factory: ContractId, token0: ContractId, token1: ContractId) {
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);
        require(factory != BASE_ASSET_ID, ParamError::InvalidFactory);
        require(token0 != token1, ParamError::InvalidTokenPair);

        storage.is_initialized = true;
        storage.token0         = token0;
        storage.token1         = token1;
        storage.factory        = factory;

        // TODO: set to real block timestamp
        storage.block_timestamp_last = 1;

        log(Initialize {
            name: LP_TOKEN_NAME,
            symbol: LP_TOKEN_SYMBOL,
            decimals: LP_TOKEN_DECIMALS,
            token0: token0,
            token1: token1,
            factory: factory
        });
    }

    ///////////////
    // Modify State
    ///////////////
    /// Mint LP tokens for a custom recipient
    ///
    /// # Arguments
    ///
    /// * `data` Data containing the recipient of the minted LP tokens
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (has more than one Identity)
    /// * When both token amounts that were LPed are zero
    /// * When no LP token could be minted (because of tiny LPed amounts)
    /// * When reentrancy is detected
    #[storage(read, write)]fn mint(data: DataPackage) -> u64 {
        reentrancy_guard();
        require(data.identities.len() == 1 && data.contract_ids.len() == 0 && data.amounts.len() == 0 && data.flags.len() == 0, LPError::InvalidDataPackage);

        let mut liquidity: u64 = 0;
        let balance0: u64      = balance_of(storage.token0, contract_id());
        let balance1: u64      = balance_of(storage.token1, contract_id());

        let balances_root: u64 = (balance0 * balance1).sqrt();
        let mut reserve0: U128 = storage.reserve0;
        let mut reserve1: U128 = storage.reserve1;
        let amount0: U128      = ~U128::from(0, balance0) - reserve0;
        let amount1: U128      = ~U128::from(0, balance1) - reserve1;

        let fees: Vec<U128>    = get_non_optimal_mint_fee(amount0, amount1, reserve0, reserve1);
        reserve0              += fees.get(0).unwrap();
        reserve1              += fees.get(1).unwrap();

        let fee_mint_update: LPUpdate = distribute_protocol_fee(reserve0.as_u64().unwrap(), reserve1.as_u64().unwrap());

        if (fee_mint_update.total_supply == 0) {
            require(amount0.as_u64().unwrap() != 0 || amount1.as_u64().unwrap() != 0, LPError::InvalidAmounts);
            liquidity = balances_root - MINIMUM_LIQUIDITY;
            mint_to_contract(MINIMUM_LIQUIDITY, BASE_ASSET_ID);
        } else {
            let k_increase: u64 = balances_root - fee_mint_update.k;
            liquidity           = (k_increase * fee_mint_update.total_supply) / fee_mint_update.k;
        }

        require(liquidity > 0, LPError::InsufficientLiquidityMinted);
        mint_to(liquidity, data.identities.get(0).unwrap());
        update_reserves_and_cumulative_prices(balance0, balance1, reserve0, reserve1);
        storage.k_last = balances_root;

        let caller: Identity = msg_sender().unwrap();

        log(Mint {
            sender: caller,
            recipient: data.identities.get(0).unwrap(),
            amount0: amount0.as_u64().unwrap(),
            amount1: amount1.as_u64().unwrap()
        });

        liquidity
    }

    /// Burn LP tokens and send the withdrawn liquidity to a custom recipient
    ///
    /// # Arguments
    ///
    /// * `recipient` Data containing the recipient of the withdrawn liquidity
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (has more than one Identity)
    /// * When reentrancy is detected
    #[storage(read, write)]fn burn(data: DataPackage) -> Vec<u64> {
        reentrancy_guard();
        require(data.identities.len() == 1 && data.contract_ids.len() == 0 && data.amounts.len() == 0 && data.flags.len() == 0, LPError::InvalidDataPackage);

        let liquidity: u64     = balance_of(contract_id(), contract_id());
        let reserve0: U128     = storage.reserve0;
        let reserve1: U128     = storage.reserve1;
        let mut balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
        let mut balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

        let burn_update: LPUpdate = distribute_protocol_fee(reserve0.as_u64().unwrap(), reserve1.as_u64().unwrap());

        let amount0: U128 = (~U128::from(0, liquidity) * balance0) / ~U128::from(0, burn_update.total_supply);
        let amount1: U128 = (~U128::from(0, liquidity) * balance1) / ~U128::from(0, burn_update.total_supply);

        burn(liquidity);

        transfer(amount0.as_u64().unwrap(), storage.token0, data.identities.get(0).unwrap());
        transfer(amount1.as_u64().unwrap(), storage.token1, data.identities.get(0).unwrap());

        balance0 -= amount0;
        balance1 -= amount1;

        update_reserves_and_cumulative_prices(balance0.as_u64().unwrap(), balance1.as_u64().unwrap(), reserve0, reserve1);
        storage.k_last = (balance0.as_u64().unwrap() * balance1.as_u64().unwrap()).sqrt();

        let caller: Identity  = msg_sender().unwrap();
        let cast_amount0: u64 = amount0.as_u64().unwrap();
        let cast_amount1: u64 = amount1.as_u64().unwrap();

        log(Burn {
            sender: caller,
            recipient: data.identities.get(0).unwrap(),
            amount0: cast_amount0,
            amount1: cast_amount1
        });

        let mut withdrawn_amounts: Vec<u64> = ~Vec::new();
        withdrawn_amounts.push(amount0.as_u64().unwrap());
        withdrawn_amounts.push(amount1.as_u64().unwrap());

        withdrawn_amounts
    }

    /// Burns LP tokens sent to this contract and swaps one of the output tokens for another; the recipient gets a single token out by burning LP tokens
    ///
    /// # Arguments
    ///
    /// * `data` Data that contains the token to give back to the `recipient` and the recipient for the withdrawn liquidity
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (has more than one Identity and/or ContractId)
    /// * When reentrancy is detected
    #[storage(read, write)]fn burn_single(data: DataPackage) -> u64 {
        reentrancy_guard();
        require(data.identities.len() == 1 && data.contract_ids.len() == 1 && data.amounts.len() == 0 && data.flags.len() == 0, LPError::InvalidDataPackage);

        let liquidity: u64        = balance_of(contract_id(), contract_id());
        let reserve0: U128        = storage.reserve0;
        let reserve1: U128        = storage.reserve1;
        let mut balance0: U128    = ~U128::from(0, balance_of(storage.token0, contract_id()));
        let mut balance1: U128    = ~U128::from(0, balance_of(storage.token1, contract_id()));

        let burn_update: LPUpdate = distribute_protocol_fee(reserve0.as_u64().unwrap(), reserve1.as_u64().unwrap());

        let mut amount0: U128 = (~U128::from(0, liquidity) * balance0) / ~U128::from(0, burn_update.total_supply);
        let mut amount1: U128 = (~U128::from(0, liquidity) * balance1) / ~U128::from(0, burn_update.total_supply);

        storage.k_last        = ((reserve0 - amount0).as_u64().unwrap() * (reserve1 - amount1).as_u64().unwrap()).sqrt();

        burn(liquidity);

        // Swap one token for the other
        let mut amount_out: u64 = 0;
        {
            if (data.contract_ids.get(0).unwrap() == storage.token1) {
                // Swap `token0` to `token1`
                amount1   += _get_amount_out(amount0, reserve0 - amount0, reserve1 - amount1);
                transfer(amount1.as_u64().unwrap(), storage.token1, data.identities.get(0).unwrap());
                amount_out = amount1.as_u64().unwrap();
                amount0    = ~U128::new();
            } else {
                // Swap `token1` to `token0`
                require(data.contract_ids.get(0).unwrap() == storage.token0, LPError::InvalidOutputToken);
                amount0   += _get_amount_out(amount1, reserve1 - amount1, reserve0 - amount0);
                transfer(amount0.as_u64().unwrap(), storage.token0, data.identities.get(0).unwrap());
                amount_out = amount0.as_u64().unwrap();
                amount1    = ~U128::new();
            }
        }

        update_reserves_and_cumulative_prices(balance_of(storage.token0, contract_id()), balance_of(storage.token1, contract_id()), reserve0, reserve1);

        log(Burn {
            sender: msg_sender().unwrap(),
            recipient: data.identities.get(0).unwrap(),
            amount0: amount0.as_u64().unwrap(),
            amount1: amount1.as_u64().unwrap()
        });

        amount_out
    }

    /// Swap one token for another
    ///
    /// # Arguments
    ///
    /// * `data` Data that contains the token to swap and the recipient that will receive the output tokens
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (has more than one Identity and/or ContractId)
    /// * When the pool is not initialized
    /// * When reentrancy is detected
    #[storage(read, write)]fn swap(data: DataPackage) -> u64 {
        let reserve0: U128 = storage.reserve0;
        let reserve1: U128 = storage.reserve1;
        require(reserve0.as_u64().unwrap() > 0, SwapError::PoolUninitialized);
        require(data.identities.len() == 1 && data.contract_ids.len() == 1 && data.amounts.len() == 0 && data.flags.len() == 0, SwapError::InvalidDataPackage);

        let swap_recipient: Identity = data.identities.get(0).unwrap();
        require(swap_recipient != Identity::Address(~Address::from(ZERO_B256)) && swap_recipient != Identity::ContractId(BASE_ASSET_ID), SwapError::NullSwapRecipient);

        reentrancy_guard();

        let mut balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
        let mut balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

        let mut amount_in: U128       = ~U128::new();
        let mut amount_out: U128      = ~U128::new();
        let mut token_out: ContractId = storage.token0;

        if (data.contract_ids.get(0).unwrap() == storage.token0) {
            token_out  = storage.token1;
            amount_in  = balance0 - reserve0;
            amount_out = _get_amount_out(amount_in, reserve0, reserve1);
            balance1  -= amount_out;
        } else {
            require(data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidInputToken);
            token_out  = storage.token0;
            amount_in  = balance1 - reserve1;
            amount_out = _get_amount_out(amount_in, reserve1, reserve0);
            balance0  -= amount_out;
        }

        require(amount_out > ~U128::new(), SwapError::NullAmountOut);

        transfer(amount_out.as_u64().unwrap(), token_out, data.identities.get(0).unwrap());
        update_reserves_and_cumulative_prices(balance0.as_u64().unwrap(), balance1.as_u64().unwrap(), reserve0, reserve1);

        let cast_amount_in: u64  = amount_in.as_u64().unwrap();
        let cast_amount_out: u64 = amount_out.as_u64().unwrap();

        log(Swap {
            recipient: data.identities.get(0).unwrap(),
            token_in: data.contract_ids.get(0).unwrap(),
            token_out: token_out,
            amount_in: cast_amount_in,
            amount_out: cast_amount_out
        });

        amount_out.as_u64().unwrap()
    }

    /// Swap one token for another, flashloan style
    ///
    /// # Arguments
    ///
    /// * `data` Data that contains the token to swap, the recipient that will receive the output tokens,
    ///              and the amount of `token_in` tokens to flashswap
    /// * `context` The callback handler for the flashswap
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (has more than one Identity, ContractId or u64)
    /// * When the method caller is not a contract
    /// * When reentrancy is detected
    #[storage(read, write)]fn flashswap(data: DataPackage, context: DataPackage) -> u64 {
        require(data.identities.len() == 1 && data.contract_ids.len() == 1 && data.amounts.len() == 1 && data.flags.len() == 0, SwapError::InvalidDataPackage);
        require(data.contract_ids.get(0).unwrap() == storage.token0 || data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidInputToken);
        let caller: b256 = match msg_sender().unwrap() {
            Identity::ContractId(id) => {
                id.into()
            },
            _ => {
                revert(0);
            }
        };

        require(
            context.identities.len() + context.contract_ids.len() + context.amounts.len() + context.flags.len() <= MAX_CALLBACK_PARAM_ARRAY_LENGTH * 4,
            SwapError::InvalidCallbackParams
        );

        require(storage.reserve0.as_u64().unwrap() > 0, SwapError::PoolUninitialized);
        reentrancy_guard();

        // Prepare local vars
        let mut amount_out: U128              = ~U128::new();
        let mut starting_reserve: U128        = storage.reserve0;
        let mut end_reserve: U128             = storage.reserve1;
        let mut starting_balance: u8          = 0;
        let mut transferred_token: ContractId = storage.token1;
        let mut paired_token: ContractId      = storage.token0;

        if (data.contract_ids.get(0).unwrap() == storage.token1) {
            starting_reserve  = storage.reserve1;
            end_reserve       = storage.reserve0;
            starting_balance  = 1;
            transferred_token = storage.token0;
            paired_token      = storage.token1;
        }

        amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), starting_reserve, end_reserve);
        {
            transfer(amount_out.as_u64().unwrap(), transferred_token, data.identities.get(0).unwrap());

            let callee = abi(Callee, caller);
            callee.swap_callback(context);

            let balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
            let balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

            let mut target_balance: U128 = balance0;
            if (starting_balance == 1) { target_balance = balance1; }

            require((target_balance - starting_reserve).as_u64().unwrap() >= data.amounts.get(0).unwrap().as_u64().unwrap(), SwapError::InsufficientAmountIn);
            update_reserves_and_cumulative_prices(balance0.as_u64().unwrap(), balance1.as_u64().unwrap(), storage.reserve0, storage.reserve1);

            log(Swap {
                recipient: data.identities.get(0).unwrap(),
                token_in: data.contract_ids.get(0).unwrap(),
                token_out: transferred_token,
                amount_in: data.amounts.get(0).unwrap().as_u64().unwrap(),
                amount_out: amount_out.as_u64().unwrap()
            });
        }

        amount_out.as_u64().unwrap()
    }

    //////////
    // Getters
    //////////
    /// Return an identifier for the pool type
    fn get_pool_id() -> u64 {
        POOL_ID
    }

    /// Return the LP token's name
    fn name() -> str[13] {
        LP_TOKEN_NAME
    }

    /// Return the LP token's symbol
    fn symbol() -> str[7] {
        LP_TOKEN_SYMBOL
    }

    /// Return the amount of decimals the pool's LP token has
    fn decimals() -> u8 {
        LP_TOKEN_DECIMALS
    }

    /// Return an array of tokens supported by the pool
    #[storage(read)]fn get_assets() -> Vec<ContractId> {
        let mut assets: Vec<ContractId> = ~Vec::new();

        assets.push(storage.token0);
        assets.push(storage.token1);

        assets
    }

    /// Return the factory contract ID
    #[storage(read)]fn get_factory() -> ContractId {
        storage.factory
    }

    /// Return the amount of out tokens that someone would get by swapping a specific amount of `in` tokens
    ///
    /// # Arguments
    ///
    /// * `data` The token and amount to swap
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (more than one ContractID or amount or any amount of Identities or flags)
    #[storage(read)]fn get_amount_out(data: DataPackage) -> u64 {
        require(data.identities.len() == 0 && data.contract_ids.len() == 1 && data.amounts.len() == 1 && data.flags.len() == 0, SwapError::InvalidDataPackage);

        let reserve0: U128 = storage.reserve0;
        let reserve1: U128 = storage.reserve1;

        let mut final_amount_out: U128 = ~U128::new();

        if (data.contract_ids.get(0).unwrap() == storage.token0) {
          final_amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve0, reserve1);
        } else {
          require(data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidInputToken);
          final_amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve1, reserve0);
        }

        final_amount_out.as_u64().unwrap()
    }

    /// Return the amount of in tokens that someone would need to swap to get a specific amount of `out` tokens
    ///
    /// # Arguments
    ///
    /// * `data` The token and amount to receive
    ///
    /// # Reverts
    ///
    /// * When the data package is invalid (more than one ContractID or amount or any amount of Identities or flags)
    #[storage(read)]fn get_amount_in(data: DataPackage) -> u64 {
        require(data.identities.len() == 0 && data.contract_ids.len() == 1 && data.amounts.len() == 1 && data.flags.len() == 0, SwapError::InvalidDataPackage);

        let reserve0: U128 = storage.reserve0;
        let reserve1: U128 = storage.reserve1;

        let mut final_amount_in: U128 = ~U128::new();

        if (data.contract_ids.get(0).unwrap() == storage.token0) {
          final_amount_in = _get_amount_in(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve0, reserve1);
        } else {
          require(data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidOutputToken);
          final_amount_in = _get_amount_in(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve1, reserve0);
        }

        final_amount_in.as_u64().unwrap()
    }

    /// Return the cumulative price for `token0`
    #[storage(read)]fn get_price_cumulative0() -> U128 {
        storage.price0_cumulative_last
    }

    /// Return the cumulative price for `token1`
    #[storage(read)]fn get_price_cumulative1() -> U128 {
        storage.price1_cumulative_last
    }

    /// Return the last recorded value for `k`
    #[storage(read)]fn get_k_last() -> u64 {
        storage.k_last
    }

    /// Return the amounts of token0 and token1 held by the pool and the last timestamp when they were updated
    #[storage(read)]fn get_reserves() -> PoolReserves {
        let reserve0: U128            = storage.reserve0;
        let reserve1: U128            = storage.reserve1;
        let block_timestamp_last: u64 = storage.block_timestamp_last;

        let reserves: PoolReserves = PoolReserves {
            reserve0,
            reserve1,
            block_timestamp_last
        };

        reserves
    }
}
