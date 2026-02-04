use bigcurve::BigCurve;
use bigcurve::curves::brainpoolP192r1::{BrainpoolP192r1, BrainpoolP192r1_Fq, BrainpoolP192r1_Fr};
use bigcurve::curves::brainpoolP192t1::{BrainpoolP192t1, BrainpoolP192t1_Fq, BrainpoolP192t1_Fr};
use bigcurve::curves::brainpoolP224r1::{BrainpoolP224r1, BrainpoolP224r1_Fq, BrainpoolP224r1_Fr};
use bigcurve::curves::brainpoolP224t1::{BrainpoolP224t1, BrainpoolP224t1_Fq, BrainpoolP224t1_Fr};
use bigcurve::curves::brainpoolP256r1::{BrainpoolP256r1, BrainpoolP256r1_Fq, BrainpoolP256r1_Fr};
use bigcurve::curves::brainpoolP256t1::{BrainpoolP256t1, BrainpoolP256t1_Fq, BrainpoolP256t1_Fr};
use bigcurve::curves::brainpoolP384r1::{BrainpoolP384r1, BrainpoolP384r1_Fq, BrainpoolP384r1_Fr};
use bigcurve::curves::brainpoolP384t1::{BrainpoolP384t1, BrainpoolP384t1_Fq, BrainpoolP384t1_Fr};
use bigcurve::curves::brainpoolP512r1::{BrainpoolP512r1, BrainpoolP512r1_Fq, BrainpoolP512r1_Fr};
use bigcurve::curves::brainpoolP512t1::{BrainpoolP512t1, BrainpoolP512t1_Fq, BrainpoolP512t1_Fr};
use bigcurve::curves::secp192r1::{Secp192r1, Secp192r1_Fq, Secp192r1_Fr};
use bigcurve::curves::secp224r1::{Secp224r1, Secp224r1_Fq, Secp224r1_Fr};
use bigcurve::curves::secp256r1::{Secp256r1, Secp256r1_Fq, Secp256r1_Fr};
use bigcurve::curves::secp384r1::{Secp384r1, Secp384r1_Fq, Secp384r1_Fr};
use bigcurve::curves::secp521r1::{Secp521r1, Secp521r1_Fq, Secp521r1_Fr};
use bigcurve::scalar_field::ScalarField;
use bignum::BigNum;
use sha256::sha256_var;

// https://github.com/madztheo/noir-ecdsa/blob/main/lib/src/secp384r1.nr
pub fn verify_ecdsa<let HASH_BYTE_SIZE: u32, let SCALAR_SLICES: u32, Fq, Fr, Curve>(
    public_key_x: Fq,
    public_key_y: Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Fr, Fr),
) -> bool
where
    Fr: BigNum,
    Fr: std::convert::From<Field>,
    Fr: std::cmp::Ord,
    Fq: BigNum,
    Curve: BigCurve<Fq>,
{
    // 1. Unpack the signature (r, s)
    let (r, s) = signature;

    // 2. Validate that s is in canonical form (s <= n/2) to prevent signature malleability
    // i.e. you could have two valid signatures (r, s) and (r, n - s) from one signature (r, s)
    let n = Fr::modulus();
    // Note: with udiv the result of the unconstrained division is already constrained so need for further checks
    let n_half = n.udiv(Fr::from(2));
    assert(s <= n_half, "Signature s value is not in canonical form");

    // 3. Pad the message digest to number of bytes of Fr and convert to a BigNum
    let mut formatted_message_digest = Fr::zero().to_le_bytes();
    let mut startIndex = 0;

    if HASH_BYTE_SIZE < formatted_message_digest.len() {
        startIndex = formatted_message_digest.len() - HASH_BYTE_SIZE;
    }
    for i in startIndex..formatted_message_digest.len() {
        formatted_message_digest[i] = message_digest[i - startIndex];
    }
    let e: Fr = Fr::from_be_bytes(formatted_message_digest);

    // 4. Compute w = s^-1 mod n
    //Safety: the inverse is computed here unconstrained but we make sure
    // the inverse is valid by checking that s * w == 1 the line below
    let w = unsafe { s.__invmod() };
    // Check that s is the inverse of w since the previous line is unconstrained
    assert(s * w == Fr::one());

    // 5. Compute u1 = ew mod n and u2 = rw mod n
    let u_1: ScalarField<SCALAR_SLICES> = ScalarField::from_bignum(e * w);
    let u_2: ScalarField<SCALAR_SLICES> = ScalarField::from_bignum(r * w);

    // Convert public key to jacobian coordinates
    let public_key = Curve::from_coordinates(public_key_x, public_key_y, false);
    public_key.validate_on_curve();

    let gen = Curve::one();

    // 6. Compute the point R = u1G + u2Q
    let r_point = Curve::evaluate_linear_expression([gen, public_key], [u_1, u_2], []);

    let r_point_x = r_point.x();
    let r_point_x_as_fr: Fr = Fr::from_limbs(r_point_x.get_limbs());
    // 7. The signature is valid if r = R.x (mod n)
    // Need to have them in the same field to do the comparison
    r_point_x_as_fr == r
}

