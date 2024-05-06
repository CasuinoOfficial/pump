module kdx_spot::swap {
    use std::option::{Option};
    use sui::coin::{Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use kdx_spot::pool::{Self, Pool, SwapEvent};
    use kdx_spot::version::{Self, Version};

    #[lint_allow(self_transfer)]
    public entry fun swap_token_x_entry<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_x: Coin<X>, 
        min_recieve_y: u64, 
        version: &Version,
        ctx: &mut TxContext
    ) {
        // check if version is supported
        version::assert_current_version(version);

        let (swapped_coin, _) = pool::swap_token_x(pool, token_x, min_recieve_y, false, ctx);
        transfer::public_transfer<Coin<Y>>(swapped_coin, tx_context::sender(ctx));
    }

    public fun swap_token_x<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_x: Coin<X>, 
        min_recieve_y: u64,
        return_event: bool,
        version: &Version,
        ctx: &mut TxContext
    ): (Coin<Y>, Option<SwapEvent<X>>) {
        // check if version is supported
        version::assert_current_version(version);

        pool::swap_token_x(pool, token_x, min_recieve_y, return_event, ctx)
    }

    #[lint_allow(self_transfer)]
    public entry fun swap_token_y_entry<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_y: Coin<Y>, 
        min_recieve_x: u64, 
        version: &Version,
        ctx: &mut TxContext
    ) {
        // check if version is supported
        version::assert_current_version(version);

        let (swapped_coin, _) = pool::swap_token_y(pool, token_y, min_recieve_x, false, ctx);
        transfer::public_transfer<Coin<X>>(swapped_coin, tx_context::sender(ctx));
    }

    public fun swap_token_y<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_y: Coin<Y>, 
        min_recieve_x: u64,
        return_event: bool,
        version: &Version,
        ctx: &mut TxContext
    ): (Coin<X>, Option<SwapEvent<Y>>) {
        // check if version is supported
        version::assert_current_version(version);

        pool::swap_token_y(pool, token_y, min_recieve_x, return_event, ctx)
    }
}