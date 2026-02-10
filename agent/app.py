#!/usr/bin/env python3
"""GroupAuth Dstack TEE Agent"""

import json, os, time, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from dstack_sdk import DstackClient
from web3 import Web3
from eth_account import Account
from eth_keys import keys
from eth_utils import keccak
from ecies import encrypt as ecies_encrypt

RPC_URL = os.environ.get('RPC_URL', 'https://mainnet.base.org')
GROUPAUTH_ADDRESS = os.environ['GROUPAUTH_ADDRESS']
GROUP_SECRET = os.environ.get('GROUP_SECRET', 'default-group-secret')
POLL_INTERVAL = int(os.environ.get('POLL_INTERVAL', '12'))

GA_ABI = json.loads("""[
  {"inputs":[{"name":"codeId","type":"bytes32"},{"components":[{"name":"messageHash","type":"bytes32"},{"name":"messageSignature","type":"bytes"},{"name":"appSignature","type":"bytes"},{"name":"kmsSignature","type":"bytes"},{"name":"derivedCompressedPubkey","type":"bytes"},{"name":"appCompressedPubkey","type":"bytes"},{"name":"purpose","type":"string"}],"name":"dstackProof","type":"tuple"}],"name":"registerDstack","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"fromMemberId","type":"bytes32"},{"name":"toMemberId","type":"bytes32"},{"name":"encryptedPayload","type":"bytes"}],"name":"onboard","outputs":[],"stateMutability":"nonpayable","type":"function"},
  {"inputs":[{"name":"memberId","type":"bytes32"}],"name":"isMember","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},
  {"inputs":[{"name":"memberId","type":"bytes32"}],"name":"getMember","outputs":[{"name":"codeId","type":"bytes32"},{"name":"pubkey","type":"bytes"},{"name":"registeredAt","type":"uint256"}],"stateMutability":"view","type":"function"},
  {"anonymous":false,"inputs":[{"indexed":true,"name":"memberId","type":"bytes32"},{"indexed":true,"name":"codeId","type":"bytes32"},{"indexed":false,"name":"pubkey","type":"bytes"}],"name":"MemberRegistered","type":"event"}
]""")

print("Connecting to Dstack KMS...")
client = DstackClient()
info = client.info()
app_id = info.app_id
print(f"App ID: {app_id}")

result = client.get_key("/groupauth", "ethereum")
derived_key = bytes.fromhex(result.key.replace('0x', ''))[:32]
acct = Account.from_key(derived_key)
print(f"Derived address: {acct.address}")

app_sig = bytes.fromhex(result.signature_chain[0].replace('0x', ''))
kms_sig = bytes.fromhex(result.signature_chain[1].replace('0x', ''))

priv = keys.PrivateKey(derived_key)
derived_pubkey = priv.public_key.to_compressed_bytes()

app_msg = f"ethereum:{derived_pubkey.hex()}"
app_msg_hash = keccak(text=app_msg)
app_pubkey = keys.Signature(app_sig).recover_public_key_from_msg_hash(app_msg_hash).to_compressed_bytes()

message_hash = keccak(b"groupauth-register")
eth_hash = keccak(b"\x19Ethereum Signed Message:\n32" + message_hash)
sig = acct.unsafe_sign_hash(eth_hash)
message_sig = bytes(sig.signature)

app_id_bytes20 = bytes.fromhex(app_id.replace('0x', ''))
code_id = app_id_bytes20 + b'\x00' * 12

dstack_proof = (message_hash, message_sig, app_sig, kms_sig, derived_pubkey, app_pubkey, "ethereum")

# Debug: recover KMS signer to verify against contract's kmsRoot
kms_msg = b"dstack-kms-issued:" + app_id_bytes20 + app_pubkey
kms_msg_hash = keccak(kms_msg)
kms_signer = keys.Signature(kms_sig).recover_public_key_from_msg_hash(kms_msg_hash)
print(f"KMS signer (recovered): {kms_signer.to_checksum_address()}")
print(f"App pubkey: {app_pubkey.hex()}")
print(f"Derived pubkey: {derived_pubkey.hex()}")
print(f"Code ID: {code_id.hex()}")

w3 = Web3(Web3.HTTPProvider(RPC_URL))
ga = w3.eth.contract(address=Web3.to_checksum_address(GROUPAUTH_ADDRESS), abi=GA_ABI)

print("Registering on GroupAuth...")
my_pubkey = derived_pubkey
my_member_id = Web3.solidity_keccak(["bytes"], [my_pubkey])

if ga.functions.isMember(my_member_id).call():
    print(f"Already registered: {my_member_id.hex()}")
else:
    tx = ga.functions.registerDstack(code_id, dstack_proof).build_transaction({
        'from': acct.address, 'nonce': w3.eth.get_transaction_count(acct.address), 'gas': 500000,
    })
    signed = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    assert receipt['status'] == 1, f"Registration reverted, gas used: {receipt['gasUsed']}"
    print(f"Registered! memberId={my_member_id.hex()} tx={tx_hash.hex()}")

onboarded = set()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            "status": "ok", "memberId": my_member_id.hex(),
            "address": acct.address, "app_id": app_id,
            "onboarded_count": len(onboarded),
        })
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, *args): pass

server = HTTPServer(("0.0.0.0", 8080), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
print("Health endpoint on :8080")

print("Watching for MemberRegistered events...")
last_block = w3.eth.block_number

while True:
    current_block = w3.eth.block_number
    if current_block > last_block:
        events = ga.events.MemberRegistered.get_logs(from_block=last_block + 1, to_block=current_block)
        for evt in events:
            new_id = evt.args.memberId
            if new_id == my_member_id or new_id in onboarded:
                continue
            print(f"New member: {new_id.hex()}")
            member_info = ga.functions.getMember(new_id).call()
            recipient_pubkey = member_info[1]  # compressed pubkey
            payload = ecies_encrypt(recipient_pubkey, GROUP_SECRET.encode())
            tx = ga.functions.onboard(my_member_id, new_id, payload).build_transaction({
                'from': acct.address, 'nonce': w3.eth.get_transaction_count(acct.address), 'gas': 200000,
            })
            signed = acct.sign_transaction(tx)
            tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
            w3.eth.wait_for_transaction_receipt(tx_hash)
            onboarded.add(new_id)
            print(f"Onboarded {new_id.hex()}: {tx_hash.hex()}")
        last_block = current_block
    time.sleep(POLL_INTERVAL)
