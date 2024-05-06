module kdx_spot::create_pool {
    use sui::coin::{CoinMetadata};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use kdx_spot::pool::{Self, Pool, PoolCap};
    use kdx_spot::default_config::{DefaultConfig};
    use kdx_spot::version::{Self, Version};

    /// Entry function for create new `Pool` for Coin<X> & Coin<Y>.
    public entry fun create_pool_entry<X, Y>(
        default_config: &DefaultConfig,
        coin_metadata_x: &CoinMetadata<X>,
        coin_metadata_y: &CoinMetadata<Y>,
        is_stable: bool,
        total_fee: u64,
        version: &Version,
        ctx: &mut TxContext
    ) {
        // check if version is supported
        version::assert_current_version(version);

        let (pool, pool_cap) = pool::new<X, Y>(default_config, is_stable, coin_metadata_x, coin_metadata_y, total_fee, ctx);
        pool::transfer(pool);
        transfer::public_transfer(pool_cap, tx_context::sender(ctx));
    }

    public fun create_pool<X, Y>(
        default_config: &DefaultConfig,
        coin_metadata_x: &CoinMetadata<X>,
        coin_metadata_y: &CoinMetadata<Y>,
        is_stable: bool,
        total_fee: u64,
        version: &Version,
        ctx: &mut TxContext
    ): (Pool<X, Y>, PoolCap) {
        // check if version is supported
        version::assert_current_version(version);

        pool::new<X, Y>(default_config, is_stable, coin_metadata_x, coin_metadata_y, total_fee, ctx)
    }
}