# Sample Attestation Bundle Analysis

Generated from workflow run: https://github.com/amiller/github-zktls/actions/runs/21653800396

## Structure Overview

The Sigstore bundle contains:

1. **DSSE Envelope** - Dead Simple Signing Envelope
   - `payload`: base64 in-toto statement
   - `payloadType`: `application/vnd.in-toto+json`
   - `signatures[].sig`: ECDSA P-256 signature

2. **Verification Material**
   - `certificate.rawBytes`: X.509 cert (base64 DER)
   - `tlogEntries[]`: Rekor transparency log entry with inclusion proof

## Key Cryptographic Details

### Signature Scheme
- **Algorithm**: ECDSA with SHA-256
- **Curve**: P-256 (prime256v1, secp256r1)
- **Certificate issuer**: `sigstore-intermediate` signed with ECDSA-SHA384

### Certificate Public Key (P-256)
```
04:a2:7f:4b:19:08:1c:3b:31:ca:55:6d:e5:c5:4b:
c1:fb:f1:08:d6:f2:ff:d3:7a:25:bf:d3:53:49:97:
df:5b:cd:aa:7f:64:e6:58:b0:dd:0d:c7:47:d4:45:
df:b6:8c:fa:03:7c:8d:f1:95:2d:03:b6:a9:b1:b4:
39:41:9c:f0:92
```

## OIDC Claims in Certificate Extensions

OID prefix: `1.3.6.1.4.1.57264.1.*`

| OID | Field | Value |
|-----|-------|-------|
| .1 | OIDC Issuer | `https://token.actions.githubusercontent.com` |
| .2 | Event Name | `workflow_dispatch` |
| .3 | SHA | `49eb0a573214e2b35e9b5c95eaad7e2770d12159` |
| .4 | Workflow Name | `Attestation Test` |
| .5 | Repository | `amiller/github-zktls` |
| .6 | Ref | `refs/heads/master` |
| .11 | Runner Environment | `github-hosted` |
| .12 | Repository URL | `https://github.com/amiller/github-zktls` |
| .15 | Repository ID | `1147567108` |
| .17 | Owner ID | `71644` |
| .21 | Run URL | `https://github.com/amiller/github-zktls/actions/runs/21653800396/attempts/1` |
| .22 | Visibility | `public` |

## In-Toto Statement (Decoded Payload)

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{
    "name": "proof.tar",
    "digest": {
      "sha256": "0ff929f1e9d16da57fb6fea24557fe429230e1bc52bb8f63077a2cd713dd2539"
    }
  }],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://actions.github.io/buildtypes/workflow/v1",
      "externalParameters": {
        "workflow": {
          "ref": "refs/heads/master",
          "repository": "https://github.com/amiller/github-zktls",
          "path": ".github/workflows/attestation-test.yml"
        }
      },
      "resolvedDependencies": [{
        "uri": "git+https://github.com/amiller/github-zktls@refs/heads/master",
        "digest": {"gitCommit": "49eb0a573214e2b35e9b5c95eaad7e2770d12159"}
      }]
    },
    "runDetails": {
      "builder": {
        "id": "https://github.com/amiller/github-zktls/.github/workflows/attestation-test.yml@refs/heads/master"
      }
    }
  }
}
```

## What We Need to Verify in ZK

### Minimal verification (for on-chain)
1. ECDSA P-256 signature over DSSE envelope
2. Certificate chain to Fulcio intermediate
3. Extract: repo, workflow path, commit SHA, artifact hash

### Signature Verification Steps
1. Compute SHA-256 hash of DSSE envelope (not just payload)
2. Verify ECDSA signature against certificate's public key
3. Verify certificate signature against Fulcio intermediate CA public key

### DSSE Envelope Format for Signing
The signature is over the PAE (Pre-Authentication Encoding):
```
"DSSEv1" + SP + LEN(payloadType) + SP + payloadType + SP + LEN(payload) + SP + payload
```
Where SP = space (0x20) and LEN = decimal string of byte length.

## Fulcio Trust Chain

```
Sigstore Root CA (offline, rotates rarely)
    └── sigstore-intermediate (ECDSA P-384)
            └── Leaf certificate (ECDSA P-256, 10 min validity)
```

Intermediate CA public key needs to be hardcoded or fetched from TUF.

## Next Steps for ZK Circuit

1. Implement DSSE PAE encoding
2. Implement SHA-256 (or use Noir stdlib)
3. Implement ECDSA P-256 verification (Noir has native support)
4. Parse X.509 certificate to extract public key and OID extensions
5. Verify certificate against intermediate CA (ECDSA P-384 - harder)
