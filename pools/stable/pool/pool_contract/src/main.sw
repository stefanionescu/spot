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

use constant_sum_pool_abi::errors::*;
use constant_sum_pool_abi::events::*;
use constant_sum_pool_abi::constants::*;
use constant_sum_pool_abi::data_structures::*;
use constant_sum_pool_abi::{ConstantSumPool};

use abi_core::token::{Token};
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
    // Current amplification parameter
    A: u64 = 1,
    // Initial value for A when ramping up/down started
    initial_A: u64 = 0,
    // End value for A when ramping up/down finishes
    future_A: u64 = 0,
    // Timestamp when ramping up/down started
    initial_A_timestamp: u64 = 0,
    // Timestamp when ramping up/down finalizes
    future_A_timestamp: u64 = 0,
    // Multiplier for token0's decimal precision in order to reach `POOL_PRECISION_DECIMALS`
    token0_precision_multiplier: u64 = 1,
    // Multiplier for token1's decimal precision in order to reach `POOL_PRECISION_DECIMALS`
    token1_precision_multiplier: u64 = 1,
    // Last recorded reserve for `token0`
    reserve0: U128 = ~U128::new(),
    // Last recorded reserve for `token1`
    reserve1: U128 = ~U128::new(),
    // Latest value for d
    d_last: U128 = ~U128::new(),
    // The constant sum factory ID
    factory: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000)
}

/////////////////
// Access Control
/////////////////
/// Checks that the method caller is the factory contract
///
/// # Reverts
///
/// * When the method caller is not the factory contract
#[storage(read)]fn only_factory() {
    let caller: Result<Identity, AuthError> = msg_sender();
    require(caller.unwrap() == Identity::ContractId(storage.factory), AccessControlError::CallerNotFactory);
}

/////////////////
// Internal Logic
/////////////////
/// Return `true` if the difference between `a` and `b` is maximum one. Otherwise returns `false`
fn within1(a: U128, b: U128) -> bool {
    if (a > b) {
        a - b < ONE_U128 || a - b == ONE_U128
    } else {
        b - a < ONE_U128 || b - a == ONE_U128
    }
}

/// Update the value of `A` as it ramps up/down. Returns early if A is not currently being ramped
#[storage(read, write)]fn _update_a() {
    // TODO: fetch the real block timestamp
    let block_timestamp: u64 = 1;

    if (storage.initial_A != 0 && storage.future_A != 0) {
        if (block_timestamp < storage.future_A_timestamp) {
            if (storage.future_A > storage.initial_A) {
                storage.A = storage.initial_A +
                            (storage.future_A - storage.initial_A) *
                            (block_timestamp - storage.initial_A_timestamp) /
                            (storage.future_A_timestamp - storage.initial_A_timestamp);
            } else {
                storage.A = storage.initial_A -
                            (storage.initial_A - storage.future_A) *
                            (block_timestamp - storage.initial_A_timestamp) /
                            (storage.future_A_timestamp - storage.initial_A_timestamp);
            }
        } else {
            storage.A                   = storage.future_A;
            storage.initial_A           = 0;
            storage.future_A            = 0;
            storage.future_A_timestamp  = 0;
        }
    }
}

/// Return the latest value for `A` without updating storage
#[storage(read)]fn _get_a() -> u64 {
    // TODO: fetch the real block timestamp
    let block_timestamp: u64 = 1;

    if (storage.initial_A != 0 && storage.future_A != 0) {
        if (block_timestamp < storage.future_A_timestamp) {
            if (storage.future_A > storage.initial_A) {
                storage.initial_A +
                  (storage.future_A - storage.initial_A) *
                  (block_timestamp - storage.initial_A_timestamp) /
                  (storage.future_A_timestamp - storage.initial_A_timestamp)
            } else {
                storage.initial_A -
                  (storage.initial_A - storage.future_A) *
                  (block_timestamp - storage.initial_A_timestamp) /
                  (storage.future_A_timestamp - storage.initial_A_timestamp)
            }
        } else {
            storage.future_A
        }
    } else {
        storage.A
    }
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

