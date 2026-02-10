use sha256::sha256_var;

fn main(data: [u8; 2048], data_len: u32, expected: pub [u8; 32]) {
    let hash = sha256_var(data, data_len as u64);
    assert(hash == expected);
}
