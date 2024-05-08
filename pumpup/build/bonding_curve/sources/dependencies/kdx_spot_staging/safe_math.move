module kdx_spot::safe_math {
    public fun safe_mul_div_u64(x: u64, y: u64, z: u64): u64 {
        ((x as u128) * (y as u128) / (z as u128) as u64)
    }
}