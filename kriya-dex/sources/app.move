module kdx_spot::app {
    use kdx_spot::pool::{Self, Pool, PoolCap};
    use kdx_spot::error;
    use kdx_spot::admin_access::{Self, AdminAccess};
    use kdx_spot::default_config::{Self, DefaultConfig};
    use sui::table::{Self, Table};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::tx_context::{Self, TxContext};

    struct AdminCap has key {
        id: UID,
        admin: address,
        whitelisted_addresses: Table<address, bool>
    }

    fun init(ctx: &mut TxContext) {
        let whitelisted_addresses = table::new<address, bool>(ctx);
        table::add(&mut whitelisted_addresses, tx_context::sender(ctx), true);
        
        transfer::share_object(AdminCap{
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            whitelisted_addresses: whitelisted_addresses
        });
    }

    public entry fun update_default_stable_fee(
        config: &mut DefaultConfig, 
        admin_cap: &AdminCap, 
        stable_total_min: u64,
        stable_total_max: u64,
        stable_flat_percent: u64,
        _ctx : &mut TxContext
    ){
        let access_token = authenticate(admin_cap, _ctx);

        default_config::set_stable_fees(config, stable_total_min, stable_total_max, stable_flat_percent, &access_token);
        admin_access::burn(access_token);
    }

    public entry fun update_default_uc_fee(
        config: &mut DefaultConfig, 
        admin_cap: &AdminCap, 
        uc_total_min: u64,
        uc_total_max: u64,
        uc_threshold: u64,
        uc_below_threshold_percent: u64,
        uc_above_threshold_percent: u64,
        _ctx : &mut TxContext
    ){
        let access_token = authenticate(admin_cap, _ctx);

        default_config::set_uc_fees(
            config, 
            uc_total_min,
            uc_total_max,
            uc_threshold,
            uc_below_threshold_percent,
            uc_above_threshold_percent, 
            &access_token
        );
        admin_access::burn(access_token);
    }

    #[lint_allow(self_transfer)]
    public entry fun claim_fees<X, Y>(
        pool: &mut Pool<X, Y>,
        admin_cap: &AdminCap,
        amount_x: u64,
        amount_y: u64,
        _ctx: &mut TxContext
    ) {
        let access_token = authenticate(admin_cap, _ctx);
        
        let (fee_x, fee_y) = pool::claim_fee<X, Y>(pool, amount_x, amount_y, &access_token, _ctx);
        transfer::public_transfer<Coin<X>>(fee_x, tx_context::sender(_ctx));
        transfer::public_transfer<Coin<Y>>(fee_y, tx_context::sender(_ctx));

        admin_access::burn(access_token);
    }

    public entry fun add_whitelist(
        admin_cap: &mut AdminCap,
        to_whitelist: address,
        _ctx: &mut TxContext
    ) {
        authenticate_admin(admin_cap, _ctx);

        assert!(!table::contains<address, bool>(&admin_cap.whitelisted_addresses, to_whitelist), error::alreadyWhitelisted());
        table::add(&mut admin_cap.whitelisted_addresses, to_whitelist, true);
        // xxx
        // emit_whitelist_event(to_whitelist, true);
    }

    public entry fun remove_whitelisted_address_config(
        admin_cap: &mut AdminCap,
        to_remove_whitelist: address,
        _ctx: &mut TxContext
    ) {
        authenticate_admin(admin_cap, _ctx);

        assert!(admin_cap.admin != to_remove_whitelist, error::removeAdminNotAllowed());
        assert!(table::contains<address, bool>(&admin_cap.whitelisted_addresses, to_remove_whitelist), error::alreadyWhitelisted());
        table::remove(&mut admin_cap.whitelisted_addresses, to_remove_whitelist);
        
        // emit_whitelist_event(to_remove_whitelist, false);
    }

    public entry fun update_pool_fee<X, Y>(
        pool_cap: &PoolCap,
        pool: &mut Pool<X, Y>,
        total_fee: u64,
        config: &DefaultConfig,
        _ctx: &mut TxContext
    ) {
        let access_token = authenticate_pool(pool_cap, pool);

        let (lp_fee, protocol_fee) = default_config::fee(config, pool::is_stable(pool), total_fee);
        pool::set_fee(pool, lp_fee, protocol_fee, &access_token);

        admin_access::burn(access_token);

        // emit_whitelist_event(to_remove_whitelist, false);
    }

    fun authenticate(admin_cap: &AdminCap, _ctx: &mut TxContext): AdminAccess {
        assert!(table::contains<address, bool>(&admin_cap.whitelisted_addresses, tx_context::sender(_ctx)), error::unauthorized());
        admin_access::mint()
    }

    fun authenticate_pool<X, Y>(pool_cap: &PoolCap, pool: &Pool<X, Y>): AdminAccess {
        assert!(pool::get_pool_id(pool_cap) == object::id(pool), error::unauthorized());
        admin_access::mint()
    }

    fun authenticate_admin(admin_cap: &AdminCap, _ctx: &mut TxContext) {
        assert!(admin_cap.admin == tx_context::sender(_ctx), error::unauthorized());
    }
    
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let whitelisted_addresses = table::new<address, bool>(ctx);
        table::add(&mut whitelisted_addresses, tx_context::sender(ctx), true);
        
        transfer::share_object(AdminCap{
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            whitelisted_addresses: whitelisted_addresses
        });
    }
}