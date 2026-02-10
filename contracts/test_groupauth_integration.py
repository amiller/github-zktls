#!/usr/bin/env python3
"""
GroupAuth Integration Test: Real Dstack Simulator + Anvil + ZK Proofs

Tests the full cross-attestation flow with:
- Real HonkVerifier + SigstoreVerifier on Anvil
- Real ZK proof from Docker prover (proof.bin/inputs.bin fixtures)
- Real Dstack KMS simulator signature chains

Test matrix:
  1. GitHub → GitHub onboarding
  2. GitHub → Dstack onboarding
  3. Dstack → GitHub onboarding

Prerequisites:
  pip install web3 eth-account eth-keys dstack-sdk
  anvil running on localhost:8545
  phala simulator running (socket at DSTACK_SOCKET)
"""

import json, os, subprocess, sys, time
from pathlib import Path
from eth_keys import keys
from eth_utils import keccak
from eth_account import Account
from web3 import Web3

ANVIL_RPC = "http://localhost:8545"
ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
KMS_ROOT = "0x8f2cF602C9695b23130367ed78d8F557554de7C5"
CONTRACTS_DIR = Path(__file__).parent
DSTACK_SOCKET = os.environ.get(
    "DSTACK_SIMULATOR_ENDPOINT",
    os.path.expanduser("~/.phala-cloud/simulator/0.5.3/dstack.sock")
)

# --- ABI fragments ---

GROUPAUTH_ABI = json.loads("""[
  {"inputs":[{"name":"_sigstoreVerifier","type":"address"},{"name":"_kmsRoot","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},
  {"inputs":[{"name":"codeId","type":"bytes32"}],"name":"addAllowedCode","outputs":[],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"proof","type":"bytes"},{"name":"publicInputs","type":"bytes32[]"},{"name":"compressedPubkey","type":"bytes"},{"name":"ownershipSig","type":"bytes"}],"name":"registerGitHub","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"codeId","type":"bytes32"},{"components":[{"name":"messageHash","type":"bytes32"},{"name":"messageSignature","type":"bytes"},{"name":"appSignature","type":"bytes"},{"name":"kmsSignature","type":"bytes"},{"name":"derivedCompressedPubkey","type":"bytes"},{"name":"appCompressedPubkey","type":"bytes"},{"name":"purpose","type":"string"}],"name":"dstackProof","type":"tuple"}],"name":"registerDstack","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"fromMemberId","type":"bytes32"},{"name":"toMemberId","type":"bytes32"},{"name":"encryptedPayload","type":"bytes"}],"name":"onboard","outputs":[],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"memberId","type":"bytes32"}],"name":"isMember","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},
  {"inputs":[{"name":"memberId","type":"bytes32"}],"name":"getOnboarding","outputs":[{"components":[{"name":"fromMember","type":"bytes32"},{"name":"encryptedPayload","type":"bytes"}],"name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
  {"inputs":[{"name":"memberId","type":"bytes32"}],"name":"getMember","outputs":[{"name":"codeId","type":"bytes32"},{"name":"pubkey","type":"bytes"},{"name":"registeredAt","type":"uint256"}],"stateMutability":"view","type":"function"}
]""")


