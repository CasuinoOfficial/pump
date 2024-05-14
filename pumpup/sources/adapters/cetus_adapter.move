// module bonding_curve::cetus_adapter {
    
//     use sui::coin::{Self, Coin, CoinMetadata};
//     use sui::balance::{Self, Balance};
//     use sui::sui::{SUI};
//     use bonding_curve::migration_receipt::{Self, MigrationReceipt};
//     use cetus_clmm::factory::{create_pool_with_liquidity, Pools};

//     // constants
//     const AdapterId: u64 = 2;

//     // Default decimal precision
//     const DEFAULT_PRECISION: u8 = 9;

//     // error codes
//     const EInvalidAdapter: u64 = 0;

//     public fun process<T>(
//         receipt: &mut MigrationReceipt<T>, 
//         _pools: &mut Pools,
//         coin_metadata_sui: &CoinMetadata<SUI>,
//         coin_metadata_token: &CoinMetadata<T>,
//         config: &DefaultConfig,
//         total_fee: u64,
//         transfer_pool_cap_to: address,
//         version: &Version,
//         ctx: &mut TxContext
//     ) {
//         assert!(migration_receipt::target<T>(receipt) == AdapterId, EInvalidAdapter);
        
//         // [1] extract assets and balance.
//         let (sui_balance, token_balance) = migration_receipt::extract_assets(receipt);
//         let (
//             base_coin,
//             meme_coin,
//             base_val,
//             meme_val
//         ) = to_coins(sui_balance, token_balance, ctx);

//         // [2] add liquidity to pool.
//         let (lp_position, a, b) = create_pool_with_liquidity<SUI, T>(
            
//         )

//         // [3] assign ownerships of pool, pool_cap & lp_token.

//     }

//     fun to_coins<A, B>(
//         balance_a: Balance<A>, 
//         balance_b: Balance<B>, 
//         ctx: &mut TxContext
//     ): (Coin<A>, Coin<B>, u64, u64) {
//         let val_a = balance::value<A>(&balance_a);
//         let val_b = balance::value<B>(&balance_b);
//         let coin_a = coin::from_balance<A>(balance_a, ctx);
//         let coin_b = coin::from_balance<B>(balance_b, ctx);

//         (coin_a, coin_b, val_a, val_b)
//     }
// }