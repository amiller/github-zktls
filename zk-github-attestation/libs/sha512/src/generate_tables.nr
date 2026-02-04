use crate::tables::{
    BASE4_ENCODE_1BIT_TABLE, BASE4_ENCODE_2BIT_TABLE, BASE4_ENCODE_3BIT_TABLE,
    BASE4_ENCODE_4BIT_TABLE, BASE4_ENCODE_5BIT_TABLE, BASE4_ENCODE_6BIT_TABLE,
    BASE4_ENCODE_7BIT_TABLE, BASE4_ENCODE_8BIT_TABLE, BASE4_ENCODE_9BIT_TABLE,
    BASE4_MAJORITY_DECODE_5BIT_TABLE, BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE,
    BASE4_XOR_DECODE_5BIT_TABLE,
};
unconstrained fn compute_base4_conversion_table<let TABLE_ENTRIES: u32>() -> [Field; TABLE_ENTRIES] {
    let mut table: [Field; TABLE_ENTRIES] = [0; TABLE_ENTRIES];

    for i in 0..TABLE_ENTRIES {
        if (i & 1 == 1) {
            table[i] += 1;
        }
        if ((i >> 1) & 1 == 1) {
            table[i] += 4;
        }
        if ((i >> 2) & 1 == 1) {
            table[i] += 16;
        }
        if ((i >> 3) & 1 == 1) {
            table[i] += 64;
        }
        if ((i >> 4) & 1 == 1) {
            table[i] += 256;
        }
        if ((i >> 5) & 1 == 1) {
            table[i] += 1024;
        }
        if ((i >> 6) & 1 == 1) {
            table[i] += 4096;
        }
        if ((i >> 7) & 1 == 1) {
            table[i] += 16384;
        }
        if ((i >> 8) & 1 == 1) {
            table[i] += 65536;
        }
    }
    table
}

unconstrained fn __compute_xor_decoding_table() {
    let mut result: [Field; 4 * 4 * 4 * 4 * 4] = [0; 4 * 4 * 4 * 4 * 4];
    for bit2 in 0..4 {
        let bit2out = ((bit2 & 1) == 1) as u32;
        for bit3 in 0..4 {
            let bit3out = ((bit3 & 1) == 1) as u32;
            for bit4 in 0..4 {
                let bit4out = ((bit4 & 1) == 1) as u32;
                for bit5 in 0..4 {
                    let bit5out = ((bit5 & 1) == 1) as u32;
                    for bit6 in 0..4 {
                        let bit6out = ((bit6 & 1) == 1) as u32;

                        let mut index = bit2;
                        index *= 4;
                        index += bit3;
                        index *= 4;
                        index += bit4;
                        index *= 4;
                        index += bit5;
                        index *= 4;
                        index += bit6;

                        let mut value = bit2out;
                        value *= 2;
                        value += bit3out;
                        value *= 2;
                        value += bit4out;
                        value *= 2;
                        value += bit5out;
                        value *= 2;
                        value += bit6out;

                        result[index] = value as Field;
                    }
                }
            }
            // }
        }
    }
    assert_eq(result, BASE4_XOR_DECODE_5BIT_TABLE);
    // UNCOMMENT IF THIS TABLE NEEDS TO BE REGENERATED
    // println(
    //     f"pub global BASE4_XOR_DECODE_5BIT_TABLE: [Field; 1024] = {result}",
    // );
}

unconstrained fn __compute_partial_choose_decoding_table() {
    // num bits = 6
    // !e & g
    // 2e + g -> 1 maps to 0
    let mut result: [Field; 4 * 4 * 4 * 4 * 4] = [0; 4 * 4 * 4 * 4 * 4];
    // for bit1 in 0..4 {
    //     let bit1out = ((bit1 & 1) == 1) as u32;
    for bit2 in 0..4 {
        let bit2out = ((bit2 & 3) == 1) as u32;
        for bit3 in 0..4 {
            let bit3out = ((bit3 & 3) == 1) as u32;
            for bit4 in 0..4 {
                let bit4out = ((bit4 & 3) == 1) as u32;
                for bit5 in 0..4 {
                    let bit5out = ((bit5 & 3) == 1) as u32;
                    for bit6 in 0..4 {
                        let bit6out = ((bit6 & 3) == 1) as u32;

                        let mut index = bit2;
                        index *= 4;
                        index += bit3;
                        index *= 4;
                        index += bit4;
                        index *= 4;
                        index += bit5;
                        index *= 4;
                        index += bit6;

                        let mut value = bit2out;
                        value *= 2;
                        value += bit3out;
                        value *= 2;
                        value += bit4out;
                        value *= 2;
                        value += bit5out;
                        value *= 2;
                        value += bit6out;

                        result[index] = value as Field;
                    }
                }
            }
        }
    }
    assert_eq(result, BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE);
    // UNCOMMENT IF THIS TABLE NEEDS TO BE REGENERATED
    // println(
    //     f"pub global BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE: [Field; 1024] = {result}",
    // );
}

unconstrained fn __compute_majority_decoding_table() {
    // num bits = 6

    let mut result: [Field; 4 * 4 * 4 * 4 * 4] = [0; 4 * 4 * 4 * 4 * 4];
    // for bit1 in 0..4 {
    //     let bit1out = ((bit1 & 1) == 1) as u32;
    for bit2 in 0..4 {
        let bit2out = ((bit2 & 3) > 1) as u32;
        for bit3 in 0..4 {
            let bit3out = ((bit3 & 3) > 1) as u32;
            for bit4 in 0..4 {
                let bit4out = ((bit4 & 3) > 1) as u32;
                for bit5 in 0..4 {
                    let bit5out = ((bit5 & 3) > 1) as u32;
                    for bit6 in 0..4 {
                        let bit6out = ((bit6 & 3) > 1) as u32;

                        // let mut index = bit1;
                        // index*= 7;
                        let mut index = bit2;
                        index *= 4;
                        index += bit3;
                        index *= 4;
                        index += bit4;
                        index *= 4;
                        index += bit5;
                        index *= 4;
                        index += bit6;

                        // let mut value = bit1out;
                        // value*= 2;
                        let mut value = bit2out;
                        value *= 2;
                        value += bit3out;
                        value *= 2;
                        value += bit4out;
                        value *= 2;
                        value += bit5out;
                        value *= 2;
                        value += bit6out;

                        result[index] = value as Field;
                    }
                }
            }
            // }
        }
    }
    assert_eq(result, BASE4_MAJORITY_DECODE_5BIT_TABLE);
    // UNCOMMENT IF THIS TABLE NEEDS TO BE REGENERATED
    // println(
    //     f"pub global BASE4_MAJORITY_DECODE_5BIT_TABLE: [Field; 1024] = {result}",
    // );
}

#[test]
fn print_xor_decoding_table() {
    //Safety:
    unsafe { __compute_xor_decoding_table() };
}

#[test]
fn print_partial_choose_decoding_table() {
    //Safety:
    unsafe { __compute_partial_choose_decoding_table() };
}

#[test]
fn print_majority_decoding_table() {
    //Safety:
    unsafe { __compute_majority_decoding_table() };
}

#[test]
fn print_encoding_table() {
    // Safety: no need to constrain this we're just computing+printing lookup table values
    unsafe {
        let t0 = compute_base4_conversion_table::<2>();
        let t1 = compute_base4_conversion_table::<4>();
        let t2 = compute_base4_conversion_table::<8>();
        let t3 = compute_base4_conversion_table::<16>();
        let t4 = compute_base4_conversion_table::<32>();
        let t5 = compute_base4_conversion_table::<64>();
        let t6 = compute_base4_conversion_table::<128>();
        let t7 = compute_base4_conversion_table::<256>();
        let t8 = compute_base4_conversion_table::<512>();

        // UNCOMMENT IF THESE TABLES NEED TO BE REGENERATED
        // println(f"pub global BASE4_ENCODE_1BIT_TABLE: [Field; 2] = {t0};");
        // println(f"pub global BASE4_ENCODE_2BIT_TABLE: [Field; 4] = {t1};");
        // println(f"pub global BASE4_ENCODE_3BIT_TABLE: [Field; 8] = {t2};");
        // println(f"pub global BASE4_ENCODE_4BIT_TABLE: [Field; 16] = {t3};");
        // println(f"pub global BASE4_ENCODE_5BIT_TABLE: [Field; 32] = {t4};");
        // println(f"pub global BASE4_ENCODE_6BIT_TABLE: [Field; 64] = {t5};");
        // println(f"pub global BASE4_ENCODE_7BIT_TABLE: [Field; 128] = {t6};");
        // println(f"pub global BASE4_ENCODE_8BIT_TABLE: [Field; 256] = {t7};");
        // println(f"pub global BASE4_ENCODE_9BIT_TABLE: [Field; 512] = {t8};");
        assert_eq(t0, BASE4_ENCODE_1BIT_TABLE);
        assert_eq(t1, BASE4_ENCODE_2BIT_TABLE);
        assert_eq(t2, BASE4_ENCODE_3BIT_TABLE);
        assert_eq(t3, BASE4_ENCODE_4BIT_TABLE);
        assert_eq(t4, BASE4_ENCODE_5BIT_TABLE);
        assert_eq(t5, BASE4_ENCODE_6BIT_TABLE);
        assert_eq(t6, BASE4_ENCODE_7BIT_TABLE);
        assert_eq(t7, BASE4_ENCODE_8BIT_TABLE);
        assert_eq(t8, BASE4_ENCODE_9BIT_TABLE);
    }
}