def deploy_contracts_via_script(w3, account):
    """Deploy all contracts using a forge script to handle library linking."""
    # Write a temporary deployment script
    script = CONTRACTS_DIR / "script" / "DeployGroupAuthTest.s.sol"
    script.parent.mkdir(exist_ok=True)
    script.write_text(f"""// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import {{Script}} from "forge-std/Script.sol";
import {{HonkVerifier}} from "../src/HonkVerifier.sol";
import {{SigstoreVerifier}} from "../src/SigstoreVerifier.sol";
import {{GroupAuth}} from "../examples/GroupAuth.sol";
contract DeployGroupAuthTest is Script {{
    function run() external {{
        vm.startBroadcast();
        HonkVerifier honk = new HonkVerifier();
        SigstoreVerifier verifier = new SigstoreVerifier(address(honk));
        new GroupAuth(address(verifier), {KMS_ROOT});
        vm.stopBroadcast();
    }}
}}
""")
    result = subprocess.run([
        "forge", "script", "script/DeployGroupAuthTest.s.sol:DeployGroupAuthTest",
        "--rpc-url", ANVIL_RPC,
        "--private-key", ANVIL_KEY,
        "--broadcast",
    ], capture_output=True, text=True, cwd=str(CONTRACTS_DIR))
    # Clean up
    script.unlink()
    try:
        script.parent.rmdir()
    except OSError:
        pass

    if result.returncode != 0:
        print(f"  DEPLOY FAILED: {result.stderr}")
        print(result.stdout[-500:] if result.stdout else "")
        sys.exit(1)

    # Parse addresses from broadcast JSON
    addresses = {}
    broadcast_dir = CONTRACTS_DIR / "broadcast" / "DeployGroupAuthTest.s.sol"
    for chain_dir in sorted(broadcast_dir.iterdir()) if broadcast_dir.exists() else []:
        run_file = chain_dir / "run-latest.json"
        if run_file.exists():
            data = json.loads(run_file.read_text())
            for tx in data.get("transactions", []):
                name = tx.get("contractName", "")
                addr = tx.get("contractAddress", "")
                if name and addr:
                    addresses[name] = Web3.to_checksum_address(addr)

    for name in ["HonkVerifier", "SigstoreVerifier", "GroupAuth"]:
        print(f"  {name}: {addresses.get(name, 'NOT FOUND')}")

    if "GroupAuth" not in addresses:
        print("  Could not find GroupAuth address in broadcast output")
        print(f"  stdout: {result.stdout[-300:]}")
        sys.exit(1)

    return addresses["GroupAuth"]


def load_github_proof():
    """Load proof.bin and inputs.bin, extract commitSha."""
    proof = (CONTRACTS_DIR / "test" / "proof.bin").read_bytes()
    inputs_raw = (CONTRACTS_DIR / "test" / "inputs.bin").read_bytes()
    # Split into bytes32 array
    public_inputs = [inputs_raw[i:i+32] for i in range(0, len(inputs_raw), 32)]
    # Extract commitSha: elements 64..83 (1 byte per element, in last byte)
    commit_bytes = bytes([inputs_raw[i*32+31] for i in range(64, 84)])
    # codeId = bytes32(bytes20(commitSha)) — right-padded
    code_id = commit_bytes + b'\x00' * 12
    return proof, public_inputs, code_id


def build_dstack_proof():
    """Get signature chain from dstack simulator, build DstackProof tuple."""
    from dstack_sdk import DstackClient
    client = DstackClient(DSTACK_SOCKET)
    info = client.info()
    result = client.get_key("/groupauth", "ethereum")

    derived_key = bytes.fromhex(result.key.replace('0x', ''))[:32]
    app_sig = bytes.fromhex(result.signature_chain[0].replace('0x', ''))
    kms_sig = bytes.fromhex(result.signature_chain[1].replace('0x', ''))
    app_id_hex = info.app_id.replace('0x', '')

    # Compressed pubkeys
    priv = keys.PrivateKey(derived_key)
    derived_pubkey = priv.public_key.to_compressed_bytes()

    # Recover app pubkey
    app_msg = f"ethereum:{derived_pubkey.hex()}"
    app_msg_hash = keccak(text=app_msg)
    app_pubkey = keys.Signature(app_sig).recover_public_key_from_msg_hash(app_msg_hash).to_compressed_bytes()

    # Sign a message with derived key (the contract verifies this)
    message_hash = keccak(b"groupauth-register")
    acct = Account.from_key(derived_key)
    eth_hash = keccak(b"\x19Ethereum Signed Message:\n32" + message_hash)
    sig = acct.unsafe_sign_hash(eth_hash)
    message_sig = bytes(sig.signature)

    # appId as bytes32 (left-padded from 20-byte address)
    app_id_bytes20 = bytes.fromhex(app_id_hex)
    code_id = app_id_bytes20 + b'\x00' * 12  # bytes32(bytes20(appId))

    dstack_proof_tuple = (
        message_hash,       # bytes32 messageHash
        message_sig,        # bytes messageSignature
        app_sig,            # bytes appSignature
        kms_sig,            # bytes kmsSignature
        derived_pubkey,     # bytes derivedCompressedPubkey
        app_pubkey,         # bytes appCompressedPubkey
        "ethereum",         # string purpose
    )

    return code_id, dstack_proof_tuple, derived_pubkey


