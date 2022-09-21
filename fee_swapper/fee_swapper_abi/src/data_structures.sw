library data_structures;

use std::{contract_id::ContractId};

pub struct Bridge {
    factory: ContractId,
    pool: ContractId,
    token_in: ContractId
}