/// Return the stableswap invariant based on a set of reserves and on the latest amplification
///
/// # Arguments
///
/// * `_A` The amplification parameter to use in calculations
/// * `reserve0` The pool's `token0` reserve
/// * `reserve1` The pool's `token1` reserve
///
/// # Reverts
///
/// * When the amplification is null or above `MAX_A`
#[storage(read)]fn compute_liquidity(_A: u64, reserve0: U128, reserve1: U128) -> U128 {
    require(_A > 0 && _A <= MAX_A, ParamError::InvalidAmplification);

    let adjusted_reserve0: U128 = reserve0 * ~U128::from(0, storage.token0_precision_multiplier);
    let adjusted_reserve1: U128 = reserve1 * ~U128::from(0, storage.token1_precision_multiplier);

    let mut D: U128       = adjusted_reserve0 + adjusted_reserve1;
    let mut prev_D: U128  = ~U128::new();
    let mut dP: U128      = ~U128::new();
    let mut i: u64        = 0;

    while (i < MAX_LOOP_LIMIT) {
        dP     = (((D * D) / adjusted_reserve0) * D) / adjusted_reserve1 / FOUR_U128;
        prev_D = D;
        D      = (((~U128::from(0, _A * COINS) * (adjusted_reserve0 + adjusted_reserve1)) / ~U128::from(0, A_PRECISION) + TWO_U128 * dP) * D) /
                 (~U128::from(0, _A * COINS / A_PRECISION - 1) * D + THREE_U128 * dP);

        if (within1(D, prev_D)) {
            break;
        }

        i += 1;
    }

    D
}

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
        let fee_split: Fees = get_pool_fees();

        if (amount1_optimal.as_u64().unwrap() <= amount1.as_u64().unwrap()) {
            fees.push(~U128::new());
            fees.push((~U128::from(0, fee_split.swap_fee) * (amount1 - amount1_optimal)) / ~U128::from(0, (2 * MAX_FEE)));
        } else {
            let amount0_optimal: U128 = (amount1 * reserve0) / reserve1;
            fees.push((~U128::from(0, fee_split.swap_fee) * (amount0 - amount0_optimal)) / ~U128::from(0, (2 * MAX_FEE)));
        }

        fees
    }

    fees
}

/// Distribute the protocol's fee portion (in the form of LP tokens) and return the new total supply of LP tokens and a recomputed `k` value
///
/// # Arguments
///
/// * `reserve0` The latest recorded reserve for `token0`
/// * `reserve1` The latest recorded reserve for `token1`
#[storage(read, write)]fn distribute_protocol_fee(reserve0: u64, reserve1: u64) -> LPUpdate {
    let mut update: LPUpdate  = LPUpdate {
        total_supply: storage.total_supply,
        d: 0
    };

    let mut _d_last: U128 = storage.d_last;

    if (_d_last != ZERO_U128) {
        _update_a();
        update.d = compute_liquidity(storage.A, ~U128::from(0, reserve0), ~U128::from(0, reserve1)).as_u64().unwrap();

        if (~U128::from(0, update.d) > _d_last) {
            let fee_split: Fees   = get_pool_fees();
            let numerator: U128   = ~U128::from(0, update.total_supply) * (~U128::from(0, update.d) - _d_last) * ~U128::from(0, fee_split.protocol_fee);
            let denominator: U128 = ~U128::from(0, (MAX_FEE - fee_split.protocol_fee)) * ~U128::from(0, update.d) + ~U128::from(0, fee_split.protocol_fee) * _d_last;
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

/// Update the token reserves
#[storage(read, write)]fn update_reserves() {
    let balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
    let balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

    require(
        (balance0 < ~U128::max() || balance0 == ~U128::max()) &&
        (balance1 < ~U128::max() || balance1 == ~U128::max()),
        ContractFlowError::BalanceOverflow
    );

    storage.reserve0   = balance0;
    storage.reserve1   = balance1;

    log(Sync {
        reserve0: balance0.as_u64().unwrap(),
        reserve1: balance1.as_u64().unwrap()
    });
}

/// Calculate new token balances given indexes for the FROM and TO tokens
///
/// # Arguments
///
/// * `_A` The amplification to use when calculating `y`
/// * `x` The new total amount of FROM tokens
/// * `D` The amount of TO tokens that should remain in the pool
#[storage(read)]fn _get_y(_A: u64, x: U128, D: U128) -> U128 {
    let mut c: U128  = D * D / (x * ~U128::from(0, 2));
    c                = c * D / ((~U128::from(0, storage.A * COINS) * ~U128::from(0, 2)) / ~U128::from(0, A_PRECISION));

    let b: U128          = x + (D * ~U128::from(0, A_PRECISION) / ~U128::from(0, storage.A * COINS));
    let mut y_prev: U128 = ~U128::new();
    let mut y: U128      = D;
    let mut i: u64       = 0;

    while (i < MAX_LOOP_LIMIT) {
        y_prev = y;
        y      = (y * y + c) / (y * ~U128::from(0, 2) + b - D);

        if (within1(y, y_prev)) {
            break;
        }

        i     += 1;
    }

    y
}