pub fn verify_secp521r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: Secp521r1_Fq,
    public_key_y: Secp521r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Secp521r1_Fr, Secp521r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 131, Secp521r1_Fq, Secp521r1_Fr, Secp521r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_secp384r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: Secp384r1_Fq,
    public_key_y: Secp384r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Secp384r1_Fr, Secp384r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 97, Secp384r1_Fq, Secp384r1_Fr, Secp384r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_secp256r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: Secp256r1_Fq,
    public_key_y: Secp256r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Secp256r1_Fr, Secp256r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 65, Secp256r1_Fq, Secp256r1_Fr, Secp256r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_secp224r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: Secp224r1_Fq,
    public_key_y: Secp224r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Secp224r1_Fr, Secp224r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 57, Secp224r1_Fq, Secp224r1_Fr, Secp224r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_secp192r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: Secp192r1_Fq,
    public_key_y: Secp192r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (Secp192r1_Fr, Secp192r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 49, Secp192r1_Fq, Secp192r1_Fr, Secp192r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp192r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP192r1_Fq,
    public_key_y: BrainpoolP192r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP192r1_Fr, BrainpoolP192r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 49, BrainpoolP192r1_Fq, BrainpoolP192r1_Fr, BrainpoolP192r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp192t1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP192t1_Fq,
    public_key_y: BrainpoolP192t1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP192t1_Fr, BrainpoolP192t1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 49, BrainpoolP192t1_Fq, BrainpoolP192t1_Fr, BrainpoolP192t1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp224r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP224r1_Fq,
    public_key_y: BrainpoolP224r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP224r1_Fr, BrainpoolP224r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 57, BrainpoolP224r1_Fq, BrainpoolP224r1_Fr, BrainpoolP224r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp224t1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP224t1_Fq,
    public_key_y: BrainpoolP224t1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP224t1_Fr, BrainpoolP224t1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 57, BrainpoolP224t1_Fq, BrainpoolP224t1_Fr, BrainpoolP224t1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp256r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP256r1_Fq,
    public_key_y: BrainpoolP256r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP256r1_Fr, BrainpoolP256r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 65, BrainpoolP256r1_Fq, BrainpoolP256r1_Fr, BrainpoolP256r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp256t1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP256t1_Fq,
    public_key_y: BrainpoolP256t1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP256t1_Fr, BrainpoolP256t1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 65, BrainpoolP256t1_Fq, BrainpoolP256t1_Fr, BrainpoolP256t1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp384r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP384r1_Fq,
    public_key_y: BrainpoolP384r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP384r1_Fr, BrainpoolP384r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 97, BrainpoolP384r1_Fq, BrainpoolP384r1_Fr, BrainpoolP384r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp384t1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP384t1_Fq,
    public_key_y: BrainpoolP384t1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP384t1_Fr, BrainpoolP384t1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 97, BrainpoolP384t1_Fq, BrainpoolP384t1_Fr, BrainpoolP384t1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp512r1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP512r1_Fq,
    public_key_y: BrainpoolP512r1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP512r1_Fr, BrainpoolP512r1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 129, BrainpoolP512r1_Fq, BrainpoolP512r1_Fr, BrainpoolP512r1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

pub fn verify_brainpoolp512t1_ecdsa<let HASH_BYTE_SIZE: u32>(
    public_key_x: BrainpoolP512t1_Fq,
    public_key_y: BrainpoolP512t1_Fq,
    message_digest: [u8; HASH_BYTE_SIZE],
    signature: (BrainpoolP512t1_Fr, BrainpoolP512t1_Fr),
) -> bool {
    verify_ecdsa::<HASH_BYTE_SIZE, 129, BrainpoolP512t1_Fq, BrainpoolP512t1_Fr, BrainpoolP512t1>(
        public_key_x,
        public_key_y,
        message_digest,
        signature,
    )
}

#[test]
fn test_secp521r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );
    let r: Secp521r1_Fr = Secp521r1_Fr::from_limbs([
        0x5d54ec424d96736a8eb7ab6b38d908,
        0x652b2107a280804afad6f3d2cc0050,
        0xed0e5a379f9fb054d066eb356d254c,
        0xfc86bb58b30a527e65c6f834a6d3db,
        0x4d2cade92f,
    ]);
    let s: Secp521r1_Fr = Secp521r1_Fr::from_limbs([
        0xbbbde07f01798860628f5af9dd2a64,
        0x5416a9927335c1e6aae0cf33d44413,
        0xc05b8c91b0f63441f63929b0d065d4,
        0x35905117e2c37f88dcffbd84648d9f,
        0x8412499ba5,
    ]);
    let public_key_x: Secp521r1_Fq = Secp521r1_Fq::from_limbs([
        0xe976cfcef3735cd6b59ac2014c4ae3,
        0xbc1c4e1989e7b94f353e9194948ed0,
        0xdea95c2502cfe36a3479a18960cf40,
        0x69b79211e183033c2f123720e96888,
        0x191ceb966f3,
    ]);
    let public_key_y: Secp521r1_Fq = Secp521r1_Fq::from_limbs([
        0xe10762c5d5f93c2754f5172fd76a6a,
        0x4d432eaa4382eaaace7018ff2268b,
        0x5e8326529e8b8bcf701c5d29bf70d6,
        0xb494cf3fb13e60d4619a41c13775cd,
        0x1c03b12ef33,
    ]);
    assert(verify_secp521r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_secp384r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );
    let r: Secp384r1_Fr = Secp384r1_Fr::from_limbs([
        0xeb06adc631cd09d17ed3268f65e288,
        0x4102680df5a59b6fc9f8f38cd01016,
        0x272042bb400a185ba04fefaa7c05ce,
        0x680dc4,
    ]);
    let s: Secp384r1_Fr = Secp384r1_Fr::from_limbs([
        0x711084a23ae842fc0e6702c3009784,
        0xe17e64a3c451466091c4c1aae7550f,
        0x017a18c55fc11347e0f27fa8fdb958,
        0x32ec1b,
    ]);
    let public_key_x: Secp384r1_Fq = Secp384r1_Fq::from_limbs([
        0x4bb414953ec1391fdbc6ea75e0d61a,
        0xfed1f2c9f9ac404d4bf5c0b267cddb,
        0xd1031dd17188527bc28ade5c97d23c,
        0x41b3d3,
    ]);
    let public_key_y: Secp384r1_Fq = Secp384r1_Fq::from_limbs([
        0x23db4726c61ec970c07ff770a2b380,
        0x3270662d9105998b8e26e9575147da,
        0x33e912de6612af790c627629f33de0,
        0x4b834d,
    ]);
    assert(verify_secp384r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_secp256r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );
    let r: Secp256r1_Fr = Secp256r1_Fr::from_limbs([
        0x6e6dd8df9cec8c31892d01e14318fb,
        0x3109c73f335657be981f6387c44d3c,
        0x8e0e,
    ]);
    let s: Secp256r1_Fr = Secp256r1_Fr::from_limbs([
        0x262ed99e46e6577a71a75b1d5c7f4a,
        0xcefc34f4b68aa019eda376372f2e76,
        0x2c2d,
    ]);
    let public_key_x: Secp256r1_Fq = Secp256r1_Fq::from_limbs([
        0xd54378ffd74c0a0692ea56dc91e14a,
        0xa683ef4c166c55cfb8d135863fc8f9,
        0xaa1d,
    ]);
    let public_key_y: Secp256r1_Fq = Secp256r1_Fq::from_limbs([
        0x6b6c3604db3440d3dc4ee95a24f0f0,
        0xc4eae722e511eeb583122a0f6ab255,
        0x4b36,
    ]);
    assert(verify_secp256r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_brainpoolp256r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );

    let r: BrainpoolP256r1_Fr = BrainpoolP256r1_Fr::from_limbs([
        0xb5dbab781aac0d3b9f3363bee44893,
        0xc14f36af7f013afc631f5ea41ebaea,
        0x70a,
    ]);

    let s: BrainpoolP256r1_Fr = BrainpoolP256r1_Fr::from_limbs([
        0x829cb95b4418f1b0d1acaa177bb8fb,
        0xf536836f61755973c25ba72ec4ae6c,
        0x3e5f,
    ]);

    let public_key_x: BrainpoolP256r1_Fq = BrainpoolP256r1_Fq::from_limbs([
        0x44c2c2f4362c32db014e2d53f81184,
        0x73c6514a204b38fccc53e73cee10c8,
        0x9c26,
    ]);

    let public_key_y: BrainpoolP256r1_Fq = BrainpoolP256r1_Fq::from_limbs([
        0x2d297c0cd741b36f47b3305a29536c,
        0xb22cccc873db46c4b99f8056ab3afc,
        0x895e,
    ]);

    assert(verify_brainpoolp256r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_brainpoolp384r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );

    let r: BrainpoolP384r1_Fr = BrainpoolP384r1_Fr::from_limbs([
        0x704089dce05bcb6ce0a9094429d30b,
        0x2707b5a5e61d766b510af6592cc6f0,
        0x7a6a11cf913fea3ab0bb8860ffc5e6,
        0x71dcf0,
    ]);

    let s: BrainpoolP384r1_Fr = BrainpoolP384r1_Fr::from_limbs([
        583843873855621341364149722400139931,
        1212337095275413398733606627875066102,
        1030624331378512455916955161925548059,
        549252,
    ]);

    let public_key_x: BrainpoolP384r1_Fq = BrainpoolP384r1_Fq::from_limbs([
        0x1003f8578f9d68939e218725376b3c,
        0xa3fb7a2aea32dd5fbe8b8834b3bfcd,
        0x4d6cb36e8aa358b5d4a260fccbc385,
        0x3b358f,
    ]);

    let public_key_y: BrainpoolP384r1_Fq = BrainpoolP384r1_Fq::from_limbs([
        0xdd2e4e62d7c2fa35b26d4bf91af381,
        0x82b9c682c1b8f6345186c166f96a3f,
        0x4295bcb724597af1820d75d3f5c232,
        0x1c529b,
    ]);

    assert(verify_brainpoolp384r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_brainpoolp384t1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );

    let r: BrainpoolP384t1_Fr = BrainpoolP384t1_Fr::from_limbs([
        0x71b474f6230c6b1ae4464bbb53fb0,
        0x4c547f4cea0ecda60d4625ae339e17,
        0x91a861c31aeb53350d4361e3838ec3,
        0x176af9,
    ]);

    let s: BrainpoolP384t1_Fr = BrainpoolP384t1_Fr::from_limbs([
        951208539839936891913486938762574601,
        297886132094751777111077343000766584,
        306609557383715756842695472429272255,
        415919,
    ]);

    let public_key_x: BrainpoolP384t1_Fq = BrainpoolP384t1_Fq::from_limbs([
        0x7c9f63fe3b28c5b715596bcb59dbb1,
        0x7eb281300e03d8026c75b6645f323c,
        0xa1960291325d182311b1fd440c69bf,
        0x737bf1,
    ]);

    let public_key_y: BrainpoolP384t1_Fq = BrainpoolP384t1_Fq::from_limbs([
        0xd4e4c1d55ebbccf88a58deefbace58,
        0x3cdfe92bc0d8d177e6bd8cf53b49c4,
        0xd853d7f2198671df96ffc8aada696d,
        0x1c679f,
    ]);

    assert(verify_brainpoolp384t1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_brainpoolp512r1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );

    let r: BrainpoolP512r1_Fr = BrainpoolP512r1_Fr::from_limbs([
        0x7a42ee3ff773930fd5a75a5f0f8f44,
        0xe08e9627534dd4b08b51cd50e1ea54,
        0x4b3b4eb9d0c140412ccc7588387e0c,
        0x667c21fe6cdf7a38e9cb665b45cd31,
        0x9c3b9f11,
    ]);

    let s: BrainpoolP512r1_Fr = BrainpoolP512r1_Fr::from_limbs([
        528407777185039668069881093702786072,
        163725918895628368670822680709138314,
        359709166105429011205054976949200043,
        1091733467074042237131228987782423193,
        27126492,
    ]);

    let public_key_x: BrainpoolP512r1_Fq = BrainpoolP512r1_Fq::from_limbs([
        0xa84c943bd583159d60859f2cfa0161,
        0x8f6771c6e3495ce6ddad026936d7a6,
        0xdeeca2efdbad740deff518494f590a,
        0x7d4c0f9655b0e3a0fd68d0edaef401,
        0x6c549ffa,
    ]);

    let public_key_y: BrainpoolP512r1_Fq = BrainpoolP512r1_Fq::from_limbs([
        0x82417399c1673ba45056d27d3e2d0,
        0x66a253b74a0ffa6829acf5ce3a9c8e,
        0xb92617dff6948f4aa6d9b597351d4e,
        0x7509a0b89cd0b7efce6622cedf2796,
        0x840299fc,
    ]);

    assert(verify_brainpoolp512r1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}

