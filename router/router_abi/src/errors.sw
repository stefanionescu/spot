library errors;

/// Contract flow errors
pub enum ContractFlowError {
    AlreadyInitialized: ()
}

/// Parameter validation errors
pub enum ParamError {
    NullFactoryRegistry: ()
}

/// Token balance related errors
pub enum BalanceError {
    NotEnoughTokensToSwap: ()
}

/// Transfer error
pub enum TransferError {
    CannotTransferToPool: ()
}

/// Whitelisting errors
pub enum WhitelistError {
    FactoryNotRegistered: (),
    PoolNotRegistered: ()
}

/// Input related errors
pub enum InputErrors {
    NullAmountIn: (),
    NullMinAmountOut: (),
    NullFactory: (),
    NullPool: (),
    NullMinLiquidity: (),
    NullLiquidity: (),
    InvalidPathLength: (),
    InvalidTokenInputLength: (),
    IncorrectSlippageParams: ()
}

/// Output related errors
pub enum OutputErrors {
    TooLittleReceived: (),
    NotEnoughLiquidityMinted: (),
    IncorrectWithdrawnLen: ()
}