/// Return the amount of tokens that someone would get by swapping `amount_in` tokens
///
/// # Arguments
///
/// * `amount_in` The amount of tokens to swap
/// * `reserve0` The reserve for `token0`
/// * `reserve1` The reserve for `token1`
/// * `token0_in` Whether `token0` is swapped or not
#[storage(read)]fn _get_amount_out(amount_in: U128, reserve0: U128, reserve1: U128, token0_in: bool) -> U128 {
    let adjusted_reserve0: U128   = reserve0 * ~U128::from(0, storage.token0_precision_multiplier);
    let adjusted_reserve1: U128   = reserve1 * ~U128::from(0, storage.token1_precision_multiplier);

    let fee_split: Fees           = get_pool_fees();
    let fee_deducted_amount: U128 = amount_in - (amount_in * ~U128::from(0, fee_split.swap_fee)) / ~U128::from(0, MAX_FEE);

    let _A: u64                       = _get_a();

    let d: U128                       = compute_liquidity(_A, reserve0, reserve1);
    let mut dy: U128                  = ~U128::new();

    let mut x_adjusted_reserve: U128  = adjusted_reserve0;
    let mut x_token_precision: U128   = ~U128::from(0, storage.token0_precision_multiplier);

    let mut y_adjusted_reserve: U128  = adjusted_reserve1;
    let mut y_token_precision: U128   = ~U128::from(0, storage.token1_precision_multiplier);

    if (!token0_in) {
        x_adjusted_reserve = adjusted_reserve1;
        x_token_precision  = ~U128::from(0, storage.token1_precision_multiplier);

        y_adjusted_reserve = adjusted_reserve0;
        y_token_precision  = ~U128::from(0, storage.token0_precision_multiplier);
    }

    let mut x: U128 = x_adjusted_reserve + (fee_deducted_amount * x_token_precision);
    let y: U128     = _get_y(_A, x, d);
    dy              = (y_adjusted_reserve - y - ~U128::from(0, 1)) / y_token_precision;

    dy
}

//////////////////////
// Core Implementation
//////////////////////
impl ConstantSumPool for Contract {
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
    /// * `_A` The initial amplification parameter for this pool
    ///
    /// # Reverts
    ///
    /// * When the contract is already initialized
    /// * When the factory ID is null
    /// * When the two tokens are identical
    /// * When either of the tokens has more than `POOL_PRECISION_DECIMALS` decimals
    /// * When `_A` is null or above `MAX_A`
    #[storage(read, write)]fn constructor(factory: ContractId, token0: ContractId, token1: ContractId, _A: u64) {
        require(!storage.is_initialized, ContractFlowError::AlreadyInitialized);
        require(factory != BASE_ASSET_ID, ParamError::InvalidFactory);
        require(token0 != token1, ParamError::InvalidTokenPair);
        require(_A > 0 && _A <= MAX_A, ParamError::InvalidAmplification);

