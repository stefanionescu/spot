library errors;

/// Contract flow errors
pub enum ContractFlowError {
    AlreadyInitialized: ()
}

/// Authentication specific errors
pub enum AccessControlError {
    NoContractOwnerSet: (),
    CallerNotProposedOwner: (),
    CallerNotContractOwner: ()
}

/// Parameter validation errors
pub enum ParamError {
    NullRouter: (),
    NullVector: (),
    InvalidFactory: (),
    InvalidTokenIn: (),
    NullFeeReceiver: (),
    InvalidEndToken: (),
    InvalidFeeToken: (),
    LPVectorTooLong: (),
    InvalidMaxBridges: (),
    InvalidBatchLimit: (),
    NullFactoryRegistry: (),
    InvalidMaxBatchLimit: (),
    BridgeSameAsFeeToken: (),
    InvalidBridgePosition: (),
    TokenInCannotBeEndToken: (),
    MismatchedVectorLengths: ()
}

/// Bridge addition/removal errors
pub enum BridgeError {
    SameBridgeTwice: (),
    NoPoolForBridgeToken: (),
    FactoryNotRegistered: (),
    PreviousBridgeNotSet: (),
    UninitializedBridges: ()
}

/// Liquidity related errors
pub enum LPError {
    LPVectorTooLong: (),
    LeftoverLPTokens: (),
    NoUnderlyingReceived: ()
}

/// Swap related errors
pub enum SwapError {
    NoBridgePath: (),
    NothingToSwap: (),
    InvalidStartingToken: (),
    CannotSwapToEndToken: (),
    FeeReceiverNoEndTokenIncrease: ()
}
