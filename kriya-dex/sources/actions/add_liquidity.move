module kdx_spot::add_liquidity {
    use std::option::{Self, Option};
    use sui::coin::{Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use kdx_spot::pool::{Self, Pool, KdxLpToken, LiquidityAddedEvent};
    use kdx_spot::version::{Self, Version};

    #[lint_allow(self_transfer)]
    public entry fun add_liquidity_entry<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_y: Coin<Y>, 
        token_x: Coin<X>, 
        amount_y_min_deposit: u64,
        amount_x_min_deposit: u64,
        version: &Version,
        ctx: &mut TxContext
    ) {
        // check if version is supported
        version::assert_current_version(version);

        let (lp_token, refund_token_x_opt, refund_token_y_opt, _) = pool::add_liquidity<X, Y>(
            pool, 
            token_y, 
            token_x, 
            amount_y_min_deposit,
            amount_x_min_deposit,
            false,
            ctx,
        );

        transfer::public_transfer<KdxLpToken<X, Y>>(lp_token, tx_context::sender(ctx));
        
        if(option::is_some<Coin<X>>(&refund_token_x_opt)) {
            transfer::public_transfer<Coin<X>>(option::destroy_some<Coin<X>>(refund_token_x_opt), tx_context::sender(ctx));
        } else {
            option::destroy_none<Coin<X>>(refund_token_x_opt)
        };

        if(option::is_some<Coin<Y>>(&refund_token_y_opt)) {
            transfer::public_transfer<Coin<Y>>(option::destroy_some<Coin<Y>>(refund_token_y_opt), tx_context::sender(ctx));
        } else {
            option::destroy_none<Coin<Y>>(refund_token_y_opt)
        };
    }

    /// Entry function for create new `Pool` for Coin<X> & Coin<Y>.
    public fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_y: Coin<Y>, 
        token_x: Coin<X>, 
        amount_y_min_deposit: u64,
        amount_x_min_deposit: u64,
        return_event: bool,
        version: &Version,
        ctx: &mut TxContext
    ): (KdxLpToken<X, Y>, Option<Coin<X>>, Option<Coin<Y>>, Option<LiquidityAddedEvent>) {
        // check if version is supported
        version::assert_current_version(version);
        
        pool::add_liquidity<X, Y>(
            pool, 
            token_y, 
            token_x, 
            amount_y_min_deposit,
            amount_x_min_deposit,
            return_event,
            ctx,
        )
    }
}