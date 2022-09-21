library events;

use std::{contract_id::ContractId};

/// Emitted when the contract is initialized
pub struct Initialize {
    factory_registry: ContractId
}
