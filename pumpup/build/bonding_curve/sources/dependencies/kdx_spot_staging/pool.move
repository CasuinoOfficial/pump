module kdx_spot::pool { 
    use std::option::{Self, Option};
    use sui::event;
    use sui::object::{Self, UID, ID};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::balance::{Self, Supply, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::math;
    use sui::transfer;
    use kdx_spot::default_config::{Self, DefaultConfig};
    use kdx_spot::constants;
    use kdx_spot::utils;
    use kdx_spot::admin_access::{AdminAccess};
    use kdx_spot::error;
    use kdx_spot::safe_math;

    friend kdx_spot::app;
    friend kdx_spot::create_pool;
    friend kdx_spot::add_liquidity;
    friend kdx_spot::remove_liquidity;
    friend kdx_spot::swap;

    /// The Pool token_x that will be used to mark the pool share
    /// of a liquidity provider. The first type parameter stands
    /// for the witness type of a pool. The seconds is for the
    /// coin held in the pool.
    struct LSP<phantom X, phantom Y> has drop {}

    #[lint_allow(coin_field)]
    struct KdxLpToken<phantom X, phantom Y> has key, store {
        id: UID,
        pool_id: ID,
        lsp: Coin<LSP<X, Y>>
    }

    /// Kriya AMM Pool object.
    struct Pool<phantom X, phantom Y> has key {
        id: UID,
        /// Balance of Coin<Y> in the pool.
        token_y: Balance<Y>,
        /// Balance of Coin<X> in the pool.
        token_x: Balance<X>,
        /// LP total supply share.
        lsp_supply: Supply<LSP<X, Y>>,
        /// Minimum required liquidity, non-withdrawable
        lsp_locked: Balance<LSP<X, Y>>,
        /// LP fee percent. Range[1-10000] (30 -> 0.3% fee)
        lp_fee_percent: u64,
        /// Protocol fee percent. Range[1-10000] (30 -> 0.3% fee)
        protocol_fee_percent: u64,
        /// Protocol fee pool to hold collected Coin<X> as fee.
        protocol_fee_x: Balance<X>,
        /// Protocol fee pool to hold collected Coin<Y> as fee.
        protocol_fee_y: Balance<Y>,
        /// If the pool uses the table_curve_formula
        is_stable: bool,
        /// 10^ Decimals of Coin<X>
        scaleX: u64,
        /// 10^ Decimals of Coin<Y>
        scaleY: u64
    }

    struct PoolCap has key, store {
        id: UID,
        pool_id: ID
    }

    struct PoolCreatedEvent has drop, copy {
        pool_id: ID,
        creator: address,
        lp_fee_percent: u64,
        protocol_fee_percent: u64,
        is_stable: bool,
        scaleX: u64,
        scaleY: u64
    }

    struct LiquidityAddedEvent has drop, copy {
        pool_id: ID,
        liquidity_provider: address,
        amount_x: u64,
        amount_y: u64,
        reserve_x: u64,
        reserve_y: u64,
        lsp_minted: u64
    }

    struct LiquidityRemovedEvent has drop, copy {
        pool_id: ID,
        liquidity_provider: address,
        amount_x: u64,
        amount_y: u64,
        reserve_x: u64,
        reserve_y: u64,
        lsp_burned: u64
    }

    struct SwapEvent<phantom T> has drop, copy {
        pool_id: ID,
        user: address,
        reserve_x: u64,
        reserve_y: u64,
        amount_in: u64,
        amount_out: u64
    }

    public(friend) fun new<X, Y>(
        default_config: &DefaultConfig,
        is_stable: bool,
        coin_metadata_x: &CoinMetadata<X>,
        coin_metadata_y: &CoinMetadata<Y>,
        total_fee: u64,
        ctx: &mut TxContext
    ): (Pool<X, Y>, PoolCap) {
        let (lp_fee_percent, protocol_fee_percent) = default_config::fee(default_config, is_stable, total_fee);
        
        assert!(((lp_fee_percent + protocol_fee_percent) as u128) <= constants::fee_scalling(), error::wrongFee());
        
        let pool = Pool {
            id: object::new(ctx),
            token_x: balance::zero<X>(),
            token_y: balance::zero<Y>(),
            lsp_supply: balance::create_supply(LSP<X, Y>{}),
            lsp_locked: balance::zero<LSP<X, Y>>(),
            lp_fee_percent: lp_fee_percent,
            protocol_fee_percent: protocol_fee_percent,
            protocol_fee_x: balance::zero<X>(),
            protocol_fee_y: balance::zero<Y>(),
            is_stable: is_stable,
            scaleX: get_scale_from_coinmetadata(coin_metadata_x),
            scaleY: get_scale_from_coinmetadata(coin_metadata_y),
        };
        let (lp_fee_percent, protocol_fee_percent, is_stable, scaleX, scaleY) = configs<X, Y>(&pool);
        let event = PoolCreatedEvent {
            pool_id: id(&pool),
            creator: tx_context::sender(ctx),
            lp_fee_percent: lp_fee_percent,
            protocol_fee_percent: protocol_fee_percent,
            is_stable: is_stable,
            scaleX: scaleX,
            scaleY: scaleY
        };
        event::emit<PoolCreatedEvent>(event);

        let pool_cap = PoolCap {
            id: object::new(ctx),
            pool_id: object::id(&pool)
        };

        (pool, pool_cap)
    }

    #[allow(lint(share_owned))]
    public fun transfer<X, Y>(pool: Pool<X, Y>) {
        transfer::share_object(pool);
    }

    // Admin only operation.
    public(friend) fun set_fee<X, Y>(self: &mut Pool<X, Y>, lp_fee_percent: u64, protocol_fee_percent: u64, _: &AdminAccess) {
        self.lp_fee_percent = lp_fee_percent;
        self.protocol_fee_percent = protocol_fee_percent;
    }

    // Admin only operation.
    public(friend) fun claim_fee<X, Y>(
        self: &mut Pool<X, Y>, 
        amount_x: u64, 
        amount_y: u64, 
        _: &AdminAccess,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>) {
        let fee_x_balance = balance::split<X>(&mut self.protocol_fee_x, amount_x);
        let fee_y_balance = balance::split<Y>(&mut self.protocol_fee_y, amount_y);

        (coin::from_balance(fee_x_balance, ctx), coin::from_balance(fee_y_balance, ctx))
    }

    /// Swap `Coin<Y>` for the `Coin<X>`.
    /// Returns Coin<X>.
    public(friend) fun swap_token_y<X, Y>(
        pool: &mut Pool<X, Y>, token_y: Coin<Y>, min_recieve_x: u64, return_event: bool, ctx: &mut TxContext
    ): (Coin<X>, Option<SwapEvent<Y>>) {
        assert!(coin::value(&token_y) > 0, error::zeroAmount());

        let token_y_balance = coin::into_balance(token_y);
        let (token_y_reserve, token_x_reserve, _) = get_reserves(pool);
        assert!(token_y_reserve > 0 && token_x_reserve > 0, error::reservesEmpty());

        let protocol_fee_value = (((balance::value(&token_y_balance) as u128) * (pool.protocol_fee_percent as u128)) / constants::fee_scalling() as u64);
        let protocol_fee_coin = coin::take<Y>(&mut token_y_balance, protocol_fee_value, ctx);

        let output_amount:u64;
        let input_amount = balance::value<Y>(&token_y_balance);

        if(pool.is_stable) {
            output_amount = utils::get_input_price_stable(balance::value<Y>(&token_y_balance), token_y_reserve, token_x_reserve, pool.lp_fee_percent, pool.scaleY, pool.scaleX);
        } else {
            output_amount = utils::get_input_price_uncorrelated(balance::value<Y>(&token_y_balance), token_y_reserve, token_x_reserve, pool.lp_fee_percent);
        };
        
        assert!(output_amount >= min_recieve_x, error::swapOutLessthanExpected());

        balance::join(&mut pool.token_y, token_y_balance);
        balance::join(&mut pool.protocol_fee_y, coin::into_balance<Y>(protocol_fee_coin));
        let swapped_coin = coin::take(&mut pool.token_x, output_amount, ctx);

        let (token_y_reserve_post, token_x_reserve_post, _) = get_reserves(pool);
        assert_lp_value_is_increased(
            pool.is_stable, 
            pool.scaleX, 
            pool.scaleY, 
            (token_x_reserve as u128), 
            (token_y_reserve as u128),
            (token_x_reserve_post as u128),
            (token_y_reserve_post as u128));
        
        let event = emit_swap_event<Y>(
            *object::uid_as_inner(&pool.id),
            tx_context::sender(ctx),
            token_x_reserve_post,
            token_y_reserve_post,
            // xxx: should this be post fee deduction?
            input_amount,
            output_amount
        );

        (
            swapped_coin,
            if(return_event) option::some<SwapEvent<Y>>(event) else option::none<SwapEvent<Y>>()
        )
    }

    /// Swap `Coin<X>` for the `Coin<Y>`.
    /// Returns the swapped `Coin<Y>`.
    public(friend) fun swap_token_x<X, Y>(
        pool: &mut Pool<X, Y>, token_x: Coin<X>, min_recieve_y: u64, return_event: bool, ctx: &mut TxContext
    ): (Coin<Y>, Option<SwapEvent<X>>) {
        // assert!(pool.is_swap_enabled, ESwapDisabled);
        assert!(coin::value(&token_x) > 0, error::zeroAmount());

        let token_x_balance = coin::into_balance(token_x);
        let (token_y_reserve, token_x_reserve, _) = get_reserves(pool);
        assert!(token_y_reserve > 0 && token_x_reserve > 0, error::reservesEmpty());

        let protocol_fee_value = ((balance::value(&token_x_balance) as u128) * (pool.protocol_fee_percent as u128) / (constants::fee_scalling() as u128) as u64);
        let protocol_fee_coin = coin::take<X>(&mut token_x_balance, protocol_fee_value, ctx);

        let _output_amount: u64 = 0;
        let input_amount: u64 = balance::value(&token_x_balance);

        if(pool.is_stable) {
            _output_amount = utils::get_input_price_stable(balance::value(&token_x_balance), token_x_reserve, token_y_reserve, pool.lp_fee_percent, pool.scaleX, pool.scaleY);
        } else {
            _output_amount = utils::get_input_price_uncorrelated(balance::value(&token_x_balance), token_x_reserve, token_y_reserve, pool.lp_fee_percent);
        };
        
        assert!(_output_amount >= min_recieve_y, error::swapOutLessthanExpected());
        
        balance::join(&mut pool.token_x, token_x_balance);
        balance::join(&mut pool.protocol_fee_x, coin::into_balance<X>(protocol_fee_coin));
        let swapped_coin = coin::take(&mut pool.token_y, _output_amount, ctx);
        let (token_y_reserve_post, token_x_reserve_post, _) = get_reserves(pool);
        assert_lp_value_is_increased(
            pool.is_stable, 
            pool.scaleX, 
            pool.scaleY, 
            (token_x_reserve as u128), 
            (token_y_reserve as u128),
            (token_x_reserve_post as u128),
            (token_y_reserve_post as u128));

        let event = emit_swap_event<X>(
            *object::uid_as_inner(&pool.id),
            tx_context::sender(ctx),
            token_x_reserve_post,
            token_y_reserve_post,
            input_amount,
            _output_amount
        );

        (
            swapped_coin,
            if(return_event) option::some<SwapEvent<X>>(event) else option::none<SwapEvent<X>>()
        )
    }

    /// Add liquidity to the `Pool`. Sender needs to provide both
    /// `Coin<Y>` and `Coin<X>`, and in exchange he gets `Coin<LSP>` -
    /// liquidity provider tokens.
    public(friend) fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>, 
        token_y: Coin<Y>, 
        token_x: Coin<X>, 
        amount_y_min_deposit: u64,
        amount_x_min_deposit: u64,
        return_event: bool,
        ctx: &mut TxContext
    ): (KdxLpToken<X, Y>, Option<Coin<X>>, Option<Coin<Y>>, Option<LiquidityAddedEvent>) {
        let token_x_amount = coin::value(&token_x);
        let token_y_amount = coin::value(&token_y);
        assert!(token_y_amount > 0 && token_x_amount > 0, error::zeroAmount());

        let (calc_amount_x_to_deposit, calc_amount_y_to_deposit) = get_amount_for_add_liquidity<X, Y>(
            pool,
            token_x_amount,
            token_y_amount,
            amount_x_min_deposit,
            amount_y_min_deposit
        );
        
        let refund_token_x = option::none<Coin<X>>();
        let refund_token_y = option::none<Coin<Y>>();

        if(token_x_amount > calc_amount_x_to_deposit) {
            option::fill(&mut refund_token_x, coin::split(&mut token_x, token_x_amount - calc_amount_x_to_deposit, ctx));
        };
        if(token_y_amount > calc_amount_y_to_deposit) {
            option::fill(&mut refund_token_y, coin::split(&mut token_y, token_y_amount - calc_amount_y_to_deposit, ctx));
        };
        

        let token_y_balance = coin::into_balance(token_y);
        let token_x_balance = coin::into_balance(token_x);

        let lsp_token = mint_lsp_token(pool, token_x_balance, token_y_balance, ctx);
        
        let (reserve_y_post, reserve_x_post, _) = get_reserves(pool);
        let event = emit_liquidity_added_event(
            *object::uid_as_inner(&pool.id),
            tx_context::sender(ctx),
            calc_amount_x_to_deposit, 
            calc_amount_y_to_deposit,
            reserve_x_post, 
            reserve_y_post,
            coin::value(&lsp_token)
        );
        
        (
            KdxLpToken {
                id: object::new(ctx),
                pool_id: *object::uid_as_inner(&pool.id),
                lsp: lsp_token
            },
            refund_token_x,
            refund_token_y,
            if(return_event) option::some<LiquidityAddedEvent>(event) else option::none<LiquidityAddedEvent>()
        )
    }

    /// Remove liquidity from the `Pool` by burning `Coin<LSP>`.
    /// Returns `Coin<X>` and `Coin<Y>`.
    public(friend) fun remove_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_token: KdxLpToken<X, Y>,
        return_event: bool,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>, Option<LiquidityRemovedEvent>) {
        assert!(lp_token.pool_id == *object::uid_as_inner(&pool.id), error::invalidLPToken());

        // If there's a non-empty LSP, we can
        assert!(lp_token_value(&lp_token) > 0, error::zeroAmount());
        let lsp_amount = lp_token_value(&lp_token);
        let lsp_removed = coin::split(&mut lp_token.lsp, lsp_amount, ctx);

        let (token_y_reserve, token_x_reserve, lsp_supply) = get_reserves(pool);
        let token_y_removed = safe_math::safe_mul_div_u64(token_y_reserve, lp_token_value(&lp_token), lsp_supply);
        let token_x_removed = safe_math::safe_mul_div_u64(token_x_reserve, lp_token_value(&lp_token), lsp_supply);

        assert!(token_y_removed > 0 && token_x_removed > 0, error::zeroAmount());

        balance::decrease_supply(&mut pool.lsp_supply, coin::into_balance(lsp_removed));
        
        // burn lp token.
        let KdxLpToken {id, pool_id: _, lsp} = lp_token;
        object::delete(id);
        coin::destroy_zero(lsp);

        let (reserve_y_post, reserve_x_post, _) = get_reserves(pool);
        let event = emit_liquidity_removed_event(
            *object::uid_as_inner(&pool.id),
            tx_context::sender(ctx),
            token_x_removed,
            token_y_removed,
            reserve_x_post,
            reserve_y_post, 
            lsp_amount
        );

        (
            coin::take(&mut pool.token_x, token_x_removed, ctx),
            coin::take(&mut pool.token_y, token_y_removed, ctx),
            if(return_event) option::some<LiquidityRemovedEvent>(event) else option::none<LiquidityRemovedEvent>()
        )
    }

    /* Public geters */

    /// Get TokenX/Y balance & treasury cap. A Getter function to get frequently get values:
    /// - amount of token_y
    /// - amount of token_x
    /// - total supply of LSP
    public fun get_reserves<X, Y>(pool: &Pool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.token_y),
            balance::value(&pool.token_x),
            balance::supply_value(&pool.lsp_supply)
        )
    }

    public fun lp_token_split<X, Y>(self: &mut KdxLpToken<X, Y>, split_amount: u64, ctx: &mut TxContext): KdxLpToken<X, Y> {
        KdxLpToken {
            id: object::new(ctx),
            pool_id: self.pool_id,
            lsp: coin::split(&mut self.lsp, split_amount, ctx)
        }
    }

    public fun lp_token_join<X, Y>(self: &mut KdxLpToken<X, Y>, lp_token: KdxLpToken<X, Y>) {
        assert!(self.pool_id == lp_token.pool_id, error::invalidLPToken());
        let KdxLpToken {id, pool_id: _, lsp} = lp_token;
        object::delete(id);
        coin::join(&mut self.lsp, lsp);
    }

    public fun lp_token_value<X, Y>(self: &KdxLpToken<X, Y>): u64 {
        coin::value(&self.lsp)
    }

    public fun lp_token_pool_id<X, Y>(self: &KdxLpToken<X, Y>): &ID {
        &self.pool_id
    }

    public fun lp_destroy_zero<X, Y>(self: KdxLpToken<X, Y>) {
        let KdxLpToken {id, pool_id: _, lsp} = self;
        coin::destroy_zero(lsp);
        object::delete(id);
    }

    public fun configs<X, Y>(self: &Pool<X, Y>): (u64, u64, bool, u64, u64) {
        (self.lp_fee_percent, self.protocol_fee_percent, self.is_stable, self.scaleX, self.scaleY)
    }

    public fun is_stable<X, Y>(self: &Pool<X, Y>): bool {
        self.is_stable
    }

    public fun id<X, Y>(pool: &Pool<X, Y>): ID {
        *object::uid_as_inner(&pool.id)
    }

    public fun get_pool_id(pool_cap: &PoolCap): ID {
        pool_cap.pool_id
    }

    public fun read_liquidity_added_event(event: &LiquidityAddedEvent): (ID, address, u64, u64, u64, u64, u64) {
        (
            event.pool_id,
            event.liquidity_provider,
            event.amount_x,
            event.amount_y,
            event.reserve_x,
            event.reserve_y,
            event.lsp_minted
        )
    }

    public fun read_liquidity_removed_event(event: &LiquidityRemovedEvent): (ID, address, u64, u64, u64, u64, u64) {
        (
            event.pool_id,
            event.liquidity_provider,
            event.amount_x,
            event.amount_y,
            event.reserve_x,
            event.reserve_y,
            event.lsp_burned
        )
    }

    public fun read_swap_event<T>(event: &SwapEvent<T>): (ID, address, u64, u64, u64, u64) {
        (
            event.pool_id,
            event.user,
            event.reserve_x,
            event.reserve_y,
            event.amount_in,
            event.amount_out
        )
    }

    //// Private functions

    fun get_amount_for_add_liquidity<X, Y>(
        pool: &Pool<X, Y>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min_deposit: u64,
        amount_y_min_deposit: u64
    ): (u64, u64) {
        let (reserve_y, reserve_x, _) = get_reserves(pool);
        if(reserve_x == 0 && reserve_y == 0) {
            (amount_x_desired, amount_y_desired)
        } else {
            let amount_b_req_to_deposit = get_token_amount_to_maintain_ratio(amount_x_desired, reserve_x, reserve_y); // 0 is fee param.
            if (amount_b_req_to_deposit <= amount_y_desired) {
                assert!(amount_b_req_to_deposit >= amount_y_min_deposit, error::liquidityInsufficientBAmount());
                (amount_x_desired, amount_b_req_to_deposit)
            } else {
                let amount_a_req_to_deposit = get_token_amount_to_maintain_ratio(amount_y_desired, reserve_y, reserve_x); // 0 is fee param.
                assert!(amount_a_req_to_deposit <= amount_x_desired, error::liquidityOverLimitADesired());
                assert!(amount_a_req_to_deposit >= amount_x_min_deposit, error::liquidityInsufficientAAmount());
                (amount_a_req_to_deposit, amount_y_desired)
            } 
        }
    }

    /// calculates amount of coin_out required to maintain same asset ratios in LP pool
    fun get_token_amount_to_maintain_ratio(coin_in: u64, reserve_in: u64, reserve_out: u64): u64 {
        assert!(coin_in > 0, error::amountZero());
        assert!(reserve_in > 0 && reserve_out > 0, error::reserveZero());

        // res = reserve_in * coin_in / reserve_out
        let res = safe_math::safe_mul_div_u64(coin_in, reserve_out, reserve_in);
        (res as u64)
    }

    fun mint_lsp_token<X, Y>(
        pool: &mut Pool<X, Y>,
        balance_x: Balance<X>,
        balance_y: Balance<Y>,
        ctx: &mut TxContext
    ): Coin<LSP<X, Y>> {
        let (reserve_y, reserve_x, _) = get_reserves(pool);

        let amount_x = balance::value(&balance_x);
        let amount_y = balance::value(&balance_y);

        let total_supply = balance::supply_value(&pool.lsp_supply);
        let liquidity: u64;
        if (total_supply == 0) {
            // adding liquidity for the first time
            liquidity = (math::sqrt_u128((amount_x as u128) * (amount_y as u128)) as u64);
            assert!(liquidity > constants::minimal_liquidity(), error::notEnoughInitialLiquidity());
            liquidity = liquidity - constants::minimal_liquidity();
            // add minimal_liquidity to pool reserve
            balance::join(&mut pool.lsp_locked, balance::increase_supply(&mut pool.lsp_supply, constants::minimal_liquidity()));
        } else {
            liquidity = math::min(
                safe_math::safe_mul_div_u64(amount_x, total_supply, reserve_x),
                safe_math::safe_mul_div_u64(amount_y, total_supply, reserve_y));
        };

        assert!(liquidity > 0, error::liquidityInsufficientMinted());

        balance::join(&mut pool.token_x, balance_x);
        balance::join(&mut pool.token_y, balance_y);

        coin::from_balance(
            balance::increase_supply(
                &mut pool.lsp_supply,
                liquidity
            ), ctx)
    }

    fun assert_lp_value_is_increased(
        is_stable: bool,
        x_scale: u64,
        y_scale: u64,
        x_res: u128,
        y_res: u128,
        x_res_post_swap: u128,
        y_res_post_swap: u128,
    ) {
        if (is_stable) {
            let lp_value_before_swap = utils::lp_value(x_res, x_scale, y_res, y_scale);
            let lp_value_after_swap_and_fee = utils::lp_value(x_res_post_swap, x_scale, y_res_post_swap, y_scale);
            assert!(lp_value_after_swap_and_fee > lp_value_before_swap, error::incorrectPoolConstantPostSwap());
        } else {
            let lp_value_before_swap = x_res * y_res;
            let lp_value_after_swap_and_fee = x_res_post_swap * y_res_post_swap;
            assert!(lp_value_after_swap_and_fee > lp_value_before_swap, error::incorrectPoolConstantPostSwap());
        };
    }

    fun get_scale_from_coinmetadata<X>(coin_metadata: &CoinMetadata<X>): u64 {
        let coin_decimals = coin::get_decimals<X>(coin_metadata);
        sui::math::pow(10, coin_decimals)
    }

    fun emit_liquidity_added_event(
        pool_id: ID,
        sender: address,
        amount_x: u64,
        amount_y: u64,
        reserve_x: u64,
        reserve_y: u64,
        lsp_minted: u64
    ): LiquidityAddedEvent {
        let event = LiquidityAddedEvent {
            pool_id: pool_id,
            liquidity_provider: sender,
            amount_x: amount_x,
            amount_y: amount_y,
            reserve_x: reserve_x,
            reserve_y: reserve_y,
            lsp_minted: lsp_minted
        };
        event::emit<LiquidityAddedEvent>(event);
        
        event
    }

    fun emit_liquidity_removed_event(
        pool_id: ID,
        sender: address,
        amount_x: u64,
        amount_y: u64,
        reserve_x: u64,
        reserve_y: u64,
        lsp_burned: u64
    ): LiquidityRemovedEvent {
        let event = LiquidityRemovedEvent {
            pool_id: pool_id,
            liquidity_provider: sender,
            amount_x: amount_x,
            amount_y: amount_y,
            reserve_x: reserve_x,
            reserve_y: reserve_y,
            lsp_burned: lsp_burned
        };
        event::emit<LiquidityRemovedEvent>(event);

        event
    }

    fun emit_swap_event<T>(
        pool_id: ID, 
        user: address, 
        reserve_x: u64, 
        reserve_y: u64, 
        amount_in: u64, 
        amount_out: u64
    ): SwapEvent<T> {
        let event = SwapEvent<T> {
            pool_id: pool_id,
            user: user,
            reserve_x: reserve_x,
            reserve_y: reserve_y,
            amount_in: amount_in,
            amount_out: amount_out
        };
        event::emit<SwapEvent<T>>(event);

        event
    }

    #[test_only]
    public fun mint_lp_token<X, Y>(lsp: Coin<LSP<X, Y>>, pool: &Pool<X, Y>, ctx: &mut TxContext): KdxLpToken<X, Y> {
        KdxLpToken<X, Y> {
            id: object::new(ctx),
            pool_id: *object::uid_as_inner(&pool.id),
            lsp: lsp
        }
    }
}