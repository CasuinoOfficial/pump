module bonding_curve::admin {

    const EAdminAccessNotInitialised: u64 = 0;

    public struct AdminAccess has key {
        id: UID,
        admin_1: address,
        admin_2: address
    }

    public struct AdminCap has key, store {
        id: UID,
        admin_id: u8
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(AdminAccess { 
            id: object::new(ctx),
            admin_1: @0x0,
            admin_2: @0x0
        });

        // create 2 admin caps.
        let admin_cap_1 = AdminCap {
            id: object::new(ctx),
            admin_id: 1
        };
        let admin_cap_2 = AdminCap {
            id: object::new(ctx),
            admin_id: 2
        };

        transfer::transfer(admin_cap_1, tx_context::sender(ctx));
        transfer::transfer(admin_cap_2, tx_context::sender(ctx));
    }

    public fun update_address(self: &mut AdminAccess, cap: &AdminCap, val: address, _ctx: &mut TxContext){
        if(cap.admin_id == 1) {
            // update admin 1
            self.admin_1 = val;
        } else if(cap.admin_id == 2) {
            // update admin 2
            self.admin_2 = val;
        }
    }

    public fun get_addresses(self: &AdminAccess): (address, address) {
        assert_initialised(self);
        (self.admin_1, self.admin_2)
    }

    public fun assert_initialised(self: &AdminAccess) {
        assert!(self.admin_1 != @0x0 && self.admin_2 != @0x0, EAdminAccessNotInitialised);
    }
}