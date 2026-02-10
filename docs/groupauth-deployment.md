# GroupAuth Deployment Guide

## Overview

GroupAuth creates a peer network where GitHub runners and Dstack TEEs register as equal members, prove their code identity, and onboard each other with encrypted group secrets.

**Components:**
1. **GroupAuth contract** — deployed to Base mainnet
2. **Dstack TEE agent** — long-running container on Phala Cloud, watches for new members
3. **GitHub runner** — ephemeral, registers via ZK proof during workflow

## Architecture

```
┌─────────────────┐     ┌──────────────────┐
│  GitHub Runner   │     │   Phala TEE      │
│  (ephemeral)     │     │  (long-running)  │
│                  │     │                  │
│ 1. Generate ZK   │     │ 1. Get derived   │
│    proof from    │     │    key from KMS  │
│    Sigstore att  │     │ 2. registerDstack│
│ 2. registerGitHub│     │ 3. Watch events  │
│ 3. Read onboard  │     │ 4. Onboard new   │
│    messages      │     │    members       │
└────────┬─────────┘     └────────┬─────────┘
         │                        │
         └───────┐   ┌────────────┘
                 ▼   ▼
         ┌───────────────────┐
         │  GroupAuth.sol     │
         │  (Base mainnet)    │
         │                    │
         │  allowedCode[]     │
         │  members[]         │
         │  onboarding[]      │
         └───────────────────┘
```

## Phala Cloud: KMS Types and URL Gotchas

### `--kms` flag determines everything

When deploying with `phala deploy`, the `--kms` flag (default: `phala`) determines:
1. **Which KMS signs your derived keys** — each KMS type has a different root address
2. **The gateway URL prefix** — the URL infix matches the KMS type

| `--kms` value | URL infix | Example domain |
|---------------|-----------|----------------|
| `phala` (default) | `pha-` | `dstack-pha-prod7.phala.network` |
| `base` | `base-` | `dstack-base-prod7.phala.network` |
| `ethereum`/`eth` | `eth-` | `dstack-eth-prod7.phala.network` |

**CRITICAL**: `phala deploy` does NOT output the endpoint URL. You must run
`phala cvms get <name> --json` and check `gateway.base_domain` or `endpoints[0].app`
to get the correct URL. The URL format is:
```
https://<app_id>-<port>.<gateway.base_domain>
```

### KMS Root differs per KMS type

Each KMS type has a different root signer. You CANNOT derive the KMS root from the
attestation's P-256 DER key — the KMS signs with secp256k1 internally.

To discover the production KMS root:
1. Deploy a CVM with your chosen `--kms` type
2. Have your app recover the KMS signer from an actual KMS signature via `ecrecover`
3. Use that address as the `kmsRoot` in your contract

| KMS type | Root address |
|----------|-------------|
| Simulator | `0x8f2cF602C9695b23130367ed78d8F557554de7C5` |
| Production (phala) | `0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77` |
| Production (base) | TBD |

## Step 1: Deploy Contracts

### Prerequisites
- Foundry installed with deployer key at `~/.foundry/keystores/deployer.key`

### Deploy

```bash
cd contracts

# Deploy HonkVerifier + SigstoreVerifier + GroupAuth
KMS_ROOT=0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77  # phala KMS
SIGSTORE_VERIFIER=0x904Ae91989C4C96F2f51f1F8c9eF65C3730b3d8d  # or deploy fresh

forge script script/DeployGroupAuth.s.sol \
  --rpc-url https://mainnet.base.org \
  --keystore ~/.foundry/keystores/deployer.key \
  --broadcast

# Add allowed code IDs (owner only)
# GitHub: bytes32(bytes20(commitSha)) — right-padded
# Dstack: bytes32(bytes20(appId)) — right-padded
cast send <GROUPAUTH_ADDR> "addAllowedCode(bytes32)" <CODE_ID> \
  --rpc-url https://mainnet.base.org \
  --keystore ~/.foundry/keystores/deployer.key \
  --gas-limit 50000
```

## Step 2: Build Dstack TEE Agent

The TEE agent is a Python container that:
1. Derives a key from Dstack KMS
2. Registers itself via `registerDstack()`
3. Watches `MemberRegistered` events
4. Posts onboarding messages (encrypted group secret) for new members

### docker-compose.yaml (for Phala Cloud)

```yaml
services:
  ssh:
    build:
      context: .
      dockerfile_inline: |
        FROM ubuntu:22.04
        RUN apt-get update && apt-get install -y openssh-server
        RUN mkdir /run/sshd
        RUN echo 'root:groupauth' | chpasswd
        RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        RUN sed -i 's/#Port 22/Port 1022/' /etc/ssh/sshd_config
        CMD ["/usr/sbin/sshd", "-D"]
    restart: unless-stopped
    network_mode: host

  groupauth-agent:
    image: ghcr.io/amiller/groupauth-agent:v1
    ports:
      - "8080:8080"
    environment:
      GROUPAUTH_ADDRESS: ${GROUPAUTH_ADDRESS}
      RPC_URL: ${RPC_URL:-https://sepolia.base.org}
      GROUP_SECRET: ${GROUP_SECRET}
    volumes:
      - /var/run/dstack.sock:/var/run/dstack.sock
    restart: unless-stopped
```

