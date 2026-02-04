/// Convert 128-byte array to array of 16 u64s
pub(crate) fn msg_u8_to_u64(msg: [u8; 128]) -> [u64; 16] {
    let mut msg64: [u64; 16] = [0; 16];

    for i in 0..16 {
        let mut msg_field: Field = 0;
        for j in 0..8 {
            msg_field = msg_field * 256 + msg[128 - 8 * (i + 1) + j] as Field;
        }

        msg64[15 - i] = to_u64(msg_field);
    }

    msg64
}

/// Convert an input `Field` element into a `u64`
///
/// # Notes
/// This fn requires that `input` is < 2^{64} or unsatisfiable constraints will be created.
/// This fn is cheaper than `as u64` because the overflow case is not handled
pub(crate) fn to_u64(input: Field) -> u64 {
    // Safety: plucking u64 out of an unconstrained fn and then validating its correctness
    // is cheaper than `as u64`, because `as u64` handles overflow cases, which we can simply forbid with a range check
    let converted = unsafe { __to_u64(input) };
    assert_eq(converted as Field, input);
    input.assert_max_bit_size::<64>();
    converted
}

/// Given an input `Field` element known to be less than 2^72, return the component of `input` that is less than 2^64
pub(crate) fn reduce_modulo_64(input: Field) -> Field {
    // Safety: obtain result and then validate result is correct
    let (modulus, remainder) = unsafe { __reduce_modulo_64(input) };

    // 1.25 gates
    modulus.assert_max_bit_size::<8>();
    // 64 bits = 14/// 4 + 8 = 3.25
    remainder.assert_max_bit_size::<64>();
    assert_eq(modulus * 0x10000000000000000 + remainder, input);

    remainder
}

// used by `to_u64`
unconstrained fn __to_u64(input: Field) -> u64 {
    input as u64
}

// use by `reduce_modulo_64`
unconstrained fn __reduce_modulo_64(input: Field) -> (Field, Field) {
    let input128 = input as u128;

    let remainder = input128 & 0xffffffffffffffff;
    let modulus = input128 >> 64;

    (modulus as Field, remainder as Field)
}
