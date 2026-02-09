// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title CrossAttestationBridge
/// @notice Mutual attestation between GitHub Actions (Sigstore ZK) and Dstack (TDX KMS)
/// @dev Both sides register verified attestations + payloads on a named channel.
///      Once both are verified, the channel is "mutually attested" and payloads are accessible.
contract CrossAttestationBridge {
    ISigstoreVerifier public immutable sigstoreVerifier;
    address public immutable kmsRoot;

    struct DstackProof {
        bytes32 messageHash;
        bytes messageSignature;
        bytes appSignature;
        bytes kmsSignature;
        bytes derivedCompressedPubkey;  // 33 bytes compressed SEC1
        bytes appCompressedPubkey;      // 33 bytes compressed SEC1
        string purpose;
    }

    struct Channel {
        bytes32 requiredRepoHash;
        bytes20 requiredCommitSha;   // 0 = any
        bytes32 requiredAppId;

        bytes32 githubArtifactHash;
        bytes20 githubCommitSha;
        bytes githubPayload;
        bool githubVerified;

        bytes dstackPayload;
        bool dstackVerified;
    }

    mapping(bytes32 => Channel) internal _channels;

    event ChannelCreated(bytes32 indexed channelId, bytes32 repoHash, bytes32 appId, address creator);
    event GitHubAttested(bytes32 indexed channelId, bytes32 artifactHash, bytes20 commitSha);
    event DstackAttested(bytes32 indexed channelId, bytes32 appId);
    event MutuallyAttested(bytes32 indexed channelId);

    error ChannelExists();
    error ChannelNotFound();
    error AlreadyRegistered();
    error RepoMismatch();
    error CommitMismatch();
    error AppIdMismatch();
    error InvalidDstackSignature();
    error NotMutuallyAttested();

    constructor(address _sigstoreVerifier, address _kmsRoot) {
        sigstoreVerifier = ISigstoreVerifier(_sigstoreVerifier);
        kmsRoot = _kmsRoot;
    }

    function createChannel(
        bytes32 channelId,
        bytes32 repoHash,
        bytes20 commitSha,
        bytes32 appId
    ) external {
        if (_channels[channelId].requiredRepoHash != bytes32(0)) revert ChannelExists();
        _channels[channelId] = Channel({
            requiredRepoHash: repoHash,
            requiredCommitSha: commitSha,
            requiredAppId: appId,
            githubArtifactHash: bytes32(0),
            githubCommitSha: bytes20(0),
            githubPayload: "",
            githubVerified: false,
            dstackPayload: "",
            dstackVerified: false
        });
        emit ChannelCreated(channelId, repoHash, appId, msg.sender);
    }

    /// @notice Register a GitHub Actions attestation via ZK proof
    function registerGitHub(
        bytes32 channelId,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata payload
    ) external {
        Channel storage ch = _channels[channelId];
        if (ch.requiredRepoHash == bytes32(0)) revert ChannelNotFound();
        if (ch.githubVerified) revert AlreadyRegistered();

        ISigstoreVerifier.Attestation memory att = sigstoreVerifier.verifyAndDecode(proof, publicInputs);

        if (att.repoHash != ch.requiredRepoHash) revert RepoMismatch();
        if (ch.requiredCommitSha != bytes20(0) && att.commitSha != ch.requiredCommitSha)
            revert CommitMismatch();

        ch.githubArtifactHash = att.artifactHash;
        ch.githubCommitSha = att.commitSha;
        ch.githubPayload = payload;
        ch.githubVerified = true;

        emit GitHubAttested(channelId, att.artifactHash, att.commitSha);
        if (ch.dstackVerified) emit MutuallyAttested(channelId);
    }

    /// @notice Register a Dstack TEE attestation via KMS signature chain
    function registerDstack(
        bytes32 channelId,
        DstackProof calldata dstackProof,
        bytes calldata payload
    ) external {
        Channel storage ch = _channels[channelId];
        if (ch.requiredRepoHash == bytes32(0)) revert ChannelNotFound();
        if (ch.dstackVerified) revert AlreadyRegistered();

        if (!_verifyDstackChain(ch.requiredAppId, dstackProof)) revert InvalidDstackSignature();

        ch.dstackPayload = payload;
        ch.dstackVerified = true;

        emit DstackAttested(channelId, ch.requiredAppId);
        if (ch.githubVerified) emit MutuallyAttested(channelId);
    }

    // --- Views ---

    function isMutuallyAttested(bytes32 channelId) external view returns (bool) {
        Channel storage ch = _channels[channelId];
        return ch.githubVerified && ch.dstackVerified;
    }

    function getChannel(bytes32 channelId) external view returns (
        bytes32 requiredRepoHash,
        bytes20 requiredCommitSha,
        bytes32 requiredAppId,
        bool githubVerified,
        bool dstackVerified
    ) {
        Channel storage ch = _channels[channelId];
        return (ch.requiredRepoHash, ch.requiredCommitSha, ch.requiredAppId,
                ch.githubVerified, ch.dstackVerified);
    }

    function getPayloads(bytes32 channelId) external view returns (
        bytes memory githubPayload,
        bytes memory dstackPayload
    ) {
        Channel storage ch = _channels[channelId];
        if (!ch.githubVerified || !ch.dstackVerified) revert NotMutuallyAttested();
        return (ch.githubPayload, ch.dstackPayload);
    }

    function getGitHubAttestation(bytes32 channelId) external view returns (
        bytes32 artifactHash, bytes20 commitSha, bool verified
    ) {
        Channel storage ch = _channels[channelId];
        return (ch.githubArtifactHash, ch.githubCommitSha, ch.githubVerified);
    }

    // --- Dstack signature chain verification (ported from TeeOracle.sol) ---

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
        bytes32 r;
        bytes32 s;
        uint8 v;
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
        bytes memory input = abi.encodePacked(
            uint256(32), uint256(32), uint256(32), base, exp, mod
        );
        bytes memory output = new bytes(32);
        assembly {
            if iszero(staticcall(gas(), 0x05, add(input, 32), 192, add(output, 32), 32)) {
                revert(0, 0)
            }
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
