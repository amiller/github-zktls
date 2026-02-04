# noir-ecdsa

Optimized Noir library that evaluates ECDSA (Elliptic Curve Digital Signature Algorithm) signatures for multiple elliptic curves.

This library supports verification of ECDSA signatures on various elliptic curves including NIST standard curves (secp256r1, secp384r1, secp521r1) and Brainpool curves (brainpoolP256r1/t1, brainpoolP384r1/t1, brainpoolP512r1/t1).

This library uses [noir-bignum](https://github.com/noir-lang/noir-bignum) as a dependency for big number arithmetic operations as well as a slightly modified version of [noir-bigcurve](https://github.com/madztheo/noir_bigcurve) for curve operations.

## Supported Curves

### NIST Curves

- **secp256r1** (P-256): 256-bit prime field curve
- **secp384r1** (P-384): 384-bit prime field curve
- **secp521r1** (P-521): 521-bit prime field curve

### Brainpool Curves

- **brainpoolP256r1**: 256-bit Brainpool curve
- **brainpoolP256t1**: 256-bit Brainpool curve (twisted)
- **brainpoolP384r1**: 384-bit Brainpool curve
- **brainpoolP384t1**: 384-bit Brainpool curve (twisted)
- **brainpoolP512r1**: 512-bit Brainpool curve
- **brainpoolP512t1**: 512-bit Brainpool curve (twisted)

## Installation

In your `Nargo.toml` file, add the version of this library you would like to install under dependency:

```toml
[dependencies]
noir_ecdsa = { tag = "v0.2.7", git = "https://github.com/zkpassport/noir-ecdsa" }
bigcurve = {tag = "v0.9.0-1", git = "https://github.com/zkpassport/noir_bigcurve"}
```

## Usage

### Basic Usage

The library provides both a generic `verify_ecdsa` function and curve-specific convenience functions. Here are examples for each supported curve:

#### secp256r1 (P-256)

```rust
use bigcurve::curves::secp256r1::{Secp256r1_Fq, Secp256r1_Fr};
use noir_ecdsa::ecdsa::verify_secp256r1_ecdsa;


// Your message hash (typically SHA-256)
let message_hash: [u8; 32] = [/* your 32-byte hash */];

// Public key coordinates (on the secp256r1 curve)
let public_key_x: Secp256r1_Fq = /* your public key x coordinate */;
let public_key_y: Secp256r1_Fq = /* your public key y coordinate */;

// ECDSA signature (r, s)
let signature_r: Secp256r1_Fr = /* signature r component */;
let signature_s: Secp256r1_Fr = /* signature s component */;

// Verify the signature
let is_valid = verify_secp256r1_ecdsa(
    public_key_x,
    public_key_y,
    message_hash,
    (signature_r, signature_s)
);

assert(is_valid);
```

#### secp384r1 (P-384)

```rust
use bigcurve::curves::secp384r1::{Secp384r1_Fq, Secp384r1_Fr};
use noir_ecdsa::ecdsa::verify_secp384r1_ecdsa;

let message_hash: [u8; 32] = [/* your hash */];
let public_key_x: Secp384r1_Fq = /* public key x */;
let public_key_y: Secp384r1_Fq = /* public key y */;
let signature_r: Secp384r1_Fr = /* signature r */;
let signature_s: Secp384r1_Fr = /* signature s */;

let is_valid = verify_secp384r1_ecdsa(
    public_key_x,
    public_key_y,
    message_hash,
    (signature_r, signature_s)
);
```

#### secp521r1 (P-521)

```rust
use bigcurve::curves::secp521r1::{Secp521r1_Fq, Secp521r1_Fr};
use noir_ecdsa::ecdsa::verify_secp521r1_ecdsa;

let message_hash: [u8; 32] = [/* your hash */];
let public_key_x: Secp521r1_Fq = /* public key x */;
let public_key_y: Secp521r1_Fq = /* public key y */;
let signature_r: Secp521r1_Fr = /* signature r */;
let signature_s: Secp521r1_Fr = /* signature s */;

let is_valid = verify_secp521r1_ecdsa(
    public_key_x,
    public_key_y,
    message_hash,
    (signature_r, signature_s)
);
```

#### Brainpool Curves

```rust
use bigcurve::curves::brainpool::{BrainpoolP256r1_Fq, BrainpoolP256r1_Fr};
use noir_ecdsa::ecdsa::{
    verify_brainpoolp256r1_ecdsa,
    verify_brainpoolp256t1_ecdsa,
    verify_brainpoolp384r1_ecdsa,
    verify_brainpoolp384t1_ecdsa,
    verify_brainpoolp512r1_ecdsa,
    verify_brainpoolp512t1_ecdsa
};

// Example with brainpoolP256r1
let message_hash: [u8; 32] = [/* your hash */];
let public_key_x: BrainpoolP256r1_Fq = /* public key x */;
let public_key_y: BrainpoolP256r1_Fq = /* public key y */;
let signature_r: BrainpoolP256r1_Fr = /* signature r */;
let signature_s: BrainpoolP256r1_Fr = /* signature s */;

let is_valid = verify_brainpoolp256r1_ecdsa(
    public_key_x,
    public_key_y,
    message_hash,
    (signature_r, signature_s)
);
```

### Generic Usage

For advanced use cases, you can use the generic `verify_ecdsa` function:

```rust
use noir_ecdsa::ecdsa::verify_ecdsa;
use bigcurve::curves::secp256r1::{Secp256r1_Fq, Secp256r1_Fr, Secp256r1_Params};

let is_valid = verify_ecdsa::<32, 65, Secp256r1_Fq, Secp256r1_Fr, Secp256r1_Params>(
    public_key_x,
    public_key_y,
    message_hash,
    (signature_r, signature_s)
);
```

### Variable Hash Sizes

All verification functions support variable hash sizes using generics:

```rust
// For a SHA-384 hash (48 bytes)
let sha384_hash: [u8; 48] = [/* your 48-byte hash */];
// Note: you should not need to specify the hash size as it is inferred from the array size
let is_valid = verify_secp384r1_ecdsa::<48>(
    public_key_x,
    public_key_y,
    sha384_hash,
    (signature_r, signature_s)
);

// For a SHA-512 hash (64 bytes)
// Note: you should not need to specify the hash size as it is inferred from the array size
let sha512_hash: [u8; 64] = [/* your 64-byte hash */];
let is_valid = verify_secp521r1_ecdsa::<64>(
    public_key_x,
    public_key_y,
    sha512_hash,
    (signature_r, signature_s)
);
```

## Security Features

### Signature Malleability Protection

This library automatically protects against signature malleability attacks by enforcing canonical signature form. For any valid signature `(r, s)`, there could potentially be another valid signature `(r, n - s)` where `n` is the curve order. To prevent this, the library checks that `s ≤ n/2`, ensuring only one canonical form is accepted.

This assumes the signature you pass has a s value less than n/2, otherwise you will get this error: `Signature s value is not in canonical form`.
So make sure to preprocess your ECDSA signatures before passing them to the library to ensure this. You can check how we do this in TypeScript [here](https://github.com/zkpassport/zkpassport-utils/blob/4cd85a51434492bb3d8b323ce8f1321217b9407f/src/circuit-matcher.ts#L256).

## Examples

See the test functions in `src/ecdsa.nr` for complete working examples of each curve. Each test demonstrates the following:

1. Computing a SHA-256 hash of a message
2. Setting up public key coordinates and signature values
3. Verifying the signature
4. Asserting the result

To run the tests:

```bash
nargo test
```

## Algorithm Details

The ECDSA verification algorithm implemented follows the standard process:

1. **Input processing**: Split the signature into its `r` and `s` components
2. **Canonical form check**: Ensure `s ≤ n/2` to prevent malleability
3. **Hash processing**: Pad the message hash to the appropriate size and convert it to a field element
4. **Inverse computation**: Calculate `w = s^(-1) mod n`
5. **Scalar computation**: Calculate `u1 = e*w mod n` and `u2 = r*w mod n`
6. **Public key validation**: Convert the public key to a point on the curve and ensure it is on the curve
7. **Point computation**: Calculate `R = u1*G + u2*Q` using multi-scalar multiplication (MSM)
8. **Verification**: Check if `R.x ≡ r (mod n)`, the final check to ensure the signature is valid

Where:

- `e` is the message hash as a field element
- `G` is the curve generator point
- `Q` is the public key point
- `n` is the curve order

## Contributing

We welcome contributions! Please feel free to submit issues and pull requests.

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.
