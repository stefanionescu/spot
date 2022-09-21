library errors;

/// Contract flow errors
pub enum ContractFlowError {
    AlreadyInitialized: ()
}

/// Authentication specific errors
pub enum AccessControlError {
    NoContractOwnerSet: (),
    CallerNotProposedOwner: (),
    CallerNotContractOwner: (),
    CallerNotFactoryRegistry: (),
    CallerNotOwnerOrFactoryRegistry: ()
}

/// Parameter validation errors
pub enum ParamError {
    NullContractID: (),
    InvalidNTokens: (),
    InvalidSwapFee: (),
    InvalidProtocolFee: (),
    InvalidProtocolFeeReceiver: (),
    ReceiverCannotBeThisContract: (),
    FactoryRegistryCannotBeThisContract: ()
}

/// Pool creation errors
pub enum PoolAdditionError {
    NullPoolID: (),
    InvalidPoolID: (),
    InvalidNTokens: (),
    InvalidTokenPair: (),
    PoolAlreadySet: (),
    FactoryMismatch: (),
    InvalidDecimalNumber: (),
    InvalidRegisteredTokens: (),
    InvalidFirstRegisteredToken: (),
    InvalidSecondRegisteredToken: ()
}
