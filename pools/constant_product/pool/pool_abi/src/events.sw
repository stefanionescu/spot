library events;

use std::{contract_id::ContractId, identity::Identity};

/// Emitted when the pool is initialized
pub struct Initialize {
    name: str[13],
    symbol: str[7],
    decimals: u8,
    token0: ContractId,
    token1: ContractId,
    factory: ContractId
}

/// Emitted when the contract mints LP tokens
pub struct Mint {
    sender: Identity,
    recipient: Identity,
    amount0: u64,
    amount1: u64
}

/// Emitted when the contract burns LP tokens
pub struct Burn {
    sender: Identity,
    recipient: Identity,
    amount0: u64,
    amount1: u64
}

/// Emitted when the pool is synced
pub struct Sync {
    reserve0: u64,
    reserve1: u64
}

/// Emitted when a swap occurs
pub struct Swap {
    recipient: Identity,
    token_in: ContractId,
    token_out: ContractId,
    amount_in: u64,
    amount_out: u64
}

/// Emitted when the protocol receives its share of the swap fees
pub struct DistributeProtocolFee {
    recipient: ContractId,
    liquidity: u64
}
