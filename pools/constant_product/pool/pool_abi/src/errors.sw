library errors;

/// Contract flow errors
pub enum ContractFlowError {
    AlreadyInitialized: ()
}

/// LP related errors
pub enum LPError {
    InvalidAmounts: (),
    InvalidOutputToken: (),
    InvalidDataPackage: (),
    InsufficientLiquidityMinted: ()
}

/// Swap related errors
pub enum SwapError {
    InvalidDataPackage: (),
    InvalidOutputToken: (),
    InvalidInputToken: (),
    NullSwapRecipient: (),
    NullAmountIn: (),
    NullAmountOut: (),
    InsufficientAmountIn: (),
    PoolUninitialized: (),
    InsufficientLiquidityMinted: (),
    InvalidCallbackParams: ()
}

/// Parameter related errors
pub enum ParamError {
    InvalidTokenPair: (),
    InvalidFactory: ()
}
