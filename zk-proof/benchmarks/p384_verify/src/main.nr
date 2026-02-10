use bignum::bignum::BigNum;
use bignum::fields::secp384r1Fq::Secp384r1_Fq;
use bignum::fields::secp384r1Fr::Secp384r1_Fr;
use ecdsa::ecdsa::verify_secp384r1_ecdsa;

fn main(
    pubkey_x: [u8; 48],
    pubkey_y: [u8; 48],
    sig_r: [u8; 48],
    sig_s: [u8; 48],
    msg_hash: pub [u8; 48],
) {
    let pubkey_x_bn: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(pubkey_x);
    let pubkey_y_bn: Secp384r1_Fq = Secp384r1_Fq::from_be_bytes(pubkey_y);
    let sig_r_bn: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(sig_r);
    let sig_s_bn: Secp384r1_Fr = Secp384r1_Fr::from_be_bytes(sig_s);
    let valid = verify_secp384r1_ecdsa(pubkey_x_bn, pubkey_y_bn, msg_hash, (sig_r_bn, sig_s_bn));
    assert(valid);
}
