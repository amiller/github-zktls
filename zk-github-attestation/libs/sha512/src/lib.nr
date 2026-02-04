mod permutation;
mod tables;
mod generate_tables;
mod encoding;
mod benchmarks;
mod formatting;

use crate::encoding::{encode_a, encode_e};
use crate::formatting::{msg_u8_to_u64, reduce_modulo_64, to_u64};
use crate::permutation::{compress, extend_message, RoundState};
use crate::tables::{SHA384_INITIAL_HASH_VALUES, SHA512_INITIAL_HASH_VALUES};
use std::ops::WrappingAdd;
pub global SHA512_LENGTH_PARAMETER_BYTES: u32 = 16;

/// Size of the message block when packed as 8-byte integer array.
pub global SHA512_BLOCK_SIZE: u32 = 128;

global INT_BLOCK_SIZE: u32 = 16;
type INT_BLOCK = [u64; INT_BLOCK_SIZE];

/// The state accumulates the blocks.
/// Its overall size is the same as the `HASH`.
type STATE = [u64; 8];

/// SHA512 compression function
///
/// We expose this as a public method because the compression fn is needed if the user desires to evaluate a partial hash.
/// Interface is compatible with the sha256 blackbox fns
pub fn sha512_compression(_input: INT_BLOCK, _state: STATE) -> STATE {
    let mut message_input: [Field; 16] = [0; 16];
    for i in 0..16 {
        message_input[i] = _input[i] as Field;
    }

    let mut state: RoundState = RoundState {
        a: encode_a(_state[0] as Field),
        b: encode_a(_state[1] as Field),
        c: encode_a(_state[2] as Field),
        d: encode_a(_state[3] as Field),
        e: encode_e(_state[4] as Field),
        f: encode_e(_state[5] as Field),
        g: encode_e(_state[6] as Field),
        h: encode_e(_state[7] as Field),
    };

    let mut w: [Field; 80] = extend_message(message_input);

    compress(&mut state, w);

    let mut output: STATE = [0; 8];
    output[0] = to_u64(state.a.raw);
    output[1] = to_u64(state.b.raw);
    output[2] = to_u64(state.c.raw);
    output[3] = to_u64(state.d.raw);
    output[4] = to_u64(state.e.raw);
    output[5] = to_u64(state.f.raw);
    output[6] = to_u64(state.g.raw);
    output[7] = to_u64(state.h.raw);
    output
}

