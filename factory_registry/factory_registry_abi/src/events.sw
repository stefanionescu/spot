library events;

use abi_utils::data_structures::DataPackage;
use std::{contract_id::ContractId, identity::Identity, option::Option};

/// Emitted when the contract is initialized
pub struct Initialize {
    owner: Identity
}

/// Emitted when the current contract owner proposes a new owner
pub struct ProposeOwner {
    proposed_owner: Identity
}

/// Emitted when the proposed contract owner claims contract ownership
pub struct ClaimOwnership {
    owner: Identity
}

/// Emitted when a factory is whitelisted
pub struct AddToWhitelist {
    factory: b256
}

/// Emitted when a factory is removed from the whitelist
pub struct RemoveFromWhitelist {
    factory: b256
}

/// Emitted when the protocol fee for a specific factory is changed
pub struct SetProtocolFee {
    factory: b256,
    fee: u16
}

/// Emitted when the protocol fee receiver for a specific factory is changed
pub struct SetProtocolFeeReceiver {
    factory: b256,
    fee_receiver: Identity
}