def make_github_node(gh_proof):
    """Generate a GitHub node: compressed pubkey + ownership signature over proof."""
    privkey = keys.PrivateKey(os.urandom(32))
    compressed = privkey.public_key.to_compressed_bytes()
    proof_hash = keccak(gh_proof)
    eth_hash = keccak(b"\x19Ethereum Signed Message:\n32" + proof_hash)
    acct = Account.from_key(privkey.to_bytes())
    sig = acct.unsafe_sign_hash(eth_hash)
    return compressed, bytes(sig.signature)


def main():
    print("=" * 60)
    print("GroupAuth Integration Test")
    print("=" * 60)

    w3 = Web3(Web3.HTTPProvider(ANVIL_RPC))
    if not w3.is_connected():
        print("ERROR: Start anvil first: anvil &")
        return False
    account = w3.eth.account.from_key(ANVIL_KEY)
    print(f"Anvil connected, block {w3.eth.block_number}, deployer {account.address}")

    # --- Deploy contracts ---
    print("\nDeploying contracts...")
    ga_addr = deploy_contracts_via_script(w3, account)
    ga = w3.eth.contract(address=ga_addr, abi=GROUPAUTH_ABI)

    # --- Load proof data ---
    print("\nLoading proof data...")
    gh_proof, gh_inputs, gh_code_id = load_github_proof()
    print(f"  GitHub codeId: 0x{gh_code_id.hex()}")

    ds_code_id, ds_proof_tuple, ds_pubkey = build_dstack_proof()
    print(f"  Dstack codeId: 0x{ds_code_id.hex()}")

    # --- Add allowed codes ---
    print("\nAdding allowed code IDs...")
    nonce = w3.eth.get_transaction_count(account.address)

    tx = ga.functions.addAllowedCode(gh_code_id).build_transaction({
        "from": account.address, "nonce": nonce, "gas": 100000, "gasPrice": w3.eth.gas_price
    })
    w3.eth.send_raw_transaction(account.sign_transaction(tx).raw_transaction)
    nonce += 1

    tx = ga.functions.addAllowedCode(ds_code_id).build_transaction({
        "from": account.address, "nonce": nonce, "gas": 100000, "gasPrice": w3.eth.gas_price
    })
    w3.eth.send_raw_transaction(account.sign_transaction(tx).raw_transaction)
    nonce += 1
    print("  Done")

    def send_tx(fn, nonce_val):
        tx = fn.build_transaction({
            "from": account.address, "nonce": nonce_val, "gas": 5000000, "gasPrice": w3.eth.gas_price
        })
        receipt = w3.eth.wait_for_transaction_receipt(
            w3.eth.send_raw_transaction(account.sign_transaction(tx).raw_transaction)
        )
        if receipt["status"] != 1:
            raise Exception(f"Transaction reverted! Gas used: {receipt['gasUsed']}")
        return receipt

    passed = 0
    failed = 0

    # ============================
    # Test 1: GitHub → GitHub
    # ============================
    print("\n--- Test 1: GitHub → GitHub ---")
    try:
        pubkey_a, sig_a = make_github_node(gh_proof)
        pubkey_b, sig_b = make_github_node(gh_proof)
        member_a = Web3.solidity_keccak(["bytes"], [pubkey_a])
        member_b = Web3.solidity_keccak(["bytes"], [pubkey_b])

        send_tx(ga.functions.registerGitHub(gh_proof, gh_inputs, pubkey_a, sig_a), nonce)
        nonce += 1
        print(f"  Registered GitHub node A: {member_a.hex()[:16]}...")

        send_tx(ga.functions.registerGitHub(gh_proof, gh_inputs, pubkey_b, sig_b), nonce)
        nonce += 1
        print(f"  Registered GitHub node B: {member_b.hex()[:16]}...")

        assert ga.functions.isMember(member_a).call(), "A not member"
        assert ga.functions.isMember(member_b).call(), "B not member"

        send_tx(ga.functions.onboard(member_a, member_b, b"gh-to-gh-secret"), nonce)
        nonce += 1

        msgs = ga.functions.getOnboarding(member_b).call()
        assert len(msgs) == 1, f"expected 1 msg, got {len(msgs)}"
        assert msgs[0][0] == member_a, "wrong sender"
        assert msgs[0][1] == b"gh-to-gh-secret", "wrong payload"

        print("  PASS: GitHub → GitHub onboarding verified on-chain")
        passed += 1
    except Exception as e:
        print(f"  FAIL: {e}")
        failed += 1

    # ============================
    # Test 2: GitHub → Dstack
    # ============================
    print("\n--- Test 2: GitHub → Dstack ---")
    try:
        gh_pubkey, gh_sig = make_github_node(gh_proof)
        gh_member = Web3.solidity_keccak(["bytes"], [gh_pubkey])
        ds_member = Web3.solidity_keccak(["bytes"], [ds_pubkey])

        send_tx(ga.functions.registerGitHub(gh_proof, gh_inputs, gh_pubkey, gh_sig), nonce)
        nonce += 1
        print(f"  Registered GitHub node: {gh_member.hex()[:16]}...")

        send_tx(ga.functions.registerDstack(ds_code_id, ds_proof_tuple), nonce)
        nonce += 1
        print(f"  Registered Dstack node: {ds_member.hex()[:16]}...")

        assert ga.functions.isMember(gh_member).call()
        assert ga.functions.isMember(ds_member).call()

        # Verify codeIds
        gh_info = ga.functions.getMember(gh_member).call()
        ds_info = ga.functions.getMember(ds_member).call()
        assert gh_info[0] == gh_code_id, "GitHub codeId mismatch"
        assert ds_info[0] == ds_code_id, "Dstack codeId mismatch"

        send_tx(ga.functions.onboard(gh_member, ds_member, b"gh-to-ds-secret"), nonce)
        nonce += 1

        msgs = ga.functions.getOnboarding(ds_member).call()
        assert len(msgs) == 1 and msgs[0][1] == b"gh-to-ds-secret"

        print("  PASS: GitHub → Dstack onboarding verified on-chain")
        passed += 1
    except Exception as e:
        print(f"  FAIL: {e}")
        failed += 1

    # ============================
    # Test 3: Dstack → GitHub
    # ============================
    print("\n--- Test 3: Dstack → GitHub ---")
    try:
        # Dstack: pubkey is now derived from the proof's derivedCompressedPubkey.
        # Same key path returns same key → same memberId. Already registered in test 2.
        # For a fresh member, we need a different key path or a fresh simulator.
        # Since the simulator returns the same derived key for "/groupauth","ethereum",
        # we reuse the already-registered ds_member from test 2 if still a member,
        # OR we just test the Dstack→GitHub direction using the existing member.
        # Actually, ds_member was registered in test 2, so just use it here.

        gh_pubkey2, gh_sig2 = make_github_node(gh_proof)
        gh_member2 = Web3.solidity_keccak(["bytes"], [gh_pubkey2])
        send_tx(ga.functions.registerGitHub(gh_proof, gh_inputs, gh_pubkey2, gh_sig2), nonce)
        nonce += 1
        print(f"  Registered GitHub node: {gh_member2.hex()[:16]}...")

        # Dstack onboards GitHub (reuse ds_member from test 2)
        send_tx(ga.functions.onboard(ds_member, gh_member2, b"ds-to-gh-secret"), nonce)
        nonce += 1

        msgs = ga.functions.getOnboarding(gh_member2).call()
        assert len(msgs) == 1 and msgs[0][1] == b"ds-to-gh-secret"

        # GitHub can now chain-onboard another
        gh_pubkey3, gh_sig3 = make_github_node(gh_proof)
        gh_member3 = Web3.solidity_keccak(["bytes"], [gh_pubkey3])
        send_tx(ga.functions.registerGitHub(gh_proof, gh_inputs, gh_pubkey3, gh_sig3), nonce)
        nonce += 1
        send_tx(ga.functions.onboard(gh_member2, gh_member3, b"chain-onboard"), nonce)
        nonce += 1

        msgs3 = ga.functions.getOnboarding(gh_member3).call()
        assert len(msgs3) == 1 and msgs3[0][1] == b"chain-onboard"

        print("  PASS: Dstack → GitHub → GitHub chain onboarding verified on-chain")
        passed += 1
    except Exception as e:
        print(f"  FAIL: {e}")
        failed += 1

    # --- Summary ---
    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)
    return failed == 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
