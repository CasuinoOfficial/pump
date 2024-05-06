module sniff_dot_fun::meme {
    use std::type_name;
    use std::string;
    use sui::url::{Url};
    use std::ascii::{Self, String};
    use sui::coin::{Self, CoinMetadata, TreasuryCap, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};
    use sui::event;
    use sniff_dot_fun::safu_receipt::{Self, SafuReceipt};
    use sniff_dot_fun::freezer;
    use sniff_dot_fun::admin::{Self, AdminAccess, AdminCap};

    // error codes
    const ETreasuryCapSupplyNonZero: u64 = 0;
    const ESwapOutLessthanExpected: u64 = 1;
    const EInvalidMemeDecimals: u64 = 2;
    const EInsufficientSuiBalance: u64 = 3;
    const EPoolNotActiveForTrading: u64 = 4;
    const EInvalidPoolStatePostSwap: u64 = 5;
    const EPoolNotMigratable: u64 = 6;

    // constants    
    const MemeCoinDecimals: u8 = 9;
    const FeeScaling: u128 = 1_000_000;

    // default values
    const DefaultSupply: u64 = 1_000_000_000 * 1_000_000_000;
    const DefaultTargetSupplyThreshold: u64 = 200_000_000 * 1_000_000_000;
    const DefaultVirtualLiquidity: u64 = 5000 * 1_000_000_000;
    const DefaultMigrationFee: u64 = 800 * 1_000_000_000;
    const DefaultListingFee: u64 = 1 * 1_000_000_000;
    const DefaultSwapFee: u64 = 10_000; // 1% fee

    public struct BondingCurve<phantom T> has key {
        id: UID,
        sui_balance: Balance<SUI>,
        meme_balance: Balance<T>,
        fee: Balance<SUI>,
        virtual_sui_amt: u64,
        target_supply_threshold: u64,
        swap_fee: u64,
        is_active: bool,
        // Metadata Info
        creator: address,
    }

    public struct Configurator has key {
        id: UID,
        virtual_sui_amt: u64,
        target_supply_threshold: u64,
        migration_fee: u64,
        listing_fee: u64,
        swap_fee: u64,
        fee: Balance<SUI>
    }

    // events

    public struct BondingCurveListedEvent has copy, drop {
        object_id: ID,
        meme_type: String,
        sui_balance_val: u64,
        meme_balance_val: u64,
        virtual_sui_amt: u64,
        target_supply_threshold: u64,
        creator: address,
        ticker: ascii::String,
        name: string::String,
        description: string::String,
        url: Option<Url>,
        coin_metadata_id: ID
    }

    public struct Points has copy, drop {
        amount: u64,
        sender: address,
    }

    public struct SwapEvent has copy, drop {
        bc_id: ID,
        meme_type: String,
        is_buy: bool,
        input_amount: u64,
        output_amount: u64,
        sui_reserve_val: u64,
        meme_reserve_val: u64,
        sender: address
    }

    public struct MigrationPendingEvent has copy, drop {
        bc_id: ID,
        meme_type: String,
        sui_reserve_val: u64,
        meme_reserve_val: u64
    }

    public struct MigrationCompletedEvent has copy, drop {
        adapter_id: u64,
        bc_id: ID,
        meme_type: String,
        target_pool_id: ID,
        sui_balance_val: u64,
        meme_balance_val: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Configurator {
            id: object::new(ctx),
            virtual_sui_amt: DefaultVirtualLiquidity,
            target_supply_threshold: DefaultTargetSupplyThreshold,
            migration_fee: DefaultMigrationFee,
            listing_fee: DefaultListingFee,
            fee: balance::zero<SUI>(),
            swap_fee: DefaultSwapFee
        });
    }

    public fun list<T>(
        configurator: &mut Configurator,
        mut tc: TreasuryCap<T>, 
        coin_metadata: &CoinMetadata<T>,
        sui_coin: Coin<SUI>,
        ctx: &mut TxContext
    ): BondingCurve<T> {
        // total supply of treasury cap should be zero while listing a new meme.
        assert!(coin::total_supply<T>(&tc) == 0, ETreasuryCapSupplyNonZero);
        assert!(coin::get_decimals<T>(coin_metadata) == MemeCoinDecimals, EInvalidMemeDecimals);
        let mut sui_balance = coin::into_balance(sui_coin);
        assert!(balance::value(&sui_balance) == configurator.listing_fee, EInsufficientSuiBalance);

        // mint meme coins max supply.
        let meme_balance = coin::mint_balance<T>(&mut tc, DefaultSupply);
        
        freezer::freeze_object<TreasuryCap<T>>(tc, ctx);

        // collect listing fee.
        let listing_fee = balance::split(&mut sui_balance, configurator.listing_fee);
        balance::join(&mut configurator.fee, listing_fee);

        let bc = BondingCurve<T> {
            id: object::new(ctx),
            sui_balance: sui_balance,
            meme_balance: meme_balance,
            virtual_sui_amt: configurator.virtual_sui_amt,
            target_supply_threshold: configurator.target_supply_threshold,
            is_active: true,
            fee: balance::zero<SUI>(),
            swap_fee: configurator.swap_fee,
            creator: tx_context::sender(ctx)
        };
        let (ticker, name, description, url) = get_coin_metadata_info(coin_metadata);

        emit_bonding_curve_event(&bc, ticker, name, description, url, object::id(coin_metadata));
        bc
    }

    #[allow(lint(share_owned))]
    public fun transfer<T>(self: BondingCurve<T>) {
        transfer::share_object(self);
    }

    public fun buy<T>(
        self: &mut BondingCurve<T>, 
        sui_coin: Coin<SUI>,
        min_recieve: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(self.is_active, EPoolNotActiveForTrading);
        let sender = tx_context::sender(ctx);
        let mut sui_balance = coin::into_balance(sui_coin);

        take_fee(self, &mut sui_balance, sender);

        let (reserve_sui, reserve_meme) = get_reserves(self);
        let amount = balance::value<SUI>(&sui_balance);

        let output_amount = get_output_amount(
            amount,
            reserve_sui + self.virtual_sui_amt, 
            reserve_meme
        );
        
        assert!(output_amount >= min_recieve, ESwapOutLessthanExpected);
        
        balance::join(&mut self.sui_balance, sui_balance);

        let (reserve_base_post, reserve_meme_post) = get_reserves(self);
        assert!(reserve_base_post > 0 && reserve_meme_post > 0, EInvalidPoolStatePostSwap);

        // stop trading once threshold is reached
        if(reserve_meme_post <= self.target_supply_threshold){
            self.is_active = false;
            emit_migration_pending_event(
                object::id(self),
                type_name::into_string(type_name::get<T>()),
                reserve_base_post,
                reserve_meme_post
            );
        };
        emit_swap_event(
            object::id(self),
            type_name::into_string(type_name::get<T>()),
            true, // isbuy
            amount, // input_amount
            output_amount, // output_amount
            reserve_base_post,
            reserve_meme_post,
            sender
        );

        coin::take(&mut self.meme_balance, output_amount, ctx)
    }

    public fun sell<T>(
        self: &mut BondingCurve<T>, 
        meme_coin: Coin<T>,
        min_recieve: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(self.is_active, EPoolNotActiveForTrading);
        let sender = tx_context::sender(ctx);
        let meme_balance = coin::into_balance(meme_coin);
        let (reserve_sui, reserve_meme) = get_reserves<T>(self);
        let amount = balance::value<T>(&meme_balance);

        let output_amount = get_output_amount(
            amount, 
            reserve_meme, 
            reserve_sui + self.virtual_sui_amt
        );
        assert!(output_amount >= min_recieve, ESwapOutLessthanExpected);

        balance::join(&mut self.meme_balance, meme_balance);
        let mut output_balance = balance::split(&mut self.sui_balance, output_amount);
        take_fee(self, &mut output_balance, sender);

        let (reserve_base_post, reserve_meme_post) = get_reserves(self);
        assert!(reserve_base_post > 0 && reserve_meme_post > 0, EInvalidPoolStatePostSwap);

        emit_swap_event(
            object::id(self),
            type_name::into_string(type_name::get<T>()),
            false, // isbuy
            amount, // input_amount
            balance::value<SUI>(&output_balance), // output_amount
            reserve_base_post,
            reserve_meme_post,
            tx_context::sender(ctx)
        );

        coin::from_balance(output_balance, ctx)
    }

    public fun make_safu<T>(
        self: &mut BondingCurve<T>, 
        configurator: &mut Configurator,
        target: u64,
        ctx: &mut TxContext
    ): SafuReceipt<T> {
        assert!(!self.is_active, EPoolNotMigratable);

        // [1] take migration fee if applicable.
        if(configurator.migration_fee > 0) {
            let migration_fee = balance::split(&mut self.sui_balance, configurator.migration_fee);
            balance::join<SUI>(&mut configurator.fee, migration_fee);
        };

        // [2] extract swap fee to configurator
        transfer_fee_to_configurator(self, configurator, ctx);

        let (reserve_sui, reserve_meme) = get_reserves<T>(self);

        // [3] mint hot potato to transfer funds to target dex for listing.
        let receipt = safu_receipt::mint<T>(
            target,
            balance::split(&mut self.sui_balance, reserve_sui),
            balance::split(&mut self.meme_balance, reserve_meme),
            object::id(self)
        );

        receipt
    }

    public fun verify_if_safu<T>(receipt: SafuReceipt<T>)  {
        // burn hot potato post listing.
        let (
            bc_id, 
            target, 
            sui_balance_val, 
            meme_balance_val, 
            target_pool_id
        ) = safu_receipt::burn<T>(receipt);

        // verify if target dex adapter filled the required values.
        assert!(sui_balance_val > 0 && meme_balance_val > 0, 0);
        assert!(target_pool_id != object::id_from_address(@0x0), 0);
        emit_migration_completed_event(
            target, // adapter_id
            bc_id,
            type_name::into_string(type_name::get<T>()),
            target_pool_id,
            sui_balance_val,
            meme_balance_val
        );
    }

    public fun transfer_fee_to_configurator<T>(
        self: &mut BondingCurve<T>, 
        configurator: &mut Configurator, 
        _ctx: &mut TxContext
    ) {
        balance::join<SUI>(&mut configurator.fee, extract_all_fee(self));
    }

    // admin only operations

    public fun update_migration_fee(_: &AdminCap, configurator: &mut Configurator, val: u64) {
        configurator.migration_fee = val;
    }

    public fun update_listing_fee(_: &AdminCap, configurator: &mut Configurator, val: u64) {
        configurator.listing_fee = val;
    }

    public fun update_virtual_sui_liq(_: &AdminCap, configurator: &mut Configurator, val: u64) {
        configurator.virtual_sui_amt = val;
    }

    public fun update_target_supply_threshold(_: &AdminCap, configurator: &mut Configurator, val: u64) {
        configurator.target_supply_threshold = val;
    }

    public fun withdraw_fee(
        _: &AdminCap, 
        admin_access: &AdminAccess, 
        configurator: &mut Configurator, 
        val: u64, 
        ctx: &mut TxContext
    ) {
        let val_by_2 = val / 2;
        let sui_balance_1 = balance::split<SUI>(&mut configurator.fee, val_by_2);
        let sui_balance_2 = balance::split<SUI>(&mut configurator.fee, val_by_2);

        let coin_1 = coin::from_balance<SUI>(sui_balance_1, ctx);
        let coin_2 = coin::from_balance<SUI>(sui_balance_2, ctx);

        let (admin_1, admin_2) = admin::get_addresses(admin_access);

        transfer::public_transfer<Coin<SUI>>(coin_1, admin_1);
        transfer::public_transfer<Coin<SUI>>(coin_2, admin_2);
    }
    
    // getters

    public fun get_info<T>(self: &BondingCurve<T>): (u64, u64, u64, u64, bool) {
        (
            balance::value<SUI>(&self.sui_balance),
            balance::value<T>(&self.meme_balance),
            self.virtual_sui_amt,
            self.target_supply_threshold,
            self.is_active
        )
    }

    /// Get output price for uncorrelated curve x*y = k
    fun get_output_amount(
        input_amount: u64, 
        input_reserve: u64, 
        output_reserve: u64
    ): u64 {
        // up casts
        let (
            input_amount,
            input_reserve,
            output_reserve
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128)
        );

        let numerator = input_amount * output_reserve;
        let denominator = input_reserve + input_amount;

        (numerator / denominator as u64)
    }

    fun get_reserves<T>(self: &BondingCurve<T>): (u64, u64) {
        (balance::value(&self.sui_balance), balance::value(&self.meme_balance))
    }

    fun take_fee<T>(self: &mut BondingCurve<T>, sui_balance: &mut Balance<SUI>, sender: address) {
        let amount = ((((self.swap_fee as u128) * (balance::value<SUI>(sui_balance) as u128)) / FeeScaling) as u64);
        event::emit(Points {
            amount,
            sender
        });
        // store fee in bonding curve itself.
        balance::join<SUI>(&mut self.sui_balance, balance::split(sui_balance, amount));
    }

    fun extract_all_fee<T>(self: &mut BondingCurve<T>): Balance<SUI> {
        let val = balance::value<SUI>(&self.fee);
        balance::split(&mut self.fee, val)
    }

    fun get_coin_metadata_info<T>(coin_metadata: &CoinMetadata<T>): (ascii::String, string::String, string::String, Option<Url>) {
        let ticker = coin::get_symbol<T>(coin_metadata);
        let name = coin::get_name<T>(coin_metadata);
        let description = coin::get_description<T>(coin_metadata);
        let url = coin::get_icon_url<T>(coin_metadata);

        (ticker, name, description, url)
    }

    public fun emit_bonding_curve_event<T>(
        self: &BondingCurve<T>, 
        ticker: ascii::String, 
        name: string::String,
        description: string::String,
        url: Option<Url>,
        coin_metadata_id: ID
    ) {
        let event = BondingCurveListedEvent {
            object_id: object::id(self),
            meme_type: type_name::into_string(type_name::get<T>()),
            sui_balance_val: balance::value<SUI>(&self.sui_balance),
            meme_balance_val: balance::value<T>(&self.meme_balance),
            virtual_sui_amt: self.virtual_sui_amt,
            target_supply_threshold: self.target_supply_threshold,
            creator: self.creator,
            ticker: ticker,
            name: name,
            description: description,
            url: url,
            coin_metadata_id: coin_metadata_id
        };

        event::emit<BondingCurveListedEvent>(event);
    }

    public fun emit_swap_event(
        bc_id: ID,
        meme_type: String,
        is_buy: bool,
        input_amount: u64,
        output_amount: u64,
        sui_reserve_val: u64,
        meme_reserve_val: u64,
        sender: address
    ) {
         event::emit(SwapEvent {
            bc_id,
            meme_type,
            is_buy,
            input_amount,
            output_amount,
            sui_reserve_val,
            meme_reserve_val,
            sender
        });
    }

    public fun emit_migration_pending_event(
        bc_id: ID,
        meme_type: String,
        sui_reserve_val: u64,
        meme_reserve_val: u64
    ) {
        event::emit(MigrationPendingEvent {
            bc_id,
            meme_type,
            sui_reserve_val,
            meme_reserve_val
        });
    }

    public fun emit_migration_completed_event(
        adapter_id: u64,
        bc_id: ID,
        meme_type: String,
        target_pool_id: ID,
        sui_balance_val: u64,
        meme_balance_val: u64
    ) {
        event::emit<MigrationCompletedEvent>(MigrationCompletedEvent {
            adapter_id,
            bc_id,
            meme_type,
            target_pool_id,
            sui_balance_val,
            meme_balance_val
        })
    }
}