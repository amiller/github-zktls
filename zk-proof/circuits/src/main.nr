// ZK GitHub Attestation Verifier with Full Certificate Chain Verification
// Verifies: Sigstore Intermediate (P-384) -> Leaf Cert (P-256) -> Attestation
//
// PUBLIC INPUT PACKING: This variant packs 84 byte-level public inputs into
// 5 Field elements to reduce on-chain verification gas (~100K savings).

use sha256::sha256_var;
use sha512::sha384;
use std::ecdsa_secp256r1;
use bignum::bignum::BigNum;
use bignum::fields::secp384r1Fq::Secp384r1_Fq;
use bignum::fields::secp384r1Fr::Secp384r1_Fr;
use ecdsa::ecdsa::verify_secp384r1_ecdsa;

// Constants
global MAX_PAE_LENGTH: u32 = 2048;
global MAX_TBS_LENGTH: u32 = 1800;
global MAX_REPO_LENGTH: u32 = 64;

// Sigstore Intermediate Certificate P-384 Public Key (valid until Oct 2031)
global SIGSTORE_INTERMEDIATE_PUBKEY_X: [u8; 48] = [
    0xf1, 0x15, 0x52, 0xff, 0x2b, 0x07, 0xf8, 0xd3, 0xaf, 0xb8, 0x36, 0x72,
    0x3c, 0x86, 0x6d, 0x8a, 0x58, 0x14, 0x17, 0xd3, 0x65, 0x6a, 0xb6, 0x29,
    0x01, 0xdf, 0x47, 0x3f, 0x5b, 0xc1, 0x04, 0x7d, 0x54, 0xe4, 0x25, 0x7b,
    0xec, 0xb4, 0x92, 0xee, 0xcd, 0x19, 0x88, 0x7e, 0x27, 0x13, 0xb1, 0xef
];

global SIGSTORE_INTERMEDIATE_PUBKEY_Y: [u8; 48] = [
    0xee, 0x9b, 0x52, 0xe8, 0xbb, 0xef, 0x47, 0xf4, 0x93, 0x93, 0xbf, 0x7c,
    0x2d, 0x58, 0x0c, 0xcc, 0xb9, 0x49, 0xe0, 0x77, 0x88, 0x7c, 0x5d, 0xed,
    0x1d, 0x26, 0x9e, 0xc4, 0xb7, 0x18, 0xa5, 0x20, 0x12, 0xaf, 0x59, 0x12,
    0xd0, 0xdf, 0xd1, 0x80, 0x12, 0x73, 0xff, 0xd8, 0xd6, 0x0a, 0x25, 0xe7
];

// OIDC extension OID prefix: 1.3.6.1.4.1.57264.1 (encoded as DER)
global OIDC_OID_PREFIX: [u8; 9] = [0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xbf, 0x30, 0x01];

fn main(
    // === Private Inputs (witness) ===
    pae_message: [u8; MAX_PAE_LENGTH],
    pae_message_len: u32,
    leaf_signature: [u8; 64],
    leaf_tbs: [u8; MAX_TBS_LENGTH],
    leaf_tbs_len: u32,
    intermediate_signature_r: [u8; 48],
    intermediate_signature_s: [u8; 48],
    leaf_pubkey_offset: u32,
    commit_oid_offset: u32,
    repo_oid_offset: u32,
    repo_name: [u8; MAX_REPO_LENGTH],
    repo_name_len: u32,
    artifact_hash_offset: u32,

    // Byte arrays (private witness -- were pub before packing)
    artifact_hash: [u8; 32],
    repo_hash: [u8; 32],
    commit_sha: [u8; 20],

    // === Public Inputs (5 packed Fields instead of 84 bytes) ===
    artifact_hash_hi: pub Field, // bytes 0..16 big-endian
    artifact_hash_lo: pub Field, // bytes 16..32 big-endian
    repo_hash_hi: pub Field,
    repo_hash_lo: pub Field,
    commit_sha_packed: pub Field, // 20 bytes as single field
) {
    // 0. Verify packed public inputs match witness byte arrays
    assert(artifact_hash_hi == pack_be_16(artifact_hash, 0), "artifact_hash_hi mismatch");
    assert(artifact_hash_lo == pack_be_16(artifact_hash, 16), "artifact_hash_lo mismatch");
    assert(repo_hash_hi == pack_be_16(repo_hash, 0), "repo_hash_hi mismatch");
    assert(repo_hash_lo == pack_be_16(repo_hash, 16), "repo_hash_lo mismatch");
    assert(commit_sha_packed == pack_be_n(commit_sha), "commit_sha mismatch");

    // 1. Verify intermediate's P-384 signature over leaf certificate TBS
    let leaf_tbs_vec = BoundedVec::from_parts_unchecked(leaf_tbs, leaf_tbs_len);
    let leaf_tbs_hash: [u8; 48] = sha384::sha384_var(leaf_tbs_vec);
    let valid_cert_chain = verify_p384_signature(
        SIGSTORE_INTERMEDIATE_PUBKEY_X,
        SIGSTORE_INTERMEDIATE_PUBKEY_Y,
        intermediate_signature_r,
        intermediate_signature_s,
        leaf_tbs_hash
    );
    assert(valid_cert_chain, "Certificate chain verification failed: leaf not signed by Sigstore intermediate");

    // 2. Extract leaf's P-256 public key from TBS
    let (leaf_pubkey_x, leaf_pubkey_y) = extract_p256_pubkey(leaf_tbs, leaf_pubkey_offset);

    // 3. Verify leaf's P-256 signature over PAE message
    let pae_hash = sha256_var(pae_message, pae_message_len as u64);
    let valid_leaf = ecdsa_secp256r1::verify_signature(
        leaf_pubkey_x,
        leaf_pubkey_y,
        leaf_signature,
        pae_hash
    );
    assert(valid_leaf, "Leaf signature verification failed");

    // 4. Extract and verify commit SHA from certificate OIDC extension
    verify_commit_sha(leaf_tbs, leaf_tbs_len, commit_oid_offset, commit_sha);

    // 5. Extract and verify repository from certificate OIDC extension
    verify_repo_hash(leaf_tbs, leaf_tbs_len, repo_oid_offset, repo_name, repo_name_len, repo_hash);

    // 6. Verify artifact hash in PAE payload
    verify_artifact_hash(pae_message, pae_message_len, artifact_hash_offset, artifact_hash);
}

// Pack 16 bytes from a 32-byte array starting at offset into a Field (big-endian)
fn pack_be_16(bytes: [u8; 32], offset: u32) -> Field {
    let mut r: Field = 0;
    for i in 0..16 {
        r = r * 256 + bytes[offset + i] as Field;
    }
    r
}

// Pack N bytes into a Field (big-endian)
fn pack_be_n<let N: u32>(bytes: [u8; N]) -> Field {
    let mut r: Field = 0;
    for i in 0..N {
        r = r * 256 + bytes[i] as Field;
    }
    r
}

fn verify_p384_signature(
    pubkey_x: [u8; 48], pubkey_y: [u8; 48],
    sig_r: [u8; 48], sig_s: [u8; 48],
    msg_hash: [u8; 48]
) -> bool {
    let pubkey_x_bn: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(pubkey_x);
    let pubkey_y_bn: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(pubkey_y);
    let sig_r_bn: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(sig_r);
    let sig_s_bn: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(sig_s);
    verify_secp384r1_ecdsa(pubkey_x_bn, pubkey_y_bn, msg_hash, (sig_r_bn, sig_s_bn))
}

fn extract_p256_pubkey(tbs: [u8; MAX_TBS_LENGTH], offset: u32) -> ([u8; 32], [u8; 32]) {
    assert(tbs[offset] == 0x04, "Expected uncompressed point prefix 0x04");
    let mut pubkey_x: [u8; 32] = [0; 32];
    let mut pubkey_y: [u8; 32] = [0; 32];
    for i in 0..32 {
        pubkey_x[i] = tbs[offset + 1 + i];
        pubkey_y[i] = tbs[offset + 33 + i];
    }
    (pubkey_x, pubkey_y)
}

fn verify_commit_sha(
    cert_tbs: [u8; MAX_TBS_LENGTH], cert_tbs_len: u32,
    oid_offset: u32, expected_commit: [u8; 20]
) {
    assert(oid_offset + 60 < cert_tbs_len, "commit OID offset out of bounds");
    for i in 0..9 {
        assert(cert_tbs[oid_offset + i] == OIDC_OID_PREFIX[i], "Invalid OIDC OID prefix for commit");
    }
    assert(cert_tbs[oid_offset + 9] == 0x03, "Expected OID .3 for commit SHA");
    let utf8_offset = find_utf8_string(cert_tbs, oid_offset + 10, 20);
    let len = cert_tbs[utf8_offset + 1];
    assert(len == 40, "Commit SHA should be 40 hex chars");
    for i in 0..20 {
        let high_char = cert_tbs[utf8_offset + 2 + i * 2];
        let low_char = cert_tbs[utf8_offset + 2 + i * 2 + 1];
        let byte = hex_char_to_nibble(high_char) * 16 + hex_char_to_nibble(low_char);
        assert(byte == expected_commit[i], "Commit SHA mismatch");
    }
}

fn verify_repo_hash(
    cert_tbs: [u8; MAX_TBS_LENGTH], cert_tbs_len: u32,
    oid_offset: u32, repo_name: [u8; MAX_REPO_LENGTH],
    repo_name_len: u32, expected_hash: [u8; 32]
) {
    assert(oid_offset + 20 + repo_name_len < cert_tbs_len, "repo OID offset out of bounds");
    for i in 0..9 {
        assert(cert_tbs[oid_offset + i] == OIDC_OID_PREFIX[i], "Invalid OIDC OID prefix for repo");
    }
    assert(cert_tbs[oid_offset + 9] == 0x05, "Expected OID .5 for repository");
    let utf8_offset = find_utf8_string(cert_tbs, oid_offset + 10, 20);
    let len = cert_tbs[utf8_offset + 1] as u32;
    assert(len == repo_name_len, "Repo name length mismatch");
    for i in 0..MAX_REPO_LENGTH {
        if i < repo_name_len {
            assert(cert_tbs[utf8_offset + 2 + i] == repo_name[i], "Repo name byte mismatch");
        }
    }
    let computed_hash = sha256_var(repo_name, repo_name_len as u64);
    for i in 0..32 {
        assert(computed_hash[i] == expected_hash[i], "Repo hash mismatch");
    }
}

fn verify_artifact_hash(
    pae_message: [u8; MAX_PAE_LENGTH], pae_message_len: u32,
    hash_offset: u32, expected_hash: [u8; 32]
) {
    assert(hash_offset + 64 <= pae_message_len, "artifact hash offset out of bounds");
    for i in 0..32 {
        let high_char = pae_message[hash_offset + i * 2];
        let low_char = pae_message[hash_offset + i * 2 + 1];
        let byte = hex_char_to_nibble(high_char) * 16 + hex_char_to_nibble(low_char);
        assert(byte == expected_hash[i], "Artifact hash mismatch");
    }
}

fn find_utf8_string(data: [u8; MAX_TBS_LENGTH], start: u32, max_search: u32) -> u32 {
    let mut result = start;
    let mut found = false;
    for i in 0..20 {
        if (i < max_search) & !found {
            let idx = start + i;
            if (data[idx] == 0x04) | (data[idx] == 0x0c) | (data[idx] == 0x16) {
                result = idx;
                found = true;
            }
        }
    }
    result
}

fn hex_char_to_nibble(c: u8) -> u8 {
    if (c >= 48) & (c <= 57) {
        c - 48
    } else if (c >= 97) & (c <= 102) {
        c - 87
    } else if (c >= 65) & (c <= 70) {
        c - 55
    } else {
        assert(false, "Invalid hex char");
        0
    }
}
