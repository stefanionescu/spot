library events;

use std::{contract_id::ContractId, identity::Identity};

/// Emitted when the contract is initialized
pub struct Initialize {
    owner: Identity,
    factory_registry: ContractId,
    swap_fee: u16,
    protocol_fee: u16,
    protocol_fee_receiver: ContractId
}

/// Emitted when the current contract owner proposes a new owner
pub struct ProposeOwner {
    proposed_owner: Identity
}

/// Emitted when the proposed contract owner claims contract ownership
pub struct ClaimOwnership {
    owner: Identity
}

/// Emitted when the current contract owner revokes contract ownership
pub struct RevokeOwnership {
    owner: Identity
}

/// Emitted when a new factory registry is set
pub struct SetFactoryRegistry {
    factory_registry: ContractId
}

/// Emitted when the swap fee for a specific factory is changed
pub struct SetSwapFee {
    swap_fee: u16
}

/// Emitted when the protocol fee for a specific factory is changed
pub struct SetProtocolFee {
    protocol_fee: u16
}

/// Emitted when the protocol fee receiver for a specific factory is changed
pub struct SetProtocolFeeReceiver {
    protocol_fee_receiver: ContractId
}

/// Emitted when a new pool is added
pub struct AddPool {
    tokenA: ContractId,
    tokenB: ContractId,
    pool: ContractId
}