/// The SHA384/SHA512 hash function
///
/// Input is the message to be hashed, produces a 64-byte output
/// The `IS_SHA512` generic is used to toggle whether a SHA384 or SHA512 hash is desired
/// (the only diff between SHA384/SHA512 are different initial starting constants, and the SHA384 hash output is truncated)
fn digest<let N: u32, let IS_SHA512: u1>(msg: [u8; N]) -> [u8; 64] {
    // noir-fmt:ignore
    let mut h: [u64; 8] = if IS_SHA512 == 1 {
        SHA512_INITIAL_HASH_VALUES
    } else {
        SHA384_INITIAL_HASH_VALUES
    };
    let mut c: [u64; 8] = [0; 8]; // Compression of current message block as sequence of u64
    let mut out_h: [u8; 64] = [0; 64]; // Digest as sequence of bytes

    let num_blocks = (N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE;

    let num_padded_bytes = num_blocks * SHA512_BLOCK_SIZE;
    let mut padded_msg: [u8; ((N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE) * SHA512_BLOCK_SIZE] = [
        0; ((N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE)
            * SHA512_BLOCK_SIZE
    ];

    for i in 0..N {
        padded_msg[i] = msg[i];
    }
    padded_msg[N] = 128;
    // N.B. assuming the message length (in bits) can be covered in 32 bits (approx 16MB message!)
    let length_bytes = (N as Field * 8).to_le_bytes::<4>();
    padded_msg[num_padded_bytes - 1] = length_bytes[0];
    padded_msg[num_padded_bytes - 2] = length_bytes[1];
    padded_msg[num_padded_bytes - 3] = length_bytes[2];
    padded_msg[num_padded_bytes - 4] = length_bytes[3];

    let mut block_bytes: [u8; 128] = [0; 128];
    for i in 0..num_blocks {
        for j in 0..128 {
            block_bytes[j] = padded_msg[i * 128 + j];
        }
        c = sha512_compression(msg_u8_to_u64(block_bytes), h);
        for j in 0..8 {
            h[j] = to_u64(reduce_modulo_64(h[j] as Field + c[j] as Field));
        }
    }

    // Return final hash as byte array
    for j in 0..8 {
        let h_bytes: [u8; 8] = (h[7 - j] as Field).to_le_bytes();
        for k in 0..8 {
            out_h[63 - 8 * j - k] = h_bytes[k];
        }
    }
    out_h
}

/// The SHA384/SHA512 hash function for a *variable length* input (up to a bounded maximum)
///
/// Input is the message to be hashed, produces a 64-byte output
/// The `IS_SHA512` generic is used to toggle whether a SHA384 or SHA512 hash is desired
///
/// (the only diff between SHA384/SHA512 are different initial starting constants, and the SHA384 hash output is truncated)
fn digest_var<let N: u32, let IS_SHA512: u1>(msg: BoundedVec<u8, N>) -> [u8; 64] {
    // noir-fmt:ignore
    let mut h: [u64; 8] = if IS_SHA512 == 1 {
        SHA512_INITIAL_HASH_VALUES
    } else {
        SHA384_INITIAL_HASH_VALUES
    };
    let mut c: [u64; 8] = [0; 8]; // Compression of current message block as sequence of u64
    let mut out_h: [u8; 64] = [0; 64]; // Digest as sequence of bytes

    let num_blocks = (N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE;

    let mut padded_msg: [u8; ((N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE) * SHA512_BLOCK_SIZE] = [
        0; ((N + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE)
            * SHA512_BLOCK_SIZE
    ];

    let msg_text = msg.storage();
    for i in 0..N {
        padded_msg[i] = msg_text[i];
    }

    let msg_length = msg.len();

    let num_used_blocks =
        (msg_length + SHA512_LENGTH_PARAMETER_BYTES + SHA512_BLOCK_SIZE) / SHA512_BLOCK_SIZE;

    let num_used_padded_bytes = num_used_blocks * SHA512_BLOCK_SIZE;
    // N.B. this line turns `padded_msg` into a RAM array, which is expensive!
    // The cost of this is roughly 7* N gates.
    // There are cheaper ways of doing this (e.g. pack into 8-byte field elements first, then update msg length),
    // however the cost of the RAM array is small relative to the total cost of a hash, so not really worth the extra complexity
    padded_msg[msg_length] = 128;
    // N.B. we assume the message length (in bits) can be covered in 32 bits (approx 16MB message!)
    let length_bytes = (msg_length as Field * 8).to_le_bytes::<4>();
    padded_msg[num_used_padded_bytes - 1] = length_bytes[0];
    padded_msg[num_used_padded_bytes - 2] = length_bytes[1];
    padded_msg[num_used_padded_bytes - 3] = length_bytes[2];
    padded_msg[num_used_padded_bytes - 4] = length_bytes[3];

    let mut output_h: [u64; 8] = h;
    let mut block_bytes: [u8; 128] = [0; 128];
    for i in 0..num_blocks {
        for j in 0..128 {
            block_bytes[j] = padded_msg[i * 128 + j];
        }
        c = sha512_compression(msg_u8_to_u64(block_bytes), h);
        for j in 0..8 {
            h[j] = h[j].wrapping_add(c[j]);
        }
        if (i < num_used_blocks) {
            output_h = h;
        }
    }

    // Return final hash as byte array
    for j in 0..8 {
        let h_bytes: [u8; 8] = (output_h[7 - j] as Field).to_le_bytes();
        for k in 0..8 {
            out_h[63 - 8 * j - k] = h_bytes[k];
        }
    }
    out_h
}

/// methods here are interface-compatible with sha256 blackbox fns
pub mod sha512 {
    pub fn digest<let N: u32>(msg: [u8; N]) -> [u8; 64] {
        crate::digest::<_, 1>(msg)
    }

    pub fn sha512_var<let N: u32>(msg: BoundedVec<u8, N>) -> [u8; 64] {
        crate::digest_var::<_, 1>(msg)
    }

    // Fuzz testing the sha512 implementation

    #[export]
    fn test_sha512_1(input: BoundedVec<u8, 1>) -> [u8; 64] {
        sha512_var(input)
    }

    #[export]
    fn test_sha512_100(input: BoundedVec<u8, 100>) -> [u8; 64] {
        sha512_var(input)
    }

    #[export]
    fn test_sha512_256(input: BoundedVec<u8, 256>) -> [u8; 64] {
        sha512_var(input)
    }

    #[test]
    fn test_empty_string() {
        let input: [u8; 0] = [];
        let result = digest(input);

        let expected: [u8; 64] = [
            0xcf, 0x83, 0xe1, 0x35, 0x7e, 0xef, 0xb8, 0xbd, 0xf1, 0x54, 0x28, 0x50, 0xd6, 0x6d,
            0x80, 0x07, 0xd6, 0x20, 0xe4, 0x05, 0x0b, 0x57, 0x15, 0xdc, 0x83, 0xf4, 0xa9, 0x21,
            0xd3, 0x6c, 0xe9, 0xce, 0x47, 0xd0, 0xd1, 0x3c, 0x5d, 0x85, 0xf2, 0xb0, 0xff, 0x83,
            0x18, 0xd2, 0x87, 0x7e, 0xec, 0x2f, 0x63, 0xb9, 0x31, 0xbd, 0x47, 0x41, 0x7a, 0x81,
            0xa5, 0x38, 0x32, 0x7a, 0xf9, 0x27, 0xda, 0x3e,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
    }

    #[test]
    fn test_abc() {
        let input = "abc".as_bytes();
        let result = digest(input);
        let result_var = sha512_var(BoundedVec::<u8, 256>::from_array(input));
        let expected: [u8; 64] = [
            0xdd, 0xaf, 0x35, 0xa1, 0x93, 0x61, 0x7a, 0xba, 0xcc, 0x41, 0x73, 0x49, 0xae, 0x20,
            0x41, 0x31, 0x12, 0xe6, 0xfa, 0x4e, 0x89, 0xa9, 0x7e, 0xa2, 0x0a, 0x9e, 0xee, 0xe6,
            0x4b, 0x55, 0xd3, 0x9a, 0x21, 0x92, 0x99, 0x2a, 0x27, 0x4f, 0xc1, 0xa8, 0x36, 0xba,
            0x3c, 0x23, 0xa3, 0xfe, 0xeb, 0xbd, 0x45, 0x4d, 0x44, 0x23, 0x64, 0x3c, 0xe8, 0x0e,
            0x2a, 0x9a, 0xc9, 0x4f, 0xa5, 0x4c, 0xa4, 0x9f,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

    #[test]
    fn test_418_bit_msg() {
        let input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_bytes();
        let result = digest(input);
        let result_var = sha512_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 64] = [
            0x20, 0x4a, 0x8f, 0xc6, 0xdd, 0xa8, 0x2f, 0x0a, 0x0c, 0xed, 0x7b, 0xeb, 0x8e, 0x08,
            0xa4, 0x16, 0x57, 0xc1, 0x6e, 0xf4, 0x68, 0xb2, 0x28, 0xa8, 0x27, 0x9b, 0xe3, 0x31,
            0xa7, 0x03, 0xc3, 0x35, 0x96, 0xfd, 0x15, 0xc1, 0x3b, 0x1b, 0x07, 0xf9, 0xaa, 0x1d,
            0x3b, 0xea, 0x57, 0x78, 0x9c, 0xa0, 0x31, 0xad, 0x85, 0xc7, 0xa7, 0x1d, 0xd7, 0x03,
            0x54, 0xec, 0x63, 0x12, 0x38, 0xca, 0x34, 0x45,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

    #[test]
    fn test_two_block_msg() {
        let input = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
            .as_bytes();
        let result = digest(input);
        let result_var = sha512_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 64] = [
            0x8e, 0x95, 0x9b, 0x75, 0xda, 0xe3, 0x13, 0xda, 0x8c, 0xf4, 0xf7, 0x28, 0x14, 0xfc,
            0x14, 0x3f, 0x8f, 0x77, 0x79, 0xc6, 0xeb, 0x9f, 0x7f, 0xa1, 0x72, 0x99, 0xae, 0xad,
            0xb6, 0x88, 0x90, 0x18, 0x50, 0x1d, 0x28, 0x9e, 0x49, 0x00, 0xf7, 0xe4, 0x33, 0x1b,
            0x99, 0xde, 0xc4, 0xb5, 0x43, 0x3a, 0xc7, 0xd3, 0x29, 0xee, 0xb6, 0xdd, 0x26, 0x54,
            0x5e, 0x96, 0xe5, 0x5b, 0x87, 0x4b, 0xe9, 0x09,
        ];

        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

}

pub mod sha384 {
    pub fn digest<let N: u32>(msg: [u8; N]) -> [u8; 48] {
        let full_result = crate::digest::<_, 0>(msg);
        let mut r: [u8; 48] = [0; 48];
        for i in 0..48 {
            r[i] = full_result[i];
        }
        r
    }

    pub fn sha384_var<let N: u32>(msg: BoundedVec<u8, N>) -> [u8; 48] {
        let full_result = crate::digest_var::<_, 0>(msg);
        let mut r: [u8; 48] = [0; 48];
        for i in 0..48 {
            r[i] = full_result[i];
        }
        r
    }

    // Fuzz testing the sha384 implementation

    #[export]
    fn test_sha384_1(input: BoundedVec<u8, 1>) -> [u8; 48] {
        sha384_var(input)
    }

    #[export]
    fn test_sha384_100(input: BoundedVec<u8, 100>) -> [u8; 48] {
        sha384_var(input)
    }

    #[export]
    fn test_sha384_256(input: BoundedVec<u8, 256>) -> [u8; 48] {
        sha384_var(input)
    }

    #[test]
    fn test_empty_string() {
        let input: [u8; 0] = [];
        let result = digest(input);
        let result_var = sha384_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 48] = [
            0x38, 0xb0, 0x60, 0xa7, 0x51, 0xac, 0x96, 0x38, 0x4c, 0xd9, 0x32, 0x7e, 0xb1, 0xb1,
            0xe3, 0x6a, 0x21, 0xfd, 0xb7, 0x11, 0x14, 0xbe, 0x07, 0x43, 0x4c, 0x0c, 0xc7, 0xbf,
            0x63, 0xf6, 0xe1, 0xda, 0x27, 0x4e, 0xde, 0xbf, 0xe7, 0x6f, 0x65, 0xfb, 0xd5, 0x1a,
            0xd2, 0xf1, 0x48, 0x98, 0xb9, 0x5b,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

    #[test]
    fn test_abc() {
        let input = "abc".as_bytes();
        let result = digest(input);
        let result_var = sha384_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 48] = [
            0xcb, 0x00, 0x75, 0x3f, 0x45, 0xa3, 0x5e, 0x8b, 0xb5, 0xa0, 0x3d, 0x69, 0x9a, 0xc6,
            0x50, 0x07, 0x27, 0x2c, 0x32, 0xab, 0x0e, 0xde, 0xd1, 0x63, 0x1a, 0x8b, 0x60, 0x5a,
            0x43, 0xff, 0x5b, 0xed, 0x80, 0x86, 0x07, 0x2b, 0xa1, 0xe7, 0xcc, 0x23, 0x58, 0xba,
            0xec, 0xa1, 0x34, 0xc8, 0x25, 0xa7,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

    #[test]
    fn test_418_bit_msg() {
        let input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_bytes();
        let result = digest(input);
        let result_var = sha384_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 48] = [
            0x33, 0x91, 0xfd, 0xdd, 0xfc, 0x8d, 0xc7, 0x39, 0x37, 0x07, 0xa6, 0x5b, 0x1b, 0x47,
            0x09, 0x39, 0x7c, 0xf8, 0xb1, 0xd1, 0x62, 0xaf, 0x05, 0xab, 0xfe, 0x8f, 0x45, 0x0d,
            0xe5, 0xf3, 0x6b, 0xc6, 0xb0, 0x45, 0x5a, 0x85, 0x20, 0xbc, 0x4e, 0x6f, 0x5f, 0xe9,
            0x5b, 0x1f, 0xe3, 0xc8, 0x45, 0x2b,
        ];

        println(f"result {result}");
        println(f"expected {expected}");
        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }

    #[test]
    fn test_two_block_msg() {
        let input = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
            .as_bytes();
        let result = digest(input);
        let result_var = sha384_var(BoundedVec::<u8, 256>::from_array(input));

        let expected: [u8; 48] = [
            0x09, 0x33, 0x0c, 0x33, 0xf7, 0x11, 0x47, 0xe8, 0x3d, 0x19, 0x2f, 0xc7, 0x82, 0xcd,
            0x1b, 0x47, 0x53, 0x11, 0x1b, 0x17, 0x3b, 0x3b, 0x05, 0xd2, 0x2f, 0xa0, 0x80, 0x86,
            0xe3, 0xb0, 0xf7, 0x12, 0xfc, 0xc7, 0xc7, 0x1a, 0x55, 0x7e, 0x2d, 0xb9, 0x66, 0xc3,
            0xe9, 0xfa, 0x91, 0x74, 0x60, 0x39,
        ];

        assert_eq(result, expected);
        assert_eq(result_var, expected);
    }
}
