library errors;

/// Contract flow errors
pub enum ContractFlowError {
    AlreadyInitialized: ()
}

/// Authentication specific errors
pub enum AccessControlError {
    CallerNotProposedOwner: (),
    CallerNotContractOwner: ()
}

/// Parameter validation errors
pub enum ParamError {
    NullAddress: (),
    NullReceiver: (),
    InvalidProtocolFee: (),
    InvalidProtocolFeeReceiver: (),
    ReceiverCannotBeThisContract: (),
    NotWhitelisted: ()
}

/// Factory specific errors
pub enum FactoryError {
    CannotSetProtocolFee: (),
    CannotSetProtocolFeeReceiver: ()
}
