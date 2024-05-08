module kdx_spot::utils {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::option::{Self, Option};
    use kdx_spot::constants;

    /// We take 10^8 as we expect most of the coins to have 6-8 decimals.
    const ONE_E_8: u128 = 100000000;

    /// Get output price for uncorrelated curve x*y = k
    public fun get_input_price_uncorrelated(
        input_amount: u64, 
        input_reserve: u64, 
        output_reserve: u64, 
        fee_percent: u64): u64 {
        // up casts
        let (
            input_amount,
            input_reserve,
            output_reserve,
            fee_percent
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128),
            (fee_percent as u128)
        );

        let input_amount_with_fee = input_amount * (constants::fee_scalling() - fee_percent);
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * constants::fee_scalling()) + input_amount_with_fee;

        (numerator / denominator as u64)
    }

    public fun get_input_price_stable(
        input_amount: u64, 
        input_reserve: u64, 
        output_reserve: u64, 
        fee_percent: u64,
        input_scale: u64,
        output_scale: u64
    ): u64 {
        let u2561e8 = (ONE_E_8 as u256);

        let xy = lp_value((input_reserve as u128), input_scale, (output_reserve as u128), output_scale);

        let reserve_in_u256 = ((input_reserve as u256) * u2561e8) / (input_scale as u256);
        let reserve_out_u256 = ((output_reserve as u256) * u2561e8) / (output_scale as u256);
        let amount_in = ((input_amount as u256) * u2561e8) / (input_scale as u256);
        let amount_in_with_fees_scaling = ((amount_in as u256) * (((constants::fee_scalling() as u128) - (fee_percent as u128)) as u256)) / (constants::fee_scalling() as u256);
        let total_reserve = amount_in_with_fees_scaling + reserve_in_u256;
        let y = reserve_out_u256 - get_y(total_reserve, xy, reserve_out_u256);

        let r = (y * (output_scale as u256)) / u2561e8;

        (r as u64)
    }

    /// Get LP value for stable curve: x^3*y + x*y^3
    /// * `x_coin` - reserves of coin X.
    /// * `x_scale` - 10 pow X coin decimals amount.
    /// * `y_coin` - reserves of coin Y.
    /// * `y_scale` - 10 pow Y coin decimals amount.
    public fun lp_value(x_coin: u128, x_scale: u64, y_coin: u128, y_scale: u64): u256 {
        let x_u256 = (x_coin as u256);
        let y_u256 = (y_coin as u256);
        let u2561e8 = (ONE_E_8 as u256);

        let x_scale_u256 = (x_scale as u256);
        let y_scale_u256 = (y_scale as u256);

        let _x = (x_u256 * u2561e8) / x_scale_u256;

        let _y = (y_u256 * u2561e8) / y_scale_u256;

        let _a = _x * _y;

        // ((_x * _x) / 1e18 + (_y * _y) / 1e18)
        let _b = _x * _x + _y * _y;

       _a * _b
    }

    public fun extract_transfer_to_sender<T: key + store>(t: Option<T>, ctx: &mut TxContext) {
        if(option::is_some<T>(&t)) {
            transfer::public_transfer<T>(option::destroy_some<T>(t), tx_context::sender(ctx));
        } else {
            option::destroy_none(t)
        }
    }

    /// get value of reserve_y - output_y
    /// * `x0` = reserve_x + input_x = total x reserve after adding input 
    /// * `xy` - original value of x^3*y + x*y^3
    /// * `y` - reserve_y - initial guess is reserve_y
    /// calculate 255 iterations of Newton's method for x^3*y + x*y^3
    fun get_y(x0: u256, xy: u256, y: u256): u256 {
        let i = 0;

        let one_u256: u256 = 1;

        while (i < 255) {
            let k = f(x0, y);

            let _dy: u256 = 0;
            if(xy > k) {
                _dy = (xy - k) / d(x0, y) + one_u256; // Round up
                y = y + _dy;
            } else {
                _dy = (k - xy) / d(x0, y) + one_u256;
                y = y - _dy;
            };
            if (_dy <= one_u256) {
                return y
            };

            i = i + 1;
        };

        y
    }

    /// Implements x0*y^3 + x0^3*y = x0*(y*y/1e18*y/1e18)/1e18+(x0*x0/1e18*x0/1e18)*y/1e18
    fun f(x0_u256: u256, y_u256: u256): u256 {
        // x0*(y*y/1e18*y/1e18)/1e18
        let yy = y_u256 * y_u256;
        let yyy = yy * y_u256;

        let a = x0_u256 * yyy;

        //(x0*x0/1e18*x0/1e18)*y/1e18
        let xx = x0_u256 * x0_u256;
        let xxx = xx * x0_u256;
        let b = xxx *y_u256;

        // a + b
        a + b
    }

    /// Implements 3 * x0 * y^2 + x0^3 = 3 * x0 * (y * y / 1e8) / 1e8 + (x0 * x0 / 1e8 * x0) / 1e8
    fun d(x0_u256: u256, y_u256: u256): u256 {
        let three_u256: u256 = 3;

        // 3 * x0 * (y * y / 1e8) / 1e8
        let x3 = three_u256 * x0_u256;
        let yy = y_u256 * y_u256;
        let xyy3 = x3 * yy;
        let xx = x0_u256 * x0_u256;

        // x0 * x0 / 1e8 * x0 / 1e8
        let xxx = xx * x0_u256;

        xyy3 + xxx
    }
}