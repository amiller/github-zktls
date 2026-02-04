use crate::tables::{
    BASE4_ENCODE_1BIT_TABLE, BASE4_ENCODE_3BIT_TABLE, BASE4_ENCODE_4BIT_TABLE,
    BASE4_ENCODE_5BIT_TABLE, BASE4_ENCODE_6BIT_TABLE, BASE4_ENCODE_7BIT_TABLE,
    BASE4_ENCODE_8BIT_TABLE, BASE4_ENCODE_9BIT_TABLE, BASE4_MAJORITY_DECODE_5BIT_TABLE,
    BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE, BASE4_POWERS, BASE4_XOR_DECODE_5BIT_TABLE,
};

// W2_POWER_SUM represents scalars that each base4_encoded_slices member must be multiplied by, in order to produce
// `encode(raw.rotate19) + encode(raw.rotate61) + encode(raw >> 6)`

global W2_POWER_SUM: [Field; 12] = [
    0x040000000000000000000040,
    0x100000000000000000000100,
    0x40000000000000000000040001,
    0x0100000000000000000000100004,
    0x0400000000000000000000400010,
    0x04000000000000000000004000100000,
    0x100004000001,
    0x1000040000010000,
    0x10000400000100000000,
    0x100004000001000000000000,
    0x4000100000040000000000000000,
    0x4000001000000000000000000001,
];

// W15_POWER_SUM represents scalars that each base4_encoded_slices member must be multiplied by, in order to produce
// `encode(raw.rotate1) + encode(raw.rotate8) + encode(raw >> 7)`
global W15_POWER_SUM: [Field; 12] = [
    0x40010000000000000000000000000000,
    0x040000000000000000000000000001,
    0x10000000000000000000000000000400,
    0x40000000000000000000000000001001,
    0x4005,
    0x40050000,
    0x1001400000,
    0x10014000000000,
    0x100140000000000000,
    0x1001400000000000000000,
    0x40050000000000000000000000,
    0x01001400000000000000000000000000,
];

/// Encodes the u64 inputs to the `Majority` function in an extended Base4 represeentation
///
/// *param* raw: the input 64-bit limb
/// *param* encoded: `raw` but where every bit is represented as a base4 value (e.g. encoded = \sum 4^i b_i, where `b_i` represents the i'th bit of `raw`)
/// *param* rotate_sum: the base-4 encoding of `encode(raw.rotate28) + encode(raw.rotate34) + encode(raw.rotate39)`
///         we use the fact that the map between rotate_sum and `raw.rotate28 ^ raw.rotate34 ^ raw.rotate39` is injective
pub(crate) struct EncodedMajority {
    pub(crate) raw: Field,
    pub(crate) encoded: Field,
    pub(crate) rotate_sum: Field,
}
impl EncodedMajority {
    pub(crate) fn new() -> Self {
        EncodedMajority { raw: 0, encoded: 0, rotate_sum: 0 }
    }
}

///  encodes the u64 inputs to the `Choose` function in an extended Base4 represeentation
/// *param* raw: the input 64-bit limb
/// *param* encoded: `raw` but where every bit is represented as a base4 value (e.g. encoded = \sum 4^i b_i, where `b_i` represents the i'th bit of `raw`)
/// *param* rotate_sum: the base-4 encoding of `encode(raw.rotate14) + encode(raw.rotate18) + encode(raw.rotate41)`
///        we use the fact that the map between rotate_sum and `raw.rotate14 ^ raw.rotate18 ^ raw.rotate41` is injective
pub(crate) struct EncodedChoose {
    pub(crate) raw: Field,
    pub(crate) encoded: Field,
    pub(crate) rotate_sum: Field,
}
impl EncodedChoose {
    pub(crate) fn new() -> Self {
        EncodedChoose { raw: 0, encoded: 0, rotate_sum: 0 }
    }
}

/// Encodes the u64 message limbs in a base4 representation, as well as the sum of the rotated components required for witness extension

/// *param* raw : the input 64-bit limb
/// *param* w : `raw` but where every bit is represented as a base4 value (e.g. encoded = \sum 4^i b_i, where `b_i` represents the i'th bit of `raw`)
/// *param* w2_rotate_sum : the base-4 encoding of `encode(raw.rotate19) + encode(raw.rotate61) + encode(raw >> 6)`
/// *param* w15_rotate_sum : the base-4 encoding of `encode(raw.rotate1) + encode(raw.rotate8) + encode(raw >> 7)`
///        like with EncodedChoose and EncodedMajority, there is an injective map between `w2_rotate_sum`/`w15_rotate_sum` and the base-2 bitwise operations required for message extension
pub(crate) struct EncodedWitness {
    pub(crate) raw: Field,
    pub(crate) w: Field,
    pub(crate) w2_rotate_sum: Field,
    pub(crate) w15_rotate_sum: Field,
}

impl EncodedWitness {
    pub(crate) fn new() -> Self {
        EncodedWitness { raw: 0, w: 0, w2_rotate_sum: 0, w15_rotate_sum: 0 }
    }
}

/// Take an input that is a u64 encoded via base4, and split it into 5-bit slices encoded via base64
unconstrained fn __split_into_base4_5bit_slices(encoded: Field) -> [u32; 13] {
    let mut acc = encoded as u128;

    let mut slices: [u32; 13] = [0; 13];

    for i in 0..13 {
        slices[i] = (acc & 1023) as u32;
        acc >>= 10;
    }

    slices
}

/// Split an input Field element `e` (known to be 64 bits) into slices that can be efficiently composed to produce inputs to `EncodedChoose`
unconstrained fn __decompose_e(e: Field) -> [u32; 9] {
    let mut r: [u32; 9] = [0; 9];
    let mut bytes = e.to_le_bytes::<8>();
    let b8to14 = bytes[1] & 63;
    let b14to16 = bytes[1] >> 6;
    let b16to18 = bytes[2] & 3;
    let b18to24 = bytes[2] >> 2;
    let b40to41 = bytes[5] & 1;
    let b41to48 = bytes[5] >> 1;

    r[0] = bytes[0] as u32; // 0-8
    r[1] = b8to14 as u32; // 8-14
    r[2] = (b14to16 + (b16to18 << 2)) as u32; // 14-18
    r[3] = b18to24 as u32;
    r[4] = bytes[3] as u32;
    r[5] = bytes[4] as u32 + (b40to41 as u32) * 256;
    r[6] = b41to48 as u32;
    r[7] = bytes[6] as u32;
    r[8] = bytes[7] as u32;
    r[0] = bytes[0] as u32; // 0-8
    r[1] = b8to14 as u32; // 8-14
    r[2] = (b14to16 + (b16to18 << 2)) as u32; // 14-18
    r[3] = b18to24 as u32;
    r[4] = bytes[3] as u32;
    r[5] = bytes[4] as u32 + (b40to41 as u32) * 256;
    r[6] = b41to48 as u32;
    r[7] = bytes[6] as u32;
    r[8] = bytes[7] as u32;
    r
}

/// Split an input Field element `a` (known to be 64 bits) into slices that can be efficiently composed to produce inputs to `EncodedMajority`
unconstrained fn __decompose_a(a: Field) -> [u32; 9] {
    let mut r: [u32; 9] = [0; 9];
    let mut bytes = a.to_le_bytes::<8>();
    let b24to28 = bytes[3] & 15;
    let b28to32 = bytes[3] >> 4;
    let b32to34 = bytes[4] & 3;
    let b34to39 = (bytes[4] >> 2) & 31;
    let b39to40 = bytes[4] >> 7;
    r[0] = bytes[0] as u32;
    r[1] = bytes[1] as u32;
    r[2] = bytes[2] as u32;
    r[3] = b24to28 as u32;
    r[4] = (b28to32 + (b32to34 << 4)) as u32;
    r[5] = b34to39 as u32;
    r[6] = b39to40 as u32 + (bytes[5] as u32 * 2);
    r[7] = bytes[6] as u32;
    r[8] = bytes[7] as u32;
    r
}

/// Split an input Field element `w` (known to be 64 bits) into slices that can be efficiently composed to produce inputs to `EncodedWitness`
unconstrained fn __decompose_witness(w: Field) -> [u32; 12] {
    // bit slice structure is:
    // 1, 5, 1, 1, 8, 3, 8, 8, 8, 9, 9, 3
    let mut acc: u64 = w as u64;
    let mut r: [u32; 12] = [0; 12];
    let mut r: [u32; 12] = [0; 12];

    r[0] = (acc & 1) as u32;
    r[0] = (acc & 1) as u32;
    acc >>= 1;
    r[1] = (acc & 31) as u32;
    r[1] = (acc & 31) as u32;
    acc >>= 5;
    r[2] = (acc & 1) as u32;
    r[2] = (acc & 1) as u32;
    acc >>= 1;
    r[3] = (acc & 1) as u32;
    r[3] = (acc & 1) as u32;
    acc >>= 1;
    r[4] = (acc & 255) as u32;
    r[4] = (acc & 255) as u32;
    acc >>= 8;
    r[5] = (acc & 7) as u32;
    r[5] = (acc & 7) as u32;
    acc >>= 3;
    r[6] = (acc & 255) as u32;
    r[6] = (acc & 255) as u32;
    acc >>= 8;
    r[7] = (acc & 255) as u32;
    r[7] = (acc & 255) as u32;
    acc >>= 8;
    r[8] = (acc & 255) as u32;
    r[8] = (acc & 255) as u32;
    acc >>= 8;
    r[9] = (acc & 511) as u32;
    r[9] = (acc & 511) as u32;
    acc >>= 9;
    r[10] = (acc & 511) as u32;
    r[10] = (acc & 511) as u32;
    acc >>= 9;
    r[11] = (acc & 7) as u32;
    r
}

