library callee;

use abi_utils::data_structures::{DataPackage};
use std::{identity::Identity, contract_id::ContractId, vec::Vec};

abi Callee {
    //////////
    // Actions
    //////////
    /// Callback for a swap
    #[storage(read, write)]fn swap_callback(data: DataPackage);
    /// Callback for minting LP tokens
    #[storage(read, write)]fn mint_callback(data: DataPackage);
}
