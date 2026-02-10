use sha512::sha384;

fn main(data: [u8; 1800], data_len: u32, expected: pub [u8; 48]) {
    let data_vec = BoundedVec::from_parts_unchecked(data, data_len);
    let hash: [u8; 48] = sha384::sha384_var(data_vec);
    assert(hash == expected);
}