### Build & Push

```bash
# Build OCI image
docker buildx build \
  --file Dockerfile \
  --output type=oci,dest=image.tar \
  .

# Push to GHCR
skopeo copy oci-archive:image.tar docker://ghcr.io/amiller/groupauth-agent:v1

# Or simpler:
docker build -t ghcr.io/amiller/groupauth-agent:v1 .
docker push ghcr.io/amiller/groupauth-agent:v1
```

### Deploy to Phala Cloud

```bash
# Auth (already done if phala CLI configured)
phala auth login <API_KEY>

# Deploy — NOTE: --kms flag determines KMS type AND gateway URL prefix
# Default is "phala". Use --kms base for Base KMS.
phala deploy -n groupauth-agent -c docker-compose.yaml
# or: phala deploy -n groupauth-agent -c docker-compose.yaml --kms base

# IMPORTANT: phala deploy does NOT output the endpoint URL!
# Get it from:
phala cvms get groupauth-agent --json | jq '.endpoints[0].app'
# → https://<app_id>-8080.dstack-<kms>-prod7.phala.network

# Check status
phala cvms list
phala cvms logs groupauth-agent
```

### SSH Access for Debugging

```bash
# Tunnel through TLS
socat TCP-LISTEN:11025,bind=127.0.0.1,fork,reuseaddr \
  OPENSSL:<cvm-id>-1022.dstack-pha-prod7.phala.network:443 &

sshpass -p 'groupauth' ssh root@127.0.0.1 -p 11025
```

## Step 3: GitHub Workflow Integration

The GitHub runner registers via the existing ZK proof pipeline:

```yaml
# In .github/workflows/groupauth.yml
- name: Generate ZK proof
  run: |
    docker run --rm \
      -v $GITHUB_WORKSPACE/bundle.json:/work/bundle.json:ro \
      -v /tmp/proof:/output \
      ghcr.io/amiller/zkproof generate /work/bundle.json /output

- name: Register and read onboarding
  run: |
    # Generate ephemeral keypair
    PRIVKEY=$(openssl rand -hex 32)
    PUBKEY=$(cast wallet address --private-key $PRIVKEY)

    # Register via GroupAuth
    cast send $GROUPAUTH_ADDRESS \
      "registerGitHub(bytes,bytes32[],bytes)" \
      $(cat /tmp/proof/proof.bin | xxd -p -c0) \
      "[$(cat /tmp/proof/inputs.bin | xxd -p -c0 | fold -w64 | sed 's/^/0x/' | paste -sd,)]" \
      $PUBKEY \
      --rpc-url $RPC_URL --private-key $PRIVKEY

    # Read onboarding messages
    MEMBER_ID=$(cast keccak $PUBKEY)
    cast call $GROUPAUTH_ADDRESS "getOnboarding(bytes32)" $MEMBER_ID --rpc-url $RPC_URL
```

## Key Addresses

| Component | Address | Network |
|-----------|---------|---------|
| GroupAuth | `0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725` | Base mainnet |
| SigstoreVerifier | `0x904Ae91989C4C96F2f51f1F8c9eF65C3730b3d8d` | Base mainnet |
| HonkVerifier | `0xd317A58C478a18CA71BfC60Aab85538aB28b98ab` | Base mainnet |
| Dstack KMS Root (sim) | `0x8f2cF602C9695b23130367ed78d8F557554de7C5` | — |
| Dstack KMS Root (phala prod) | `0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77` | — |
| TEE Agent CVM | `app_7385b203510cc6735e512ca776ad27c37a52d249` | Phala Cloud (phala KMS) |
| TEE Agent health | `https://7385b203510cc6735e512ca776ad27c37a52d249-8080.dstack-pha-prod7.phala.network/` | — |
| TEE Agent memberId | `0x66a87d52...` | — |

## Testing Checklist

- [x] 21 forge unit tests pass
- [x] Integration: GitHub→GitHub (real ZK proof on Anvil)
- [x] Integration: GitHub→Dstack (real Dstack simulator on Anvil)
- [x] Integration: Dstack→GitHub (real Dstack simulator on Anvil)
- [x] Deploy contracts to Base mainnet
- [x] Verify contracts on Basescan
- [x] Deploy TEE agent to Phala Cloud
- [x] TEE agent registers on-chain
- [ ] End-to-end: GitHub registers + TEE auto-onboards
- [ ] GitHub workflow for GroupAuth registration