/// Take an input field element `w`, known to be 64-bits, and convert into an EncodedWitness member
///
/// # Cost
/// 40 gates
pub(crate) fn encode_message_extension(w: Field) -> EncodedWitness {
    //Safety: split input into slices with the following bit sizes:
    //   1, 5, 1, 1, 8, 3, 8, 8, 8, 9, 9, 3
    //        We need to validate the correctness of these slice claims by asserting their sum equals `w`,
    //        and we also need to validate the bit range of each slice
    //        (we get an implicit range constraint for free by indexing our BASE4_ENCODE_TABLE lookup tables)
    let s: [u32; 12] = unsafe { __decompose_witness(w) };
    let s: [u32; 12] = unsafe { __decompose_witness(w) };

    // Validate the sum of the slices equals the original input `w`
    // Note: we range constrain the slices later on in the function
    let mut reconstructed = s[11] as Field;
    reconstructed *= 512;
    reconstructed += s[10] as Field;
    reconstructed *= 512;
    reconstructed += s[9] as Field;
    reconstructed *= 256;
    reconstructed += s[8] as Field;
    reconstructed *= 256;
    reconstructed += s[7] as Field;
    reconstructed *= 256;
    reconstructed += s[6] as Field;
    reconstructed *= 8;
    reconstructed += s[5] as Field;
    reconstructed *= 256;
    reconstructed += s[4] as Field;
    reconstructed *= 2;
    reconstructed += s[3] as Field;
    reconstructed *= 2;
    reconstructed += s[2] as Field;
    reconstructed *= 32;
    reconstructed += s[1] as Field;
    reconstructed *= 2;
    reconstructed += s[0] as Field;
    assert_eq(reconstructed, w);

    let mut base4_encoded_slices: [Field; 12] = [0; 12];

    // convert our input slices `s` into base4-encoded slices
    // Note: indexing each lookup table provides an implicit range check on the elements of `s`
    base4_encoded_slices[0] = BASE4_ENCODE_1BIT_TABLE[s[0]];
    base4_encoded_slices[1] = BASE4_ENCODE_5BIT_TABLE[s[1]];
    base4_encoded_slices[2] = BASE4_ENCODE_1BIT_TABLE[s[2]];
    base4_encoded_slices[3] = BASE4_ENCODE_1BIT_TABLE[s[3]];
    base4_encoded_slices[4] = BASE4_ENCODE_8BIT_TABLE[s[4]];
    base4_encoded_slices[5] = BASE4_ENCODE_3BIT_TABLE[s[5]];
    base4_encoded_slices[6] = BASE4_ENCODE_8BIT_TABLE[s[6]];
    base4_encoded_slices[7] = BASE4_ENCODE_8BIT_TABLE[s[7]];
    base4_encoded_slices[8] = BASE4_ENCODE_8BIT_TABLE[s[8]];
    base4_encoded_slices[9] = BASE4_ENCODE_9BIT_TABLE[s[9]];
    base4_encoded_slices[10] = BASE4_ENCODE_9BIT_TABLE[s[10]];
    base4_encoded_slices[11] = BASE4_ENCODE_3BIT_TABLE[s[11]];

    // 4 gates
    let mut w2_rotate_sum: Field = base4_encoded_slices[0] * W2_POWER_SUM[0];
    w2_rotate_sum += base4_encoded_slices[1] * W2_POWER_SUM[1];
    w2_rotate_sum += base4_encoded_slices[2] * W2_POWER_SUM[2];
    w2_rotate_sum += base4_encoded_slices[3] * W2_POWER_SUM[3];
    w2_rotate_sum += base4_encoded_slices[4] * W2_POWER_SUM[4];
    w2_rotate_sum += base4_encoded_slices[5] * W2_POWER_SUM[5];
    w2_rotate_sum += base4_encoded_slices[6] * W2_POWER_SUM[6];
    w2_rotate_sum += base4_encoded_slices[7] * W2_POWER_SUM[7];
    w2_rotate_sum += base4_encoded_slices[8] * W2_POWER_SUM[8];
    w2_rotate_sum += base4_encoded_slices[9] * W2_POWER_SUM[9];
    w2_rotate_sum += base4_encoded_slices[10] * W2_POWER_SUM[10];
    w2_rotate_sum += base4_encoded_slices[11] * W2_POWER_SUM[11];

    // 4 gates
    let mut w15_rotate_sum: Field = base4_encoded_slices[0] * W15_POWER_SUM[0];
    w15_rotate_sum += base4_encoded_slices[1] * W15_POWER_SUM[1];
    w15_rotate_sum += base4_encoded_slices[2] * W15_POWER_SUM[2];
    w15_rotate_sum += base4_encoded_slices[3] * W15_POWER_SUM[3];
    w15_rotate_sum += base4_encoded_slices[4] * W15_POWER_SUM[4];
    w15_rotate_sum += base4_encoded_slices[5] * W15_POWER_SUM[5];
    w15_rotate_sum += base4_encoded_slices[6] * W15_POWER_SUM[6];
    w15_rotate_sum += base4_encoded_slices[7] * W15_POWER_SUM[7];
    w15_rotate_sum += base4_encoded_slices[8] * W15_POWER_SUM[8];
    w15_rotate_sum += base4_encoded_slices[9] * W15_POWER_SUM[9];
    w15_rotate_sum += base4_encoded_slices[10] * W15_POWER_SUM[10];
    w15_rotate_sum += base4_encoded_slices[11] * W15_POWER_SUM[11];

    // 4 gates
    let mut ror0: Field = base4_encoded_slices[0];
    ror0 += base4_encoded_slices[1] * BASE4_POWERS[1];
    ror0 += base4_encoded_slices[2] * BASE4_POWERS[6];
    ror0 += base4_encoded_slices[3] * BASE4_POWERS[7];
    ror0 += base4_encoded_slices[4] * BASE4_POWERS[8];
    ror0 += base4_encoded_slices[5] * BASE4_POWERS[16];
    ror0 += base4_encoded_slices[6] * BASE4_POWERS[19];
    ror0 += base4_encoded_slices[7] * BASE4_POWERS[27];
    ror0 += base4_encoded_slices[8] * BASE4_POWERS[35];
    ror0 += base4_encoded_slices[9] * BASE4_POWERS[43];
    ror0 += base4_encoded_slices[10] * BASE4_POWERS[52];
    ror0 += base4_encoded_slices[11] * BASE4_POWERS[61];

    EncodedWitness { raw: w, w: ror0, w2_rotate_sum, w15_rotate_sum }
}

/// Take an input field element `e`, known to be 64-bits, and convert into an EncodedChoose member
///
/// # Cost
/// 27 gates
pub(crate) fn encode_e(e: Field) -> EncodedChoose {
    //Safety: split input into slices with the following bit sizes:
    //        8,6,4,6,8,9,7,8,8
    //        We need to validate the correctness of these slice claims by asserting their sum equals `a`,
    //        and we also need to validate the bit range of each slice
    //        (we get an implicit range constraint for free by indexing our BASE4_ENCODE_TABLE lookup tables)
    let s = unsafe { __decompose_e(e) };

    // Validate the sum of the slices equals the original input `e`
    // Note: we range constrain the slices later on in the function
    let mut reconstructed = s[8] as Field;
    reconstructed *= 256;
    reconstructed += s[7] as Field;
    reconstructed *= 128;
    reconstructed += s[6] as Field;
    reconstructed *= 512;
    reconstructed += s[5] as Field;
    reconstructed *= 256;
    reconstructed += s[4] as Field;
    reconstructed *= 64;
    reconstructed += s[3] as Field;
    reconstructed *= 16;
    reconstructed += s[2] as Field;
    reconstructed *= 64;
    reconstructed += s[1] as Field;
    reconstructed *= 256;
    reconstructed += s[0] as Field;
    assert_eq(reconstructed, e); // 4 gates?

    // convert our input slices `s` into base4-encoded slices
    // Note: indexing each lookup table provides an implicit range check on the elements of `s`
    let mut base4_encoded_slices: [Field; 9] = [0; 9];
    base4_encoded_slices[0] = BASE4_ENCODE_8BIT_TABLE[s[0]];
    base4_encoded_slices[1] = BASE4_ENCODE_6BIT_TABLE[s[1]];
    base4_encoded_slices[2] = BASE4_ENCODE_4BIT_TABLE[s[2]];
    base4_encoded_slices[3] = BASE4_ENCODE_6BIT_TABLE[s[3]];
    base4_encoded_slices[4] = BASE4_ENCODE_8BIT_TABLE[s[4]];
    base4_encoded_slices[5] = BASE4_ENCODE_9BIT_TABLE[s[5]];
    base4_encoded_slices[6] = BASE4_ENCODE_7BIT_TABLE[s[6]];
    base4_encoded_slices[7] = BASE4_ENCODE_8BIT_TABLE[s[7]];
    base4_encoded_slices[8] = BASE4_ENCODE_8BIT_TABLE[s[8]];

    let mut e_ror0: Field = base4_encoded_slices[0];
    e_ror0 += base4_encoded_slices[1] * BASE4_POWERS[8];
    e_ror0 += base4_encoded_slices[2] * BASE4_POWERS[14];
    e_ror0 += base4_encoded_slices[3] * BASE4_POWERS[18];
    e_ror0 += base4_encoded_slices[4] * BASE4_POWERS[24];
    e_ror0 += base4_encoded_slices[5] * BASE4_POWERS[32];
    e_ror0 += base4_encoded_slices[6] * BASE4_POWERS[41];
    e_ror0 += base4_encoded_slices[7] * BASE4_POWERS[48];
    e_ror0 += base4_encoded_slices[8] * BASE4_POWERS[56];

    std::as_witness(e_ror0);

    // RSUMPOWERS represents scalars that each base4_encoded_slices member must be multiplied by, in order to produce
    // `encode(raw.rotate14) + encode(raw.rotate18) + encode(raw.rotate41)`
    let RSUMPOWERS = [
        0x10100000000000400000000000,
        0x101000000000004000000000000000,
        0x01000000000004000000000000000001,
        0x0400000000000000000101,
        0x400000000000000000101000,
        0x4000000000000000001010000000,
        0x40400000000001,
        0x101000000000004000,
        0x1010000000000040000000,
    ];
    let mut e_ror_sum = base4_encoded_slices[0] * RSUMPOWERS[0];
    e_ror_sum += base4_encoded_slices[1] * RSUMPOWERS[1];
    e_ror_sum += base4_encoded_slices[2] * RSUMPOWERS[2];
    e_ror_sum += base4_encoded_slices[3] * RSUMPOWERS[3];
    e_ror_sum += base4_encoded_slices[4] * RSUMPOWERS[4];
    e_ror_sum += base4_encoded_slices[5] * RSUMPOWERS[5];
    e_ror_sum += base4_encoded_slices[6] * RSUMPOWERS[6];
    e_ror_sum += base4_encoded_slices[7] * RSUMPOWERS[7];
    e_ror_sum += base4_encoded_slices[8] * RSUMPOWERS[8];
    std::as_witness(e_ror_sum);

    EncodedChoose { raw: e, encoded: e_ror0, rotate_sum: e_ror_sum }
}

/// Take an input field element `a`, known to be 64-bits, and convert into an EncodedMajority member
///
/// # Cost
/// 27 gates
pub(crate) fn encode_a(a: Field) -> EncodedMajority {
    //Safety: split input into slices with the following bit sizes:
    //        8,8,8,4,6,5,9,8,8
    //        We need to validate the correctness of these slice claims by asserting their sum equals `a`,
    //        and we also need to validate the bit range of each slice
    //        (we get an implicit range constraint for free by indexing our BASE4_ENCODE_TABLE lookup tables)
    let s = unsafe { __decompose_a(a) };

    // Validate the sum of the slices equals the original input `e`
    // Note: we range constrain the slices later on in the function
    let mut reconstructed = s[8] as Field;
    reconstructed *= 256;
    reconstructed += s[7] as Field;
    reconstructed *= 512;
    reconstructed += s[6] as Field;
    reconstructed *= 32;
    reconstructed += s[5] as Field;
    reconstructed *= 64;
    reconstructed += s[4] as Field;
    reconstructed *= 16;
    reconstructed += s[3] as Field;
    reconstructed *= 256;
    reconstructed += s[2] as Field;
    reconstructed *= 256;
    reconstructed += s[1] as Field;
    reconstructed *= 256;
    reconstructed += s[0] as Field;
    assert_eq(reconstructed, a);

    let mut base4_encoded_slices: [Field; 9] = [0; 9];

    // convert our input slices `s` into base4-encoded slices
    // Note: indexing each lookup table provides an implicit range check on the elements of `s`
    base4_encoded_slices[0] = BASE4_ENCODE_8BIT_TABLE[s[0]];
    base4_encoded_slices[1] = BASE4_ENCODE_8BIT_TABLE[s[1]];
    base4_encoded_slices[2] = BASE4_ENCODE_8BIT_TABLE[s[2]];
    base4_encoded_slices[3] = BASE4_ENCODE_4BIT_TABLE[s[3]];
    base4_encoded_slices[4] = BASE4_ENCODE_6BIT_TABLE[s[4]];
    base4_encoded_slices[5] = BASE4_ENCODE_5BIT_TABLE[s[5]];
    base4_encoded_slices[6] = BASE4_ENCODE_9BIT_TABLE[s[6]];
    base4_encoded_slices[7] = BASE4_ENCODE_8BIT_TABLE[s[7]];
    base4_encoded_slices[8] = BASE4_ENCODE_8BIT_TABLE[s[8]];

    // RSUMPOWERS represents scalars that each base4_encoded_slices member must be multiplied by, in order to produce
    // `encode(raw.rotate28) + encode(raw.rotate34) + encode(raw.rotate39)`
    let RSUMPOWERS: [Field; 9] = [
        0x01001004000000000000,
        0x010010040000000000000000,
        0x0100100400000000000000000000,
        0x01001004000000000000000000000000,
        0x100400000000000000000000000001,
        0x400000000000000000000000001001,
        0x400401,
        0x010010040000,
        0x0100100400000000,
    ];
    let mut a_ror_sum = base4_encoded_slices[0] * RSUMPOWERS[0];
    a_ror_sum += base4_encoded_slices[1] * RSUMPOWERS[1];
    a_ror_sum += base4_encoded_slices[2] * RSUMPOWERS[2];
    a_ror_sum += base4_encoded_slices[3] * RSUMPOWERS[3];
    a_ror_sum += base4_encoded_slices[4] * RSUMPOWERS[4];
    a_ror_sum += base4_encoded_slices[5] * RSUMPOWERS[5];
    a_ror_sum += base4_encoded_slices[6] * RSUMPOWERS[6];
    a_ror_sum += base4_encoded_slices[7] * RSUMPOWERS[7];
    a_ror_sum += base4_encoded_slices[8] * RSUMPOWERS[8];
    std::as_witness(a_ror_sum);
    //     // 8,8,8,4,6,5,9,8,8
    let mut a_ror0 = base4_encoded_slices[0];
    a_ror0 += base4_encoded_slices[1] * BASE4_POWERS[8];
    a_ror0 += base4_encoded_slices[2] * BASE4_POWERS[16];
    a_ror0 += base4_encoded_slices[3] * BASE4_POWERS[24];
    a_ror0 += base4_encoded_slices[4] * BASE4_POWERS[28];
    a_ror0 += base4_encoded_slices[5] * BASE4_POWERS[34];
    a_ror0 += base4_encoded_slices[6] * BASE4_POWERS[39];
    a_ror0 += base4_encoded_slices[7] * BASE4_POWERS[48];
    a_ror0 += base4_encoded_slices[8] * BASE4_POWERS[56];
    std::as_witness(a_ror0);
    EncodedMajority { raw: a, encoded: a_ror0, rotate_sum: a_ror_sum }
}

/// Given three Field inputs `a, b, c`, known to be 64-bit values encoded as base4 numbers,
/// evaluate the SHA384/512 majority function `(a and b) xor (a and c) xor (b and c)`
///
/// Note: the return parameter is a base-2 value
pub(crate) fn decode_majority(a: Field, b: Field, c: Field) -> Field {
    // adding base4 basis numbers produces an injective map vs computing (a&b)^(a&c)^(b&c) in the base2 basis
    // e.g. each base4 "bit" in `encoded` will be either 0, 1, 2 or 3
    // We use a lookup table `BASE4_MAJORITY_DECODE_5BIT_TABLE` to create the following map for each bit:
    // | a + b + c (base4) | (a&b)^(a&c)^(b&c) (base2) |
    // | ----------------- | ------------------------- |
    // | 0                 | 0                         |
    // | 1                 | 0                         |
    // | 2                 | 1                         |
    // | 3                 | 1                         |
    // note: BASE4_MAJORITY_DECODE_5BIT_TABLE is size 4^5 because we apply the above map to 5 bits at a time
    let encoded = a + b + c;
    // Safety: split input into base4 5bit slices (i.e. 10 bit slices)
    //         we validate the sum of the slices equals the input.
    //         indexing `BASE4_MAJORITY_DECODE_5BIT_TABLE` by each slice is an implicit range check
    let slices = unsafe { __split_into_base4_5bit_slices(encoded) };
    let mut reconstructed: Field = 0;
    let mut decoded: Field = 0;

    // 13 lookups = 26 gates
    for i in 0..13 {
        reconstructed *= 1024;
        reconstructed += slices[12 - i] as Field;
        decoded *= 32;
        decoded += BASE4_MAJORITY_DECODE_5BIT_TABLE[slices[12 - i]];
    }
    // reconstructed = 13 chunks, encoded = 3 chunks = 5 gates?
    assert_eq(reconstructed, encoded);

    // Tadaa. the output is our base2 XOR result.
    decoded
}

