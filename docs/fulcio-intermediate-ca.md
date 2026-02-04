# Fulcio Intermediate CA Public Key

Fetched from: `https://fulcio.sigstore.dev/api/v2/trustBundle`

## Certificate Details

- **Subject**: `O=sigstore.dev, CN=sigstore-intermediate`
- **Issuer**: `O=sigstore.dev, CN=sigstore` (root)
- **Valid**: Apr 13, 2022 - Oct 5, 2031
- **Key Algorithm**: ECDSA P-384 (secp384r1)
- **Signature Algorithm**: ECDSA-SHA384 (signs leaf certs)

## Public Key (P-384)

### Hex (uncompressed, 97 bytes with 04 prefix)
```
04f11552ff2b07f8d3afb836723c866d8a581417d3656ab62901df473f5bc1047d54e4257becb492eecd19887e2713b1efee9b52e8bbef47f49393bf7c2d580cccb949e077887c5ded1d269ec4b718a52012af5912d0dfd1801273ffd8d60a25e7
```

### X coordinate (48 bytes)
```
f11552ff2b07f8d3afb836723c866d8a581417d3656ab62901df473f5bc1047d54e4257becb492eecd19887e2713b1ef
```

### Y coordinate (48 bytes)
```
ee9b52e8bbef47f49393bf7c2d580cccb949e077887c5ded1d269ec4b718a52012af5912d0dfd1801273ffd8d60a25e7
```

### Decimal byte arrays (for Noir circuit)
```rust
// X coordinate
let fulcio_x: [u8; 48] = [241,21,82,255,43,7,248,211,175,184,54,114,60,134,109,138,88,20,23,211,101,106,182,41,1,223,71,63,91,193,4,125,84,228,37,123,236,180,146,238,205,25,136,126,39,19,177,239];

// Y coordinate
let fulcio_y: [u8; 48] = [238,155,82,232,187,239,71,244,147,147,191,124,45,88,12,204,185,73,224,119,136,124,93,237,29,38,158,196,183,24,165,32,18,175,89,18,208,223,209,128,18,115,255,216,214,10,37,231];
```

## PEM Certificate
```
-----BEGIN CERTIFICATE-----
MIICGjCCAaGgAwIBAgIUALnViVfnU0brJasmRkHrn/UnfaQwCgYIKoZIzj0EAwMw
KjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTAeFw0y
MjA0MTMyMDA2MTVaFw0zMTEwMDUxMzU2NThaMDcxFTATBgNVBAoTDHNpZ3N0b3Jl
LmRldjEeMBwGA1UEAxMVc2lnc3RvcmUtaW50ZXJtZWRpYXRlMHYwEAYHKoZIzj0C
AQYFK4EEACIDYgAE8RVS/ysH+NOvuDZyPIZtilgUF9NlarYpAd9HP1vBBH1U5CV7
7LSS7s0ZiH4nE7Hv7ptS6LvvR/STk798LVgMzLlJ4HeIfF3tHSaexLcYpSASr1kS
0N/RgBJz/9jWCiXno3sweTAOBgNVHQ8BAf8EBAMCAQYwEwYDVR0lBAwwCgYIKwYB
BQUHAwMwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU39Ppz1YkEZb5qNjp
KFWixi4YZD8wHwYDVR0jBBgwFoAUWMAeX5FFpWapesyQoZMi0CrFxfowCgYIKoZI
zj0EAwMDZwAwZAIwPCsQK4DYiZYDPIaDi5HFKnfxXx6ASSVmERfsynYBiX2X6SJR
nZU84/9DZdnFvvxmAjBOt6QpBlc4J/0DxvkTCqpclvziL6BCCPnjdlIB3Pu3BxsP
mygUY7Ii2zbdCdliiow=
-----END CERTIFICATE-----
```

## Trust Chain

```
Sigstore Root CA (offline, P-384)
    └── Fulcio Intermediate CA (P-384) ← THIS KEY
            └── Leaf certificate (P-256, 10 min validity)
                    └── Signs DSSE envelope
```

## Usage in ZK Circuit

1. **Leaf signature verification** (P-256): Verify attestation signature
2. **Certificate verification** (P-384): Verify leaf cert against this intermediate

Note: Noir has native `ecdsa_secp256r1` but P-384 verification may need custom implementation or bignum library.
