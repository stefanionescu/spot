library events;

use std::{identity::Identity, contract_id::ContractId};

pub struct Swap {
    recipient: Identity,
    token_in: ContractId,
    token_out: ContractId,
    amount_in: u64,
    amount_out: u64
}