/// Given three Field inputs `e, f, g`, known to be 64-bit values encoded as base4 numbers,
/// evaluate the SHA384/512 choose function `(e & f) ^ (!e & g)`
///
/// Note: the return parameter is a base-2 value
pub(crate) fn decode_choose(e: Field, f: Field, g: Field) -> Field {
    // Note: unlike in `decode_majority`, there is not a nice injective map between
    // a linear relation between base4-encoded values and the bitwise operation over base2 values.
    // The smallest linear relation that works is base7, and we cannot fit a base7 basis representation of a u64 into a Field element (too many bits).

    // What we do instead is we create two maps and sum the result together
    // We create an injective map between: `e + e + g` (base4) and `(!e & g)` (base2)
    //                                and: `e + f` (base4) and `(e & f)` (base2)
    // It is not possible for both (!e & g) AND (e & f) to both equal 1 for a single bit.
    // So we can sum together the two decoded outputs
    let two_e_plus_g = e + e + g;
    let e_plus_f = e + f;
    // Safety: split input into base4 5bit slices (i.e. 10 bit slices)
    //         we validate the sum of the slices equals the input.
    //         indexing `BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE` by each slice is an implicit range check
    let lhs_slices = unsafe { __split_into_base4_5bit_slices(two_e_plus_g) };
    let mut reconstructed: Field = 0;
    let mut decoded_lhs: Field = 0;

    // adding `2e + g` base4 basis numbers produces an injective map vs computing (!e & g) in the base2 basis
    // e.g. each base4 "bit" in `encoded` will be either 0, 1, 2 or 3
    // We use a lookup table `BASE4_MAJORITY_DECODE_5BIT_TABLE` to create the following map for each bit:
    // | 2e + g (base4) | (!e & g) (base2) |
    // | -------------- | ---------------- |
    // | 0              | 0                |
    // | 1              | 1                |
    // | 2              | 0                |
    // | 3              | 0                |
    // note: BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE is size 4^5 because we apply the above map to 5 bits at a time
    for i in 0..13 {
        reconstructed *= 1024;
        reconstructed += lhs_slices[12 - i] as Field;
        decoded_lhs *= 32;
        decoded_lhs += BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE[lhs_slices[12 - i]];
    }
    // relation has 15 inputs = 5 gates
    assert_eq(reconstructed, two_e_plus_g);

    // Safety: split input into base4 5bit slices (i.e. 10 bit slices)
    //         we validate the sum of the slices equals the input.
    //         indexing `BASE4_MAJORITY_DECODE_5BIT_TABLE` by each slice is an implicit range check
    let rhs_slices = unsafe { __split_into_base4_5bit_slices(e_plus_f) };
    let mut reconstructed: Field = 0;
    let mut decoded_rhs: Field = 0;

    // adding `2e + f` base4 basis numbers produces an injective map vs computing (!e & f) in the base2 basis
    // e.g. each base4 "bit" in `encoded` will be either 0, 1, 2 or 3
    // We use a lookup table `BASE4_MAJORITY_DECODE_5BIT_TABLE` to create the following map for each bit:
    // | e + f (base4) | (e & f) (base2) |
    // | -------------- | ---------------- |
    // | 0              | 0                |
    // | 1              | 0                |
    // | 2              | 1                |
    // | 3              | 0                |
    // note: BASE4_PARTIAL_CHOOSE_DECODE_5BIT_TABLE is size 4^5 because we apply the above map to 5 bits at a time
    for i in 0..13 {
        reconstructed *= 1024;
        reconstructed += rhs_slices[12 - i] as Field;
        decoded_rhs *= 32;
        decoded_rhs += BASE4_MAJORITY_DECODE_5BIT_TABLE[rhs_slices[12 - i]];
    }
    // relation has 15 inputs = 5 gates
    assert_eq(reconstructed, e_plus_f);

    decoded_lhs + decoded_rhs
}

/// Given an input `encoded` that is a linear sum of base4 elements, map into a base2 number which is a linear XOR of the same elements
///
/// e.g. if `encoded = a + b + c` in base4, the return value will be a ^ b ^ c in base2
pub(crate) fn decode_xor(encoded: Field) -> Field {
    //Safety: split input into "5-bit" slices.
    //        Because the input is in base4, we actually obtain 10-bit slices
    //        We need to validate the correctness of these slice claims by asserting their sum equals `encoded`,
    //        and we also need to validate the bit range of each slice
    //        (we get an implicit range constraint for free by indexing our BASE4_XOR_DECODE_5BIT_TABLE lookup table)
    let slices = unsafe { __split_into_base4_5bit_slices(encoded) };

    let mut reconstructed: Field = 0;
    let mut decoded: Field = 0;

    // We use a lookup table `BASE4_XOR_DECODE_5BIT_TABLE` to create the following map for each bit:
    // | encoded        | xor result (base2) |
    // | -------------- | ------------------ |
    // | 0              | 0                  |
    // | 1              | 1                  |
    // | 2              | 0                  |
    // | 3              | 1                  |
    // note: BASE4_XOR_DECODE_5BIT_TABLE is size 4^5 because we apply the above map to 5 bits at a time
    for i in 0..13 {
        reconstructed *= 1024;
        reconstructed += slices[12 - i] as Field;
        decoded *= 32;
        decoded += BASE4_XOR_DECODE_5BIT_TABLE[slices[12 - i]];
    }
    // decoded = 13 adds = 5 gates
    // reconstructed vs encoded = 14 vars = 5 gates
    assert_eq(reconstructed, encoded);

    decoded
}

