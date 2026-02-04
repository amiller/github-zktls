// ZK GitHub Attestation Verifier
// Verifies Sigstore attestations from GitHub Actions in ZK

use sha256::sha256_var;
use sha512::sha384::sha384_var;
use std::ecdsa_secp256r1;
use bignum::bignum::BigNum;
use bignum::fields::secp384r1Fq::Secp384r1_Fq;
use bignum::fields::secp384r1Fr::Secp384r1_Fr;
use ecdsa::ecdsa::verify_secp384r1_ecdsa;

// Constants
global MAX_PAE_LENGTH: u32 = 2048;
global MAX_TBS_LENGTH: u32 = 1800;  // Sigstore certs have many OIDC extensions (~1700 bytes)

// Fulcio Intermediate CA Public Key (P-384)
// Valid: Apr 2022 - Oct 2031
// From: https://fulcio.sigstore.dev/api/v2/trustBundle
global FULCIO_INTERMEDIATE_X: [u8; 48] = [
    241, 21, 82, 255, 43, 7, 248, 211, 175, 184, 54, 114, 60, 134, 109, 138,
    88, 20, 23, 211, 101, 106, 182, 41, 1, 223, 71, 63, 91, 193, 4, 125,
    84, 228, 37, 123, 236, 180, 146, 238, 205, 25, 136, 126, 39, 19, 177, 239
];

global FULCIO_INTERMEDIATE_Y: [u8; 48] = [
    238, 155, 82, 232, 187, 239, 71, 244, 147, 147, 191, 124, 45, 88, 12, 204,
    185, 73, 224, 119, 136, 124, 93, 237, 29, 38, 158, 196, 183, 24, 165, 32,
    18, 175, 89, 18, 208, 223, 209, 128, 18, 115, 255, 216, 214, 10, 37, 231
];

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

    // Certificate TBS (To Be Signed) - what Fulcio signed
    cert_tbs: [u8; MAX_TBS_LENGTH],
    cert_tbs_len: u32,

    // Issuer (Fulcio) signature over cert TBS (P-384, r||s)
    issuer_sig_r: [u8; 48],
    issuer_sig_s: [u8; 48],

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

    // 3. Hash the certificate TBS with SHA-384
    let tbs_vec: BoundedVec<u8, MAX_TBS_LENGTH> = BoundedVec::from_parts_unchecked(cert_tbs, cert_tbs_len);
    let tbs_hash: [u8; 48] = sha384_var(tbs_vec);

    // 4. Verify certificate chain: Fulcio intermediate signed the leaf cert (P-384)
    let issuer_pubkey_x: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(FULCIO_INTERMEDIATE_X);
    let issuer_pubkey_y: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(FULCIO_INTERMEDIATE_Y);
    let sig_r: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(issuer_sig_r);
    let sig_s: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(issuer_sig_s);

    let valid_cert = verify_secp384r1_ecdsa(
        issuer_pubkey_x,
        issuer_pubkey_y,
        tbs_hash,
        (sig_r, sig_s)
    );
    assert(valid_cert, "Certificate chain verification failed");

    // 5. TODO: Parse certificate to extract OIDC claims
    // Verify extracted repo matches repo_hash, commit matches commit_sha

    // 6. TODO: Parse PAE payload to verify artifact_hash

    // Suppress unused warnings for now
    let _ = artifact_hash[0];
    let _ = repo_hash[0];
    let _ = commit_sha[0];
}
