library events;

use std::{vec::Vec, contract_id::ContractId, identity::Identity};

/// Emitted when the contract is initialized
pub struct Initialize {
    owner: Identity,
    router: ContractId,
    factory_registry: ContractId,
    fee_receiver: ContractId,
    end_token: ContractId,
    batch_limit: u8
}

/// Emitted when the current contract owner proposes a new owner
pub struct ProposeOwner {
    proposed_owner: Identity
}

/// Emitted when the proposed contract owner claims contract ownership
pub struct ClaimOwnership {
    owner: Identity
}

/// Emitted when changing the router contract ID
pub struct SetRouter {
    router: ContractId
}

/// Emitted when changing the router contract ID
pub struct SetFeeReceiver {
    fee_receiver: ContractId
}

/// Emitted when LP tokens are burned in exchange for underlying reserves
pub struct RedeemFees {
    lp_tokens: Vec<ContractId>
}

/// Emitted when swapping fee tokens to the target token
pub struct SwapFees {
    tokens: Vec<ContractId>,
    in_amounts: Vec<u64>,
    out_amounts: Vec<u64>
}

/// Emitted when setting a new bridge for a fee token
pub struct SetBridge {
    bridge_position: u8,
    fee_token: ContractId,
    bridge_token: ContractId,
    bridge_pool: ContractId,
    factory: ContractId,
    token_in: ContractId
}

/// Emitted when a bridge is removed
pub struct RemoveBridge {
    fee_token: ContractId,
    bridge_position: u8
}