#[test]
fn test_encode_message_extension() {
    let expected: u64 = 0x7ffffaffeffff2ff;
    let encoded = encode_message_extension(expected as Field);

    let w_ror1: u64 = (expected >> 1) + ((expected & 1) << (64 - 1));
    let w_ror8 = (expected >> 8) + ((expected & 255) << (64 - 8));
    let w_rshift7 = (expected >> 7);
    let w_ror19 = (expected >> 19) + ((expected & 0x7ffff) << (64 - 19));
    let w_ror61 = (expected >> 61) + ((expected & 0x1fffffffffffffff) << (64 - 61));
    let w_rshift6 = (expected >> 6);

    let result = decode_xor(encoded.w);

    let decoded_w2_rotate_sum: Field = decode_xor(encoded.w2_rotate_sum);
    let decoded_w15_rotate_sum: Field = decode_xor(encoded.w15_rotate_sum);

    assert_eq(result, expected as Field);
    assert_eq(decoded_w2_rotate_sum, (w_ror19 ^ w_ror61 ^ w_rshift6) as Field);
    assert_eq(decoded_w15_rotate_sum, (w_ror1 ^ w_ror8 ^ w_rshift7) as Field);
}

#[test]
fn test_encode_e() {
    let expected: u64 = 0x7ffffaffeffff2ff;
    let e_encoded = encode_e(expected as Field);

    let ror_14 = (expected >> 14) + ((expected & 0x3fff) << (64 - 14));
    let ror_18 = (expected >> 18) + ((expected & 0x3ffff) << (64 - 18));
    let ror_41 = (expected >> 41) + ((expected & 0x1ffffffffff) << (64 - 41));

    let result = decode_xor(e_encoded.encoded);
    let decoded_rotate_sum: Field = decode_xor(e_encoded.rotate_sum);

    assert_eq(result, expected as Field);
    assert_eq(decoded_rotate_sum, (ror_14 ^ ror_18 ^ ror_41) as Field);
}

#[test]
fn test_encode_a() {
    let expected: u64 = 0x7ffffaffeffff2ff; // two pow 52
    let a_encoded = encode_a(expected as Field);

    let ror_28 = (expected >> 28) + ((expected & 0x0fffffff) << (64 - 28));
    let ror_34 = (expected >> 34) + ((expected & 0x3ffffffff) << (64 - 34));
    let ror_39 = (expected >> 39) + ((expected & 0x7fffffffff) << (64 - 39));

    let result = decode_xor(a_encoded.encoded);
    let decoded_ror_sum: Field = decode_xor(a_encoded.rotate_sum);

    assert_eq(result, expected as Field);
    assert_eq(decoded_ror_sum, (ror_28 ^ ror_34 ^ ror_39) as Field);
}

#[test]
fn test_majority() {
    let a: u64 = 0x7ffffaffeffff2ff;
    let b: u64 = 0xf23ff3900baa22ff;
    let c: u64 = 0x2439823847ffeeaa;

    let a_enc = encode_a(a as Field);
    let b_enc = encode_a(b as Field);
    let c_enc = encode_a(c as Field);

    let result = decode_majority(a_enc.encoded, b_enc.encoded, c_enc.encoded);

    let expected = ((a & b) ^ (a & c) ^ (b & c)) as Field;

    assert_eq(result, expected);
}

#[test]
fn test_choose() {
    let e: u64 = 0x7ffffaffeffff2ff;
    let f: u64 = 0xf23ff3900baa22ff;
    let g: u64 = 0xf439823847ffeeaa;

    let e_enc = encode_e(e as Field);
    let f_enc = encode_e(f as Field);
    let g_enc = encode_e(g as Field);

    let result = decode_choose(e_enc.encoded, f_enc.encoded, g_enc.encoded);

    let expected = ((!e & g) ^ (e & f)) as Field;

    assert_eq(result, expected);
}
