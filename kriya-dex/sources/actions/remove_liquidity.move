module kdx_spot::remove_liquidity {
    use std::option::{Option};
    use sui::coin::{Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use kdx_spot::pool::{Self, Pool, KdxLpToken, LiquidityRemovedEvent};
    use kdx_spot::version::{Self, Version};

    #[lint_allow(self_transfer)]
    public entry fun remove_liquidity_entry<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_token: KdxLpToken<X, Y>,
        version: &Version,
        ctx: &mut TxContext
    ) {
        // check if version is supported
        version::assert_current_version(version);

        let (coin_x, coin_y, _) = pool::remove_liquidity<X, Y>(
            pool, 
            lp_token, 
            false,
            ctx,
        );

        transfer::public_transfer<Coin<X>>(coin_x, tx_context::sender(ctx));
        transfer::public_transfer<Coin<Y>>(coin_y, tx_context::sender(ctx));
    }

    public fun remove_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_token: KdxLpToken<X, Y>,
        return_event: bool,
        version: &Version,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>, Option<LiquidityRemovedEvent>) {
        // check if version is supported
        version::assert_current_version(version);

        pool::remove_liquidity<X, Y>(
            pool, 
            lp_token, 
            return_event,
            ctx,
        )
    }
}