module kdx_spot::default_config {
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use kdx_spot::constants;
    use kdx_spot::error;
    use kdx_spot::safe_math;
    use kdx_spot::admin_access::{AdminAccess};

    friend kdx_spot::app;

    struct DefaultConfig has key {
        id: UID,
        // uc curve fields
        uc_total_min: u64,
        uc_total_max: u64,
        uc_threshold: u64,
        uc_below_threshold_percent: u64,
        uc_above_threshold_percent: u64,

        // stable curve fields
        stable_total_min: u64,
        stable_total_max: u64,
        stable_flat_percent: u64
    }

    fun init(ctx: &mut TxContext) {
        let default_config = DefaultConfig {
            id: object::new(ctx),
            uc_total_min: 3_000, // 0.3%
            uc_total_max: 1_00000, // 10%
            uc_threshold: 5_0000, // 5%
            uc_below_threshold_percent: 33_0000, // 33%
            uc_above_threshold_percent: 10_0000, // 10%

            // stable curve fields
            stable_total_min: 200, // 0.02%
            stable_total_max: 1_000, // 0.1%
            stable_flat_percent: 33_0000 // 33%
        };

        transfer::share_object(default_config);
    }

    public(friend) fun set_stable_fees(
        self: &mut DefaultConfig, 
        stable_total_min: u64,
        stable_total_max: u64,
        stable_flat_percent: u64,
        _ : &AdminAccess
    ) {
        assert!(stable_total_min <= (constants::fee_scalling() as u64), error::feeInvalid());
        assert!(stable_total_max <= (constants::fee_scalling() as u64), error::feeInvalid());
        assert!(stable_flat_percent <= (constants::fee_percent_scalling() as u64), error::feeInvalid());
        
        self.stable_total_min = stable_total_min;
        self.stable_total_max = stable_total_max;
        self.stable_flat_percent = stable_flat_percent;
    }

    public(friend) fun set_uc_fees(
        self: &mut DefaultConfig, 
        uc_total_min: u64,
        uc_total_max: u64,
        uc_threshold: u64,
        uc_below_threshold_percent: u64,
        uc_above_threshold_percent: u64,
        _ : &AdminAccess
    ) {
        assert!(uc_total_min <= (constants::fee_scalling() as u64), error::feeInvalid());
        assert!(uc_total_max <= (constants::fee_scalling() as u64), error::feeInvalid());
        assert!(uc_threshold <= (constants::fee_scalling() as u64), error::feeInvalid());
        assert!(uc_below_threshold_percent <= (constants::fee_percent_scalling() as u64), error::feeInvalid());
        assert!(uc_above_threshold_percent <= (constants::fee_percent_scalling() as u64), error::feeInvalid());

        self.uc_total_min = uc_total_min;
        self.uc_total_max = uc_total_max;
        self.uc_threshold = uc_threshold;
        self.uc_below_threshold_percent = uc_below_threshold_percent;
        self.uc_above_threshold_percent = uc_above_threshold_percent;
    }

    // Get lp_fee_percent, protocol_fee_percent from default_config
    public fun fee(self: &DefaultConfig, is_stable: bool, total_fee: u64): (u64, u64) {
        let (lp_fee, protocol_fee) = if(is_stable) {
            // todo: add error code
            assert!(total_fee <= self.stable_total_max && total_fee >= self.stable_total_min, 0);
            let protocol_fee = safe_math::safe_mul_div_u64(self.stable_flat_percent, total_fee, constants::fee_percent_scalling());
            let lp_fee = total_fee - protocol_fee;
            (lp_fee, protocol_fee)
        } else {
            // todo: add error code
            assert!(total_fee <= self.uc_total_max && total_fee >= self.uc_total_min, 0);
            let fee_percent = if(total_fee > self.uc_threshold) self.uc_above_threshold_percent else self.uc_below_threshold_percent;
            let protocol_fee = safe_math::safe_mul_div_u64(fee_percent, total_fee, constants::fee_percent_scalling());
            let lp_fee = total_fee - protocol_fee;
            (lp_fee, protocol_fee)
        };

        (lp_fee, protocol_fee)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}