use crate::formatting::msg_u8_to_u64;

global MAX_BYTES_1_BLOCK: u32 = 111;
global MAX_BYTES_2_BLOCKS: u32 = MAX_BYTES_1_BLOCK + 128;
global MAX_BYTES_3_BLOCKS: u32 = MAX_BYTES_2_BLOCKS + 128;
global MAX_BYTES_4_BLOCKS: u32 = MAX_BYTES_3_BLOCKS + 128;

#[export]
fn bench_sha512_compression(input: [u8; 128], h: [u64; 8]) -> [u64; 8] {
    let r = crate::sha512_compression(msg_u8_to_u64(input), h);
    r
}

#[export]
fn bench_sha512_1_block(input: [u8; MAX_BYTES_1_BLOCK]) -> [u8; 64] {
    crate::sha512::digest(input)
}

#[export]
fn bench_sha512_2_blocks(input: [u8; MAX_BYTES_2_BLOCKS]) -> [u8; 64] {
    crate::sha512::digest(input)
}

#[export]
fn bench_sha512_3_blocks(input: [u8; MAX_BYTES_3_BLOCKS]) -> [u8; 64] {
    crate::sha512::digest(input)
}

#[export]
fn bench_sha512_4_blocks(input: [u8; MAX_BYTES_4_BLOCKS]) -> [u8; 64] {
    crate::sha512::digest(input)
}

#[export]
fn bench_sha512_var_1_block(input: BoundedVec<u8, MAX_BYTES_1_BLOCK>) -> [u8; 64] {
    crate::sha512::sha512_var(input)
}

#[export]
fn bench_sha512_var_2_blocks(input: BoundedVec<u8, MAX_BYTES_2_BLOCKS>) -> [u8; 64] {
    crate::sha512::sha512_var(input)
}

#[export]
fn bench_sha512_var_3_blocks(input: BoundedVec<u8, MAX_BYTES_3_BLOCKS>) -> [u8; 64] {
    crate::sha512::sha512_var(input)
}

#[export]
fn bench_sha512_var_4_blocks(input: BoundedVec<u8, MAX_BYTES_4_BLOCKS>) -> [u8; 64] {
    crate::sha512::sha512_var(input)
}
