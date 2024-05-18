#[test_only]
module bonding_curve::meme {

    use std::option;
    use sui::coin;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::url;

    public struct MEME has drop {}

    const ADMIN: address = @0xAAA;

    fun init(otw: MEME, ctx: &mut TxContext) {
        let (meme_treasury_cap, meme_metadata) = coin::create_currency(
            otw,
            9,
            b"MEME",
            b"MEME USD",
            b"the meme used to mint",
            option::some(url::new_unsafe_from_bytes(
                b"https://ipfs.io/ipfs/QmYH4seo7K9CiFqHGDmhbZmzewHEapAhN9aqLRA7af2vMW"),
            ),
            ctx,
        );
        transfer::public_freeze_object(meme_treasury_cap);
        transfer::public_freeze_object(meme_metadata);
    }
}

#[test_only]
module bonding_curve::bonding_curve_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use bonding_curve::meme::MEME;
    use sui::coin::{Self};
    use bonding_curve::curve::{Self, BondingCurve, Configurator};
    use sui::sui::SUI;
    use std::ascii::{Self, String};

    const ENotImplemented: u64 = 0;
    const ADMIN: address = @0xAAA;
    const COIN_SCALER: u64 = 1_000_000_000;

    #[test_only]
    fun setup_for_testing(): Scenario {
        let mut scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;

        // Create the contract
        ts::next_tx(scenario, ADMIN);
        {
            curve::init_for_testing(ts::ctx(scenario));
        };
        ts::next_tx(scenario, ADMIN);
        {
            let mut configurator = ts::take_shared<Configurator>(scenario);
            let init_fund = coin::mint_for_testing<MEME>(1_000_000_000 * COIN_SCALER, ts::ctx(scenario));
            let init_sui = coin::mint_for_testing<SUI>(1 * COIN_SCALER + 1, ts::ctx(scenario));
            let curve = curve::list_for_testing<MEME>(
                &mut configurator,
                init_sui,
                init_fund,
                option::none<String>(),
                option::none<String>(),
                option::none<String>(),
                1,
                ts::ctx(scenario)
            );
            curve::transfer<MEME>(curve);
            ts::return_shared(configurator);
        };
        
        scenario_val
    }

    #[test]
    fun test_bonding_curve() {
        let scenario_val = setup_for_testing();
        ts::end(scenario_val);
    }

    // #[test]
    // fun test_remove_liquidity() {
    //     let scenario_val = setup_for_testing();
    //     let scenario = &mut scenario_val;
    //     let bob = @0xbb;
    //     ts::next_tx(scenario, bob);
    //     {
    //         let pool = ts::take_shared<Pool<MEME>>(scenario);
    //         let pooler = ts::take_shared<Pooler>(scenario);

    //         let result_meme = curve::buy<MEME>(
    //             &mut pooler,
    //             &mut pool,
    //             coin::mint_for_testing<SUI>(25000 * COIN_SCALER, ts::ctx(scenario)),
    //             ts::ctx(scenario),
    //         );
    //         let (sui_reserve, tok_reserve, _, _, _) = curve::get_info<MEME>(&pool);

    //         let result_sui = curve::sell<MEME>(
    //             &mut pooler,
    //             &mut pool,
    //             result_meme,
    //             ts::ctx(scenario),
    //         );

    //         // std::debug::print(&result_meme);
    //         transfer::public_transfer(result_sui, bob);
    //         // std::debug::print(&sui_reserve);
    //         // std::debug::print(&tok_reserve);
    //         ts::return_shared(pool);
    //         ts::return_shared(pooler);
    //     };
    //     ts::end(scenario_val);

    //     // assert removing from pool works

    //     // set liquidity to 0
    //     // assert removing from pool fails
    // }
}