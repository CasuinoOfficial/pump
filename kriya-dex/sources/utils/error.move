module kdx_spot::error {
     /// For when supplied Coin is zero.
    public fun zeroAmount(): u64 { 0 }
    /// Allowed values are: [0-10000).
    public fun wrongFee(): u64 { 1 }
    public fun reservesEmpty(): u64 { 2 }
    public fun insufficientBalance(): u64 { 3 }
    public fun liquidityInsufficientBAmount(): u64 { 4 }
    public fun liquidityInsufficientAAmount(): u64 { 5 }
    public fun liquidityOverLimitADesired(): u64 { 6 }
    public fun liquidityInsufficientMinted(): u64 { 7 }
    public fun swapOutLessthanExpected(): u64 { 8 }
    public fun unauthorized(): u64 { 9 }
    public fun callerNotAdmin(): u64 { 10 }
    public fun swapDisabled(): u64 { 11 }
    public fun addLiquidityDisabled(): u64 { 12 }
    public fun alreadyWhitelisted(): u64 { 13 }
    /// When not enough liquidity minted.
    public fun notEnoughInitialLiquidity(): u64 { 14 }
    public fun removeAdminNotAllowed(): u64 { 15 }
    public fun incorrectPoolConstantPostSwap(): u64 { 16 }
    public fun feeInvalid(): u64 { 17 }
    public fun amountZero(): u64 { 18 }
    public fun reserveZero(): u64 { 19 }
    public fun invalidLPToken(): u64 { 20}
    public fun version_mismatch(): u64 { 21 }

}