// ZK GitHub Attestation Verifier (P-256 only version)
// Verifies Sigstore attestations from GitHub Actions in ZK
// Note: P-384 cert chain verification commented out due to toolchain version issues

use sha256::sha256_var;
use std::ecdsa_secp256r1;

// Constants
global MAX_PAE_LENGTH: u32 = 2048;
global MAX_TBS_LENGTH: u32 = 1800;
global MAX_REPO_LENGTH: u32 = 64;

// OIDC extension OID prefix: 1.3.6.1.4.1.57264.1 (encoded as DER)
global OIDC_OID_PREFIX: [u8; 9] = [0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xbf, 0x30, 0x01];

fn main(
    // === Private Inputs (witness) ===

    // DSSE PAE-encoded message (padded to MAX_PAE_LENGTH)
    pae_message: [u8; MAX_PAE_LENGTH],
    pae_message_len: u32,

    // Leaf certificate ECDSA P-256 signature (concatenated r||s)
    signature: [u8; 64],

    // Leaf certificate public key (P-256)
    leaf_pubkey_x: [u8; 32],
    leaf_pubkey_y: [u8; 32],

    // Certificate TBS (To Be Signed) - for OIDC claim extraction
    cert_tbs: [u8; MAX_TBS_LENGTH],
    cert_tbs_len: u32,

    // OIDC claim extraction hints (witness-provided offsets)
    commit_oid_offset: u32,
    repo_oid_offset: u32,
    repo_name: [u8; MAX_REPO_LENGTH],
    repo_name_len: u32,

    // Offset in pae_message where artifact hash appears (as hex string)
    artifact_hash_offset: u32,

    // === Public Inputs ===
    artifact_hash: pub [u8; 32],
    repo_hash: pub [u8; 32],
    commit_sha: pub [u8; 20],
) {
    // 1. Hash the PAE message (variable length)
    let pae_hash = sha256_var(pae_message, pae_message_len as u64);

    // 2. Verify leaf signature over PAE message (P-256)
    let valid_leaf = ecdsa_secp256r1::verify_signature(
        leaf_pubkey_x,
        leaf_pubkey_y,
        signature,
        pae_hash
    );
    assert(valid_leaf, "Leaf signature verification failed");

    // 3. Extract and verify commit SHA from certificate OIDC extension
    verify_commit_sha(cert_tbs, cert_tbs_len, commit_oid_offset, commit_sha);

    // 4. Extract and verify repository from certificate OIDC extension
    verify_repo_hash(cert_tbs, cert_tbs_len, repo_oid_offset, repo_name, repo_name_len, repo_hash);

    // 5. Verify artifact hash in PAE payload
    verify_artifact_hash(pae_message, pae_message_len, artifact_hash_offset, artifact_hash);
}

// Verify the commit SHA OIDC extension (OID 1.3.6.1.4.1.57264.1.3)
fn verify_commit_sha(
    cert_tbs: [u8; MAX_TBS_LENGTH],
    cert_tbs_len: u32,
    oid_offset: u32,
    expected_commit: [u8; 20]
) {
    // Verify we're within bounds
    assert(oid_offset + 60 < cert_tbs_len, "commit OID offset out of bounds");

    // Verify OID prefix at offset
    for i in 0..9 {
        assert(cert_tbs[oid_offset + i] == OIDC_OID_PREFIX[i], "Invalid OIDC OID prefix for commit");
    }
    // Verify OID suffix is .3 (sha)
    assert(cert_tbs[oid_offset + 9] == 0x03, "Expected OID .3 for commit SHA");

    // Find UTF8String after OID
    let utf8_offset = find_utf8_string(cert_tbs, oid_offset + 10, 20);
    let len = cert_tbs[utf8_offset + 1];
    assert(len == 40, "Commit SHA should be 40 hex chars");

    // Convert 40 hex chars to 20 bytes and compare
    for i in 0..20 {
        let high_char = cert_tbs[utf8_offset + 2 + i * 2];
        let low_char = cert_tbs[utf8_offset + 2 + i * 2 + 1];
        let byte = hex_char_to_nibble(high_char) * 16 + hex_char_to_nibble(low_char);
        assert(byte == expected_commit[i], "Commit SHA mismatch");
    }
}

// Verify the repository OIDC extension (OID 1.3.6.1.4.1.57264.1.5)
fn verify_repo_hash(
    cert_tbs: [u8; MAX_TBS_LENGTH],
    cert_tbs_len: u32,
    oid_offset: u32,
    repo_name: [u8; MAX_REPO_LENGTH],
    repo_name_len: u32,
    expected_hash: [u8; 32]
) {
    // Verify we're within bounds
    assert(oid_offset + 20 + repo_name_len < cert_tbs_len, "repo OID offset out of bounds");

    // Verify OID prefix at offset
    for i in 0..9 {
        assert(cert_tbs[oid_offset + i] == OIDC_OID_PREFIX[i], "Invalid OIDC OID prefix for repo");
    }
    // Verify OID suffix is .5 (repository)
    assert(cert_tbs[oid_offset + 9] == 0x05, "Expected OID .5 for repository");

    // Find UTF8String containing repo name
    let utf8_offset = find_utf8_string(cert_tbs, oid_offset + 10, 20);
    let len = cert_tbs[utf8_offset + 1] as u32;
    assert(len == repo_name_len, "Repo name length mismatch");

    // Verify repo name matches what witness provided
    for i in 0..MAX_REPO_LENGTH {
        if i < repo_name_len {
            assert(cert_tbs[utf8_offset + 2 + i] == repo_name[i], "Repo name byte mismatch");
        }
    }

    // Hash repo name and compare with expected
    let computed_hash = sha256_var(repo_name, repo_name_len as u64);
    for i in 0..32 {
        assert(computed_hash[i] == expected_hash[i], "Repo hash mismatch");
    }
}

// Verify artifact hash appears in PAE payload
fn verify_artifact_hash(
    pae_message: [u8; MAX_PAE_LENGTH],
    pae_message_len: u32,
    hash_offset: u32,
    expected_hash: [u8; 32]
) {
    // Verify offset is within bounds
    assert(hash_offset + 64 <= pae_message_len, "artifact hash offset out of bounds");

    // Convert 64 hex chars to 32 bytes and compare
    for i in 0..32 {
        let high_char = pae_message[hash_offset + i * 2];
        let low_char = pae_message[hash_offset + i * 2 + 1];
        let byte = hex_char_to_nibble(high_char) * 16 + hex_char_to_nibble(low_char);
        assert(byte == expected_hash[i], "Artifact hash mismatch");
    }
}

// Find OCTET STRING (0x04), UTF8String (0x0c), or IA5String (0x16) within search range
fn find_utf8_string(data: [u8; MAX_TBS_LENGTH], start: u32, max_search: u32) -> u32 {
    let mut result = start;
    for i in 0..20 {
        if i < max_search {
            let idx = start + i;
            if (data[idx] == 0x04) | (data[idx] == 0x0c) | (data[idx] == 0x16) {
                result = idx;
            }
        }
    }
    result
}

// Convert hex char to nibble value
fn hex_char_to_nibble(c: u8) -> u8 {
    if (c >= 48) & (c <= 57) {  // '0'-'9'
        c - 48
    } else if (c >= 97) & (c <= 102) {  // 'a'-'f'
        c - 87
    } else if (c >= 65) & (c <= 70) {  // 'A'-'F'
        c - 55
    } else {
        assert(false, "Invalid hex char");
        0
    }
}
