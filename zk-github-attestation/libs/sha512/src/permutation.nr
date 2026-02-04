use crate::encoding::{
    decode_choose, decode_majority, decode_xor, encode_a, encode_e, encode_message_extension,
    EncodedChoose, EncodedMajority, EncodedWitness,
};
use crate::formatting::reduce_modulo_64;
use crate::tables::SHA512_ROUND_CONSTANTS;

/// Represent the SHA384/512 permutation state as base4-encoded variables
pub(crate) struct RoundState {
    pub(crate) a: EncodedMajority,
    pub(crate) b: EncodedMajority,
    pub(crate) c: EncodedMajority,
    pub(crate) d: EncodedMajority,
    pub(crate) e: EncodedChoose,
    pub(crate) f: EncodedChoose,
    pub(crate) g: EncodedChoose,
    pub(crate) h: EncodedChoose,
}

/// Perform message extension, expanding 16 words of the message schedule into 80 words
pub(crate) fn extend_message(witness: [Field; 16]) -> [Field; 80] {
    let mut w: [EncodedWitness; 80] = [EncodedWitness::new(); 80];

    for i in 0..16 {
        w[i] = encode_message_extension(witness[i]);
    }
    for i in 16..78 {
        // s0 = (w[i-15] rightrotate 7) xor (w[i-15] rightrotate 18) xor (w[i-15] rightshift  3)
        // When we encoded `w`, w15_rotate_sum represents the base4-encoded linear sum of the above
        // all we need to do is decode back into base2
        let s0: Field = decode_xor(w[i - 15].w15_rotate_sum);

        // s1 = (w[i-2] rightrotate 17) xor (w[i-2] rightrotate 19) xor (w[i-2] rightshift 10)
        // When we encoded `w`, w2_rotate_sum represents the base4-encoded linear sum of the above
        // all we need to do is decode back into base2
        let s1 = decode_xor(w[i - 2].w2_rotate_sum);

        // evaluating the sum as Field elements and then reducing modulo 64 is more efficient than `u64` arithmetic
        let new_witness = reduce_modulo_64(w[i - 16].raw + s0 + w[i - 7].raw + s1);

        // take the output and encode into the extended base4 representation
        w[i] = encode_message_extension(new_witness);
    }

    let mut result: [Field; 80] = [0; 80];
    for i in 0..78 {
        result[i] = w[i].raw;
    }

    // For the final 2 iterations, we do not need to encode the output, as we will only access these variables in their native base2 representation
    for i in 78..80 {
        let s0: Field = decode_xor(w[i - 15].w15_rotate_sum);

        let s1 = decode_xor(w[i - 2].w2_rotate_sum);

        result[i] = reduce_modulo_64(w[i - 16].raw + s0 + w[i - 7].raw + s1);
    }
    result
}

/// Evaluate the SHA384/512 compression function
///
/// # Cost
/// Each iteration costs 243 gates
pub(crate) fn compress(state: &mut RoundState, w: [Field; 80]) {
    for i in 0..80 {
        // S0 = (a rightrotate 2) xor (a rightrotate 13) xor (a rightrotate 22)
        // When we encoded `a`, a_rotrate_sum represents the base4-encoded linear sum of the above
        // all we need to do is decode back into base2
        let S0 = decode_xor(state.a.rotate_sum);
        let majority = decode_majority(state.a.encoded, state.b.encoded, state.c.encoded);
        let temp2 = S0 + majority;

        // S1 = (e rightrotate 6) xor (e rightrotate 11) xor (e rightrotate 25)
        // When we encoded `a`, a_rotrate_sum represents the base4-encoded linear sum of the above
        // all we need to do is decode back into base2
        let S1 = decode_xor(state.e.rotate_sum);
        let choose_output = decode_choose(state.e.encoded, state.f.encoded, state.g.encoded);
        let temp1 = state.h.raw + S1 + choose_output + (SHA512_ROUND_CONSTANTS[i] as Field) + w[i];
        // temp1 is a linar sum of ~50 inputs. Without std::as_witness the addition gates required to eval are duplicated
        // for both `raw_e` and `raw_a`
        std::as_witness(temp1); // temp1 = 106 gates

        // 6.5 gates
        let raw_e = reduce_modulo_64(state.d.raw + temp1);

        // 6.5 gates
        let raw_a = reduce_modulo_64(temp1 + temp2);

        state.h = state.g;
        state.g = state.f;
        state.f = state.e;
        state.d = state.c;
        state.c = state.b;
        state.b = state.a;

        if (i < 79) {
            // encode the new `a, e` vars in the extended base4 representation
            let encoded_e = encode_e(raw_e); // 27 gates
            let encoded_a = encode_a(raw_a); // 27 gates
            state.e = encoded_e;
            state.a = encoded_a;
        } else {
            // if this is the last iteration, no need to encode `a` and `e` as we only care about the raw value
            state.a = EncodedMajority { encoded: 0, raw: raw_a, rotate_sum: 0 };
            state.e = EncodedChoose { encoded: 0, raw: raw_e, rotate_sum: 0 };
        }
    }
}

