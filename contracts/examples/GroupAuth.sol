// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title GroupAuth
/// @notice Peer network membership for GitHub runners + Dstack TEEs
/// @dev Members prove code identity via ZK (GitHub) or KMS chain (Dstack).
///      Any verified member can onboard new members by posting encrypted group secrets.
contract GroupAuth {
    ISigstoreVerifier public immutable sigstoreVerifier;
    address public immutable kmsRoot;
    address public owner;

    // Allowed code identities (bytes32)
    // GitHub: bytes32(commitSha)  |  Dstack: appId/composeHash
    mapping(bytes32 => bool) public allowedCode;

    struct Member {
        bytes32 codeId;
        bytes pubkey;
        uint256 registeredAt;
    }

    // memberId = keccak256(pubkey)
    mapping(bytes32 => Member) internal _members;

    struct OnboardMsg {
        bytes32 fromMember;
        bytes encryptedPayload;
    }
    mapping(bytes32 => OnboardMsg[]) internal _onboarding;

    struct DstackProof {
        bytes32 messageHash;
        bytes messageSignature;
        bytes appSignature;
        bytes kmsSignature;
        bytes derivedCompressedPubkey;  // 33 bytes compressed SEC1
        bytes appCompressedPubkey;      // 33 bytes compressed SEC1
        string purpose;
    }

    event MemberRegistered(bytes32 indexed memberId, bytes32 indexed codeId, bytes pubkey);
    event OnboardingPosted(bytes32 indexed toMember, bytes32 indexed fromMember);
    event AllowedCodeAdded(bytes32 indexed codeId);
    event AllowedCodeRemoved(bytes32 indexed codeId);

    error NotOwner();
    error CodeNotAllowed();
    error AlreadyRegistered();
    error MemberNotFound();
    error InvalidDstackSignature();
    error InvalidOwnershipProof();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _sigstoreVerifier, address _kmsRoot) {
        sigstoreVerifier = ISigstoreVerifier(_sigstoreVerifier);
        kmsRoot = _kmsRoot;
        owner = msg.sender;
    }

    // --- Admin ---

    function addAllowedCode(bytes32 codeId) external onlyOwner {
        allowedCode[codeId] = true;
        emit AllowedCodeAdded(codeId);
    }

    function removeAllowedCode(bytes32 codeId) external onlyOwner {
        allowedCode[codeId] = false;
        emit AllowedCodeRemoved(codeId);
    }

    // --- Registration ---

    /// @notice Register via GitHub Sigstore ZK proof
    /// @dev codeId = bytes32(att.commitSha), right-padded with zeros.
    ///      ownershipSig binds the proof to the pubkey — prevents proof replay.
    /// @param proof ZK proof bytes
    /// @param publicInputs ZK proof public inputs
    /// @param compressedPubkey 33-byte SEC1 compressed pubkey for this member
    /// @param ownershipSig EIP-191 signature of keccak256(proof) by pubkey's private key
    function registerGitHub(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata compressedPubkey,
        bytes calldata ownershipSig
    ) external returns (bytes32) {
        ISigstoreVerifier.Attestation memory att = sigstoreVerifier.verifyAndDecode(proof, publicInputs);
        bytes32 codeId = bytes32(att.commitSha);
        if (!allowedCode[codeId]) revert CodeNotAllowed();
        // Verify caller controls the private key for compressedPubkey
        bytes32 proofHash = keccak256(proof);
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", proofHash));
        if (_recoverSigner(ethHash, ownershipSig) != _compressedPubkeyToAddress(compressedPubkey))
            revert InvalidOwnershipProof();
        return _register(codeId, compressedPubkey);
    }

    /// @notice Register via Dstack KMS signature chain
    /// @dev Pubkey is derived from the DstackProof's derivedCompressedPubkey — no separate param.
    ///      The KMS chain proves the TEE controls this key.
    /// @param codeId The appId/composeHash — caller declares, chain verification confirms
    function registerDstack(
        bytes32 codeId,
        DstackProof calldata dstackProof
    ) external returns (bytes32) {
        if (!_verifyDstackChain(codeId, dstackProof)) revert InvalidDstackSignature();
        if (!allowedCode[codeId]) revert CodeNotAllowed();
        return _register(codeId, dstackProof.derivedCompressedPubkey);
    }

    function _register(bytes32 codeId, bytes calldata pubkey) internal returns (bytes32 memberId) {
        memberId = keccak256(pubkey);
        if (_members[memberId].registeredAt != 0) revert AlreadyRegistered();
        _members[memberId] = Member({codeId: codeId, pubkey: pubkey, registeredAt: block.timestamp});
        emit MemberRegistered(memberId, codeId, pubkey);
    }

    // --- Onboarding ---

    /// @notice Post encrypted group secret for a new member
    /// @dev Any verified member can onboard any other verified member. No sender auth
    ///      needed — the payload is encrypted to the recipient's pubkey, useless to others.
    function onboard(bytes32 fromMemberId, bytes32 toMemberId, bytes calldata encryptedPayload) external {
        if (_members[fromMemberId].registeredAt == 0) revert MemberNotFound();
        if (_members[toMemberId].registeredAt == 0) revert MemberNotFound();
        _onboarding[toMemberId].push(OnboardMsg({fromMember: fromMemberId, encryptedPayload: encryptedPayload}));
        emit OnboardingPosted(toMemberId, fromMemberId);
    }

    // --- Views ---

    function getMember(bytes32 memberId) external view returns (bytes32 codeId, bytes memory pubkey, uint256 registeredAt) {
        Member storage m = _members[memberId];
        return (m.codeId, m.pubkey, m.registeredAt);
    }

    function isMember(bytes32 memberId) external view returns (bool) {
        return _members[memberId].registeredAt != 0;
    }

    function getOnboarding(bytes32 memberId) external view returns (OnboardMsg[] memory) {
        return _onboarding[memberId];
    }

    // --- Dstack signature chain verification (ported from CrossAttestationBridge) ---

    function _verifyDstackChain(bytes32 _appId, DstackProof calldata p) internal view returns (bool) {
        // Step 1: App signs "purpose:derivedPubkeyHex"
        address recoveredApp;
        {
            string memory derivedHex = _bytesToHex(p.derivedCompressedPubkey);
            bytes32 appMsgHash = keccak256(bytes(abi.encodePacked(p.purpose, ":", derivedHex)));
            recoveredApp = _recoverSigner(appMsgHash, p.appSignature);
        }

        // Step 2: KMS signs "dstack-kms-issued:" + bytes20(appId) + appPubkey
        {
            bytes32 kmsMsgHash = keccak256(abi.encodePacked(
                "dstack-kms-issued:", bytes20(_appId), p.appCompressedPubkey
            ));
            if (_recoverSigner(kmsMsgHash, p.kmsSignature) != kmsRoot) return false;
        }

        // Step 3: Derived key signs the message (EIP-191)
        {
            bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", p.messageHash));
            address messageSigner = _recoverSigner(ethHash, p.messageSignature);
            if (messageSigner != _compressedPubkeyToAddress(p.derivedCompressedPubkey)) return false;
        }

        // Step 4: App pubkey matches recovered app signer
        if (recoveredApp != _compressedPubkeyToAddress(p.appCompressedPubkey)) return false;

        return true;
    }

    function _recoverSigner(bytes32 hash, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig len");
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }

    function _compressedPubkeyToAddress(bytes calldata pubkey) internal view returns (address) {
        require(pubkey.length == 33, "need compressed pubkey");
        uint8 prefix = uint8(pubkey[0]);
        require(prefix == 0x02 || prefix == 0x03, "invalid prefix");

        uint256 x;
        assembly { x := calldataload(add(pubkey.offset, 1)) }

        uint256 p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
        uint256 y2 = addmod(mulmod(mulmod(x, x, p), x, p), 7, p);
        uint256 y = _modExp(y2, (p + 1) / 4, p);

        if ((prefix == 0x02 && y % 2 != 0) || (prefix == 0x03 && y % 2 == 0)) {
            y = p - y;
        }

        bytes32 hash = keccak256(abi.encodePacked(x, y));
        return address(uint160(uint256(hash)));
    }

    function _modExp(uint256 base, uint256 exp, uint256 mod) internal view returns (uint256) {
        bytes memory input = abi.encodePacked(uint256(32), uint256(32), uint256(32), base, exp, mod);
        bytes memory output = new bytes(32);
        assembly {
            if iszero(staticcall(gas(), 0x05, add(input, 32), 192, add(output, 32), 32)) { revert(0, 0) }
        }
        return abi.decode(output, (uint256));
    }

    function _bytesToHex(bytes calldata data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(data.length * 2);
        for (uint i = 0; i < data.length; i++) {
            str[i*2] = alphabet[uint8(data[i] >> 4)];
            str[i*2+1] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