#[test]
fn test_brainpoolp512t1_signature_verification() {
    let sha256_hash: [u8; 32] = sha256_var("Hello World! This is Noir-ECDSA".as_bytes(), 31);
    assert_eq(
        sha256_hash,
        [
            42, 204, 207, 15, 192, 246, 143, 215, 180, 110, 75, 247, 21, 126, 103, 225, 251, 180,
            86, 221, 251, 68, 216, 63, 17, 236, 32, 223, 169, 198, 9, 98,
        ],
    );

    let r: BrainpoolP512t1_Fr = BrainpoolP512t1_Fr::from_limbs([
        0x7746cefc148255fc0469c6c7458167,
        0x9632ecde268968a1f6f171e9ee9cae,
        0x612d682feec3c244e896cec770ecd2,
        0x74ad1958977398b94657a3447d521,
        0x9d977546,
    ]);

    let s: BrainpoolP512t1_Fr = BrainpoolP512t1_Fr::from_limbs([
        398311017405186900405056391525974158,
        186954885950299626652744917756210209,
        833991342457265350994683408517212481,
        502874513420693716557925105329695155,
        374444511,
    ]);

    let public_key_x: BrainpoolP512t1_Fq = BrainpoolP512t1_Fq::from_limbs([
        0xdbfb0d9259dcbb574c17a5fd0907d8,
        0x524e5295868b24e8816453980ba46,
        0x1202cdb3acccb9f728cab6032e30a9,
        0xe30c3d06e2ba4dcb1377c310967911,
        0x72408dda,
    ]);

    let public_key_y: BrainpoolP512t1_Fq = BrainpoolP512t1_Fq::from_limbs([
        0x270944181de6fd04bf119df6d58d54,
        0x438cb67ac1a5f3dfac1a605a567acf,
        0xae972b88bd469b0eacff28204d35be,
        0xc3d429a82ec2c7aebc2d6c1026aa35,
        0x59143171,
    ]);

    assert(verify_brainpoolp512t1_ecdsa(public_key_x, public_key_y, sha256_hash, (r, s)));
}