mod test {
    unconstrained fn __extend_message_native(witness: [Field; 16]) -> [u64; 80] {
        let mut w: [u64; 80] = [0; 80];
        for i in 0..16 {
            w[i] = witness[i] as u64;
        }

        for i in 16..80 {
            let w15 = w[i - 15];
            let w2 = w[i - 2];

            let ror1: u64 = (w15 >> 1) + ((w15 & 1) << (64 - 1));
            let ror8 = (w15 >> 8) + ((w15 & 255) << (64 - 8));
            let rshift7 = (w15 >> 7);
            let ror19 = (w2 >> 19) + ((w2 & 0x7ffff) << (64 - 19));
            let ror61 = (w2 >> 61) + ((w2 & 0x1fffffffffffffff) << (64 - 61));
            let rshift6 = (w2 >> 6);

            let s0 = ror1 ^ ror8 ^ rshift7;
            let s1 = ror19 ^ ror61 ^ rshift6;

            let wout =
                ((w[i - 16] as Field) + (s0 as Field) + (w[i - 7] as Field) + (s1 as Field)) as u64;
            w[i] = wout;
        }
        w
    }
    unconstrained fn __compress_native(witness: [Field; 80]) -> [Field; 8] {
        let mut expected: [Field; 8] = [0; 8];

        let mut a: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[0];
        let mut b: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[1];
        let mut c: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[2];
        let mut d: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[3];
        let mut e: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[4];
        let mut f: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[5];
        let mut g: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[6];
        let mut h: u64 = crate::tables::SHA512_INITIAL_HASH_VALUES[7];
        for i in 0..80 {
            let ror14 = (e >> 14) + ((e & 0x3fff) << (64 - 14));
            let ror18 = (e >> 18) + ((e & 0x3ffff) << (64 - 18));
            let ror41 = (e >> 41) + ((e & 0x1ffffffffff) << (64 - 41));

            let ror28 = (a >> 28) + ((a & 0x0fffffff) << (64 - 28));
            let ror34 = (a >> 34) + ((a & 0x3ffffffff) << (64 - 34));
            let ror39 = (a >> 39) + ((a & 0x7fffffffff) << (64 - 39));

            let S1 = ror14 ^ ror18 ^ ror41;
            let ch = (e & f) ^ ((!e) & g);
            let mut temp1 = h as Field + S1 as Field;
            temp1 += ch as Field;
            temp1 += crate::tables::SHA512_ROUND_CONSTANTS[i] as Field;
            temp1 += witness[i];
            let temp1 = temp1 as u64;
            let S0 = ror28 ^ ror34 ^ ror39;
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = (S0 as Field + maj as Field) as u64;

            h = g;
            g = f;
            f = e;
            e = (d as Field + temp1 as Field) as u64;
            d = c;
            c = b;
            b = a;
            a = (temp1 as Field + temp2 as Field) as u64;
        }
        expected[0] = a as Field;
        expected[1] = b as Field;
        expected[2] = c as Field;
        expected[3] = d as Field;
        expected[4] = e as Field;
        expected[5] = f as Field;
        expected[6] = g as Field;
        expected[7] = h as Field;

        expected
    }

    #[test]
    fn test_compress() {
        let mut witness: [Field; 80] = [0; 80];
        for i in 0..80 {
            witness[i] = crate::tables::SHA512_ROUND_CONSTANTS[i] as Field;
        }
        let mut state: crate::permutation::RoundState = crate::permutation::RoundState {
            a: crate::encoding::encode_a(crate::tables::SHA512_INITIAL_HASH_VALUES[0] as Field),
            b: crate::encoding::encode_a(crate::tables::SHA512_INITIAL_HASH_VALUES[1] as Field),
            c: crate::encoding::encode_a(crate::tables::SHA512_INITIAL_HASH_VALUES[2] as Field),
            d: crate::encoding::encode_a(crate::tables::SHA512_INITIAL_HASH_VALUES[3] as Field),
            e: crate::encoding::encode_e(crate::tables::SHA512_INITIAL_HASH_VALUES[4] as Field),
            f: crate::encoding::encode_e(crate::tables::SHA512_INITIAL_HASH_VALUES[5] as Field),
            g: crate::encoding::encode_e(crate::tables::SHA512_INITIAL_HASH_VALUES[6] as Field),
            h: crate::encoding::encode_e(crate::tables::SHA512_INITIAL_HASH_VALUES[7] as Field),
        };

        crate::permutation::compress(&mut state, witness);
        // Safety: get native result to compare against
        let expected = unsafe { __compress_native(witness) };
        assert_eq(state.a.raw, expected[0]);
        assert_eq(state.b.raw, expected[1]);
        assert_eq(state.c.raw, expected[2]);
        assert_eq(state.d.raw, expected[3]);
        assert_eq(state.e.raw, expected[4]);
        assert_eq(state.f.raw, expected[5]);
        assert_eq(state.g.raw, expected[6]);
        assert_eq(state.h.raw, expected[7]);
    }

    #[test]
    fn test_extend_message() {
        let mut initial_witness: [Field; 16] = [0; 16];
        for i in 0..16 {
            initial_witness[i] = crate::tables::SHA512_ROUND_CONSTANTS[i] as Field;
        }

        let result = crate::permutation::extend_message(initial_witness);
        // Safety: get native result to compare against
        let expected = unsafe { __extend_message_native(initial_witness) };

        for i in 0..80 {
            assert_eq(result[i], expected[i] as Field);
        }
    }
}