        let token0_contract      = abi(Token, token0.into());
        let token1_contract      = abi(Token, token1.into());

        // TODO: get real block timestamp
        let block_timestamp: u64 = 1;

        storage.is_initialized              = true;
        storage.token0                      = token0;
        storage.token1                      = token1;
        storage.factory                     = factory;
        storage.A                           = _A;
        storage.initial_A_timestamp         = block_timestamp;
        storage.token0_precision_multiplier = 10.pow(POOL_PRECISION_DECIMALS - token0_contract.decimals());
        storage.token1_precision_multiplier = 10.pow(POOL_PRECISION_DECIMALS - token1_contract.decimals());

        log(Initialize {
            name: LP_TOKEN_NAME,
            symbol: LP_TOKEN_SYMBOL,
            decimals: LP_TOKEN_DECIMALS,
            token0: token0,
            token1: token1,
            factory: factory,
            A: _A
        });
    }

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

        _update_a();

        let mut liquidity: u64 = 0;
        let balance0: u64      = balance_of(storage.token0, contract_id());
        let balance1: u64      = balance_of(storage.token1, contract_id());

        let mut reserve0: U128 = storage.reserve0;
        let mut reserve1: U128 = storage.reserve1;

        let new_liquidity: u64 = compute_liquidity(storage.A, ~U128::from(0, balance0), ~U128::from(0, balance1)).as_u64().unwrap();

        let amount0: U128      = ~U128::from(0, balance0) - reserve0;
        let amount1: U128      = ~U128::from(0, balance1) - reserve1;

        let fees: Vec<U128>    = get_non_optimal_mint_fee(amount0, amount1, reserve0, reserve1);
        reserve0              += fees.get(0).unwrap();
        reserve1              += fees.get(1).unwrap();

        let mint_update: LPUpdate = distribute_protocol_fee(reserve0.as_u64().unwrap(), reserve1.as_u64().unwrap());

        if (mint_update.total_supply == 0) {
            require(amount0.as_u64().unwrap() != 0 || amount1.as_u64().unwrap() != 0, LPError::InvalidAmounts);
            liquidity = new_liquidity - MINIMUM_LIQUIDITY;
            mint_to_contract(MINIMUM_LIQUIDITY, BASE_ASSET_ID);
        } else {
            liquidity = (new_liquidity - mint_update.d) * storage.total_supply / mint_update.d;
        }

        require(liquidity > 0, LPError::InsufficientLiquidityMinted);
        mint_to(liquidity, data.identities.get(0).unwrap());
        update_reserves();

        storage.d_last = ~U128::from(0, mint_update.d);

        log(Mint {
            sender: msg_sender().unwrap(),
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
        let mut balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
        let mut balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

        let burn_update: LPUpdate = distribute_protocol_fee(balance0.as_u64().unwrap(), balance1.as_u64().unwrap());

        let amount0: U128 = (~U128::from(0, liquidity) * balance0) / ~U128::from(0, burn_update.total_supply);
        let amount1: U128 = (~U128::from(0, liquidity) * balance1) / ~U128::from(0, burn_update.total_supply);

        burn(liquidity);

        transfer(amount0.as_u64().unwrap(), storage.token0, data.identities.get(0).unwrap());
        transfer(amount1.as_u64().unwrap(), storage.token1, data.identities.get(0).unwrap());

        update_reserves();

        let caller: Identity  = msg_sender().unwrap();
        let cast_amount0: u64 = amount0.as_u64().unwrap();
        let cast_amount1: u64 = amount1.as_u64().unwrap();

        log(Burn {
            sender: msg_sender().unwrap(),
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

        _update_a();

        let liquidity: u64     = balance_of(contract_id(), contract_id());
        let mut balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
        let mut balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

        let burn_update: LPUpdate = distribute_protocol_fee(balance0.as_u64().unwrap(), balance1.as_u64().unwrap());

        let mut amount0: U128  = (~U128::from(0, liquidity) * balance0) / ~U128::from(0, burn_update.total_supply);
        let mut amount1: U128  = (~U128::from(0, liquidity) * balance1) / ~U128::from(0, burn_update.total_supply);

        burn(liquidity);

        storage.d_last         = compute_liquidity(storage.A, balance0 - amount0, balance1 - amount1);

        // Swap one token for the other
        let mut amount_out: u64 = 0;
        {
            if (data.contract_ids.get(0).unwrap() == storage.token1) {
                // Swap `token0` to `token1`
                amount1   += _get_amount_out(amount0, balance0 - amount0, balance1 - amount1, true);
                transfer(amount1.as_u64().unwrap(), storage.token1, data.identities.get(0).unwrap());
                amount_out = amount1.as_u64().unwrap();
                amount0    = ~U128::new();
            } else {
                // Swap `token1` to `token0`
                require(data.contract_ids.get(0).unwrap() == storage.token0, LPError::InvalidOutputToken);
                amount0   += _get_amount_out(amount1, balance1 - amount1, balance0 - amount0, false);
                transfer(amount0.as_u64().unwrap(), storage.token0, data.identities.get(0).unwrap());
                amount_out = amount0.as_u64().unwrap();
                amount1    = ~U128::new();
            }
        }

        update_reserves();

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

        _update_a();

        if (data.contract_ids.get(0).unwrap() == storage.token0) {
            token_out  = storage.token1;
            amount_in  = balance0 - reserve0;
            amount_out = _get_amount_out(amount_in, reserve0, reserve1, true);
        } else {
            require(data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidInputToken);
            token_out  = storage.token0;
            amount_in  = balance1 - reserve1;
            amount_out = _get_amount_out(amount_in, reserve1, reserve0, false);
        }

        require(amount_out > ~U128::new(), SwapError::NullAmountOut);

        transfer(amount_out.as_u64().unwrap(), token_out, data.identities.get(0).unwrap());
        update_reserves();

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
        let mut token0_in: bool               = true;

        if (data.contract_ids.get(0).unwrap() == storage.token1) {
            starting_reserve  = storage.reserve1;
            end_reserve       = storage.reserve0;
            starting_balance  = 1;
            transferred_token = storage.token0;
            paired_token      = storage.token1;
            token0_in         = false;
        }

        _update_a();
        amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), starting_reserve, end_reserve, false);

        {
            transfer(amount_out.as_u64().unwrap(), transferred_token, data.identities.get(0).unwrap());

            let callee = abi(Callee, caller);
            callee.swap_callback(context);

            let balance0: U128 = ~U128::from(0, balance_of(storage.token0, contract_id()));
            let balance1: U128 = ~U128::from(0, balance_of(storage.token1, contract_id()));

            let mut target_balance: U128 = balance0;
            if (starting_balance == 1) { target_balance = balance1; }

            require((target_balance - starting_reserve).as_u64().unwrap() >= data.amounts.get(0).unwrap().as_u64().unwrap(), SwapError::InsufficientAmountIn);

            update_reserves();

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

    /// Start ramping A up or down
    ///
    /// # Arguments
    ///
    /// * `next_A` The future value for `A`
    /// * `ramp_end_time` The timestamp when ramping up/down ends and `storage.A` is equal to `next_A`
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the factory contract
    /// * When not enough time has elapsed since the last ramp
    /// * When `ramp_end_time` is not far enough in the future
    /// * When the ramp change is too large
    /// * When `next_A` is null or above `MAX_A`
    #[storage(read, write)]fn start_ramp_a(next_A: u64, ramp_end_time: u64) -> bool {
        only_factory();

        // TODO: fetch real block timestamp
        let block_timestamp: u64 = 1;

        require(next_A > 0 && next_A <= MAX_A, ParamError::InvalidAmplification);
        require(storage.initial_A_timestamp + MIN_A_CHANGE_DURATION <= block_timestamp, ParamError::InsufficientTimeSinceLastRamp);
        require(ramp_end_time >= block_timestamp + MIN_A_CHANGE_DURATION, ParamError::InsufficientRampTime);

        if (next_A < storage.A) {
            require(next_A * MAX_A_CHANGE >= storage.A, ParamError::InvalidAChange);
        } else {
            require(next_A <= storage.A * MAX_A_CHANGE, ParamError::InvalidAChange);
        }

        storage.initial_A           = storage.A;
        storage.future_A            = next_A;
        storage.initial_A_timestamp = block_timestamp;
        storage.future_A_timestamp  = ramp_end_time;

        log(RampA {
            initial_A: storage.initial_A,
            future_A: storage.future_A,
            initial_A_timestamp: storage.initial_A_timestamp,
            future_A_timestamp: storage.future_A_timestamp
        });

        true
    }

    /// Stop ramping A up or down
    ///
    /// # Reverts
    ///
    /// * When the method caller is not the factory contract
    #[storage(read, write)]fn stop_ramp_a() -> bool {
        only_factory();
        _update_a();

        // TODO: fetch the real block timestamp
        let block_timestamp: u64 = 1;

        // Avoids updating storage a second time for no reason (because in case ramping already finished, `initial_A`, `future_A` and `future_A_timestamp` are already zero)
        if (block_timestamp < storage.future_A_timestamp) {
            storage.initial_A          = 0;
            storage.future_A           = 0;
            storage.future_A_timestamp = 0;
        }

        log(StopRampA {
            current_A: storage.A,
            current_timestamp: block_timestamp
        });

        true
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
    /// * `token_in` The token to swap
    /// * `amount_in` The amount of tokens to swap
    #[storage(read)]fn get_amount_out(data: DataPackage) -> u64 {
        require(data.identities.len() == 0 && data.contract_ids.len() == 1 && data.amounts.len() == 1 && data.flags.len() == 0, SwapError::InvalidDataPackage);

        let reserve0: U128 = storage.reserve0;
        let reserve1: U128 = storage.reserve1;

        let mut final_amount_out: U128 = ~U128::new();

        if (data.contract_ids.get(0).unwrap() == storage.token0) {
          final_amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve0, reserve1, true);
        } else {
          require(data.contract_ids.get(0).unwrap() == storage.token1, SwapError::InvalidInputToken);
          final_amount_out = _get_amount_out(~U128::from(0, data.amounts.get(0).unwrap().as_u64().unwrap()), reserve1, reserve0, false);
        }

        final_amount_out.as_u64().unwrap()
    }

    /// Return the amount of in tokens that someone would need to swap to get a specific amount of `out` tokens
    ///
    /// # Arguments
    ///
    /// * `data` The token and amount to receive
    #[storage(read)]fn get_amount_in(data: DataPackage) -> u64 {
        0
    }

    /// Return the pool's virtual price
    #[storage(read)]fn get_virtual_price() -> U128 {
        let reserve0: U128 = storage.reserve0;
        let reserve1: U128 = storage.reserve1;

        (compute_liquidity(_get_a(), reserve0, reserve1) * ~U128::from(0, 10.pow(LP_TOKEN_DECIMALS))) / ~U128::from(0, storage.total_supply)
    }

    /// Return the amounts of token0 and token1 held by the pool and the last timestamp when they were updated
    #[storage(read)]fn get_reserves() -> PoolReserves {
        let reserve0: U128            = storage.reserve0;
        let reserve1: U128            = storage.reserve1;

        let reserves: PoolReserves = PoolReserves {
            reserve0: reserve0,
            reserve1: reserve1,
            d_last: storage.d_last
        };

        reserves
    }

    /// Return the latest amplification parameter
    #[storage(read)]fn get_a() -> u64 {
        let _A: u64 = _get_a();
        _A
    }
}
