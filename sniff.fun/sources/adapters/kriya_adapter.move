module sniff_dot_fun::kriya_adapter {
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};
    use kdx_spot::pool::{Self, PoolCap, KdxLpToken};
    use kdx_spot::default_config::{DefaultConfig};
    use kdx_spot::version::{Version};
    use kdx_spot::add_liquidity;
    use kdx_spot::create_pool;
    use sniff_dot_fun::freezer;
    use sniff_dot_fun::safu_receipt::{Self, SafuReceipt};

    // constants
    const AdapterId: u64 = 0;

    // error codes
    const EInvalidAdapter: u64 = 0;

    public fun process<T>(
        receipt: &mut SafuReceipt<T>, 
        coin_metadata_sui: &CoinMetadata<SUI>,
        coin_metadata_meme: &CoinMetadata<T>,
        config: &DefaultConfig,
        total_fee: u64,
        transfer_pool_cap_to: address,
        version: &Version,
        ctx: &mut TxContext
    ) {
        assert!(safu_receipt::target<T>(receipt) == AdapterId, EInvalidAdapter);
        
        // [1] create new kriya pool.
        let (mut pool, pool_cap) = create_pool::create_pool<SUI, T>(
            config,
            coin_metadata_sui,
            coin_metadata_meme,
            false, // is_stable false
            total_fee,
            version,
            ctx
        );

        // [2] add liquidity to pool.
        let (sui_balance, meme_balance) = safu_receipt::extract_assets(receipt);
        let (
            base_coin,
            meme_coin,
            base_val,
            meme_val
        ) = to_coins(sui_balance, meme_balance, ctx);

        let (lp_token, refund_token_x_opt, refund_token_y_opt, _) = add_liquidity::add_liquidity<SUI, T>(
            &mut pool,
            meme_coin, // token_y
            base_coin, // token_x
            meme_val, // amount_y_min_deposit
            base_val, // amount_x_min_deposit
            false, // return event
            version,
            ctx
        );

        if(option::is_some<Coin<SUI>>(&refund_token_x_opt)) {
            transfer::public_transfer<Coin<SUI>>(option::destroy_some<Coin<SUI>>(refund_token_x_opt), transfer_pool_cap_to);
        } else {
            option::destroy_none<Coin<SUI>>(refund_token_x_opt)
        };

        if(option::is_some<Coin<T>>(&refund_token_y_opt)) {
            transfer::public_transfer<Coin<T>>(option::destroy_some<Coin<T>>(refund_token_y_opt), transfer_pool_cap_to);
        } else {
            option::destroy_none<Coin<T>>(refund_token_y_opt)
        };

        // [3] assign ownerships of pool, pool_cap & lp_token.
        pool::transfer<SUI, T>(pool);
        transfer::public_transfer<PoolCap>(pool_cap, transfer_pool_cap_to);
        freezer::freeze_object<KdxLpToken<SUI, T>>(lp_token, ctx);
    }

    fun to_coins<A, B>(
        balance_a: Balance<A>, 
        balance_b: Balance<B>, 
        ctx: &mut TxContext
    ): (Coin<A>, Coin<B>, u64, u64) {
        let val_a = balance::value<A>(&balance_a);
        let val_b = balance::value<B>(&balance_b);
        let coin_a = coin::from_balance<A>(balance_a, ctx);
        let coin_b = coin::from_balance<B>(balance_b, ctx);

        (coin_a, coin_b, val_a, val_b)
    }
}