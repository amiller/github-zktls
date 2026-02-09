// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {CrossAttestationBridge} from "../examples/CrossAttestationBridge.sol";
import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

contract MockSigstoreVerifier is ISigstoreVerifier {
    Attestation public nextAttestation;

    function setAttestation(bytes32 artifactHash, bytes32 repoHash, bytes20 commitSha) external {
        nextAttestation = Attestation(artifactHash, repoHash, commitSha);
    }

    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) { return true; }
    function verifyAndDecode(bytes calldata, bytes32[] calldata)
        external view returns (Attestation memory) { return nextAttestation; }
    function decodePublicInputs(bytes32[] calldata)
        external pure returns (Attestation memory) { revert("not used"); }
}

contract CrossAttestationBridgeTest is Test {
    CrossAttestationBridge bridge;
    MockSigstoreVerifier mockVerifier;

    // Dstack key hierarchy
    uint256 kmsPriv = 0xA11CE;
    uint256 appPriv = 0xB0B;
    uint256 derivedPriv = 0xCA7;

    // Pre-computed compressed SEC1 pubkeys for the above private keys
    bytes constant KMS_PUBKEY = hex"02a64db41e2968c849c2a5615ba0d6e816734a6d3e6ea6ecd6f3acb7d59daa9102";
    bytes constant APP_PUBKEY = hex"035d45cb81aa765d69ca52e3869491ecf0e8fdf6a63d64e65b5213647ee4973ae5";
    bytes constant DERIVED_PUBKEY = hex"0203dffc4af6214b639839fbc2b949621a35ae41bbe7679eee5798afbe85919f69";

    address kmsRoot;
    bytes32 appId = bytes32(bytes20(uint160(0xDEAD)));
    bytes32 repoHash = sha256("owner/repo");
    bytes20 commitSha = bytes20(hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    bytes32 channelId = keccak256("test-channel-1");

    function setUp() public {
        kmsRoot = vm.addr(kmsPriv);
        mockVerifier = new MockSigstoreVerifier();
        bridge = new CrossAttestationBridge(address(mockVerifier), kmsRoot);
    }

    // --- Helpers ---

    function _sign(uint256 privKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _bytesToHex(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(data.length * 2);
        for (uint i = 0; i < data.length; i++) {
            str[i*2] = alphabet[uint8(data[i] >> 4)];
            str[i*2+1] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function _buildDstackProof(bytes32 messageHash) internal pure returns (CrossAttestationBridge.DstackProof memory) {
        bytes32 appId_ = bytes32(bytes20(uint160(0xDEAD)));

        // Step 1: App signs "ethereum:{derivedPubkeyHex}"
        string memory derivedHex = _bytesToHex(DERIVED_PUBKEY);
        string memory appMessage = string(abi.encodePacked("ethereum:", derivedHex));
        bytes32 appMessageHash = keccak256(bytes(appMessage));
        bytes memory appSignature = _sign(0xB0B, appMessageHash);

        // Step 2: KMS signs "dstack-kms-issued:" + bytes20(appId) + appPubkey
        bytes memory kmsMessage = abi.encodePacked("dstack-kms-issued:", bytes20(appId_), APP_PUBKEY);
        bytes32 kmsMessageHash = keccak256(kmsMessage);
        bytes memory kmsSignature = _sign(0xA11CE, kmsMessageHash);

        // Step 3: Derived key signs the message (EIP-191)
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        bytes memory messageSignature = _sign(0xCA7, ethHash);

        return CrossAttestationBridge.DstackProof({
            messageHash: messageHash,
            messageSignature: messageSignature,
            appSignature: appSignature,
            kmsSignature: kmsSignature,
            derivedCompressedPubkey: DERIVED_PUBKEY,
            appCompressedPubkey: APP_PUBKEY,
            purpose: "ethereum"
        });
    }

    // --- Channel creation ---

    function test_CreateChannel() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        (bytes32 rRepo, bytes20 rCommit, bytes32 rApp, bool ghV, bool dsV) = bridge.getChannel(channelId);
        assertEq(rRepo, repoHash);
        assertEq(rCommit, commitSha);
        assertEq(rApp, appId);
        assertFalse(ghV);
        assertFalse(dsV);
    }

    function test_CreateChannel_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit CrossAttestationBridge.ChannelCreated(channelId, repoHash, appId, address(this));
        bridge.createChannel(channelId, repoHash, commitSha, appId);
    }

    function test_CreateChannel_RevertIfExists() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        vm.expectRevert(CrossAttestationBridge.ChannelExists.selector);
        bridge.createChannel(channelId, repoHash, commitSha, appId);
    }

    // --- GitHub registration ---

    function test_RegisterGitHub() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("artifact"), repoHash, commitSha);

        bridge.registerGitHub(channelId, "", new bytes32[](0), hex"deadbeef");

        (bytes32 artHash, bytes20 cSha, bool verified) = bridge.getGitHubAttestation(channelId);
        assertEq(artHash, sha256("artifact"));
        assertEq(cSha, commitSha);
        assertTrue(verified);
    }

    function test_RegisterGitHub_EmitsEvent() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);

        vm.expectEmit(true, false, false, true);
        emit CrossAttestationBridge.GitHubAttested(channelId, sha256("art"), commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
    }

    function test_RegisterGitHub_RevertNoChannel() public {
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);
        vm.expectRevert(CrossAttestationBridge.ChannelNotFound.selector);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
    }

    function test_RegisterGitHub_RevertAlreadyRegistered() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");

        vm.expectRevert(CrossAttestationBridge.AlreadyRegistered.selector);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
    }

    function test_RegisterGitHub_RevertWrongRepo() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), sha256("wrong/repo"), commitSha);

        vm.expectRevert(CrossAttestationBridge.RepoMismatch.selector);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
    }

    function test_RegisterGitHub_RevertWrongCommit() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, bytes20(hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));

        vm.expectRevert(CrossAttestationBridge.CommitMismatch.selector);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
    }

    function test_RegisterGitHub_AnyCommitWhenZero() public {
        bridge.createChannel(channelId, repoHash, bytes20(0), appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, bytes20(hex"cccccccccccccccccccccccccccccccccccccccc"));

        bridge.registerGitHub(channelId, "", new bytes32[](0), "");
        (, bytes20 cSha, bool verified) = bridge.getGitHubAttestation(channelId);
        assertEq(cSha, bytes20(hex"cccccccccccccccccccccccccccccccccccccccc"));
        assertTrue(verified);
    }

    // --- Dstack registration ---

    function test_RegisterDstack_RevertNoChannel() public {
        CrossAttestationBridge.DstackProof memory proof;
        vm.expectRevert(CrossAttestationBridge.ChannelNotFound.selector);
        bridge.registerDstack(channelId, proof, "");
    }

    function test_RegisterDstack_RevertBadSigLen() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        CrossAttestationBridge.DstackProof memory proof;
        proof.messageSignature = hex"1234";
        proof.appSignature = hex"1234";
        proof.kmsSignature = hex"1234";
        proof.derivedCompressedPubkey = DERIVED_PUBKEY;
        proof.appCompressedPubkey = APP_PUBKEY;
        proof.purpose = "ethereum";

        vm.expectRevert("bad sig len");
        bridge.registerDstack(channelId, proof, "");
    }

    function test_RegisterDstack_RevertInvalidChain() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);

        bytes memory sig = new bytes(65);
        CrossAttestationBridge.DstackProof memory proof = CrossAttestationBridge.DstackProof({
            messageHash: bytes32(0),
            messageSignature: sig,
            appSignature: sig,
            kmsSignature: sig,
            derivedCompressedPubkey: hex"020000000000000000000000000000000000000000000000000000000000000001",
            appCompressedPubkey: hex"020000000000000000000000000000000000000000000000000000000000000001",
            purpose: "ethereum"
        });

        vm.expectRevert(CrossAttestationBridge.InvalidDstackSignature.selector);
        bridge.registerDstack(channelId, proof, "");
    }

    function test_RegisterDstack_ValidChain() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);

        bytes32 msgHash = keccak256("dstack-says-hello");
        CrossAttestationBridge.DstackProof memory proof = _buildDstackProof(msgHash);

        bridge.registerDstack(channelId, proof, "dstack-payload");

        (, , , bool ghV, bool dsV) = bridge.getChannel(channelId);
        assertFalse(ghV);
        assertTrue(dsV);
    }

    function test_RegisterDstack_RevertAlreadyRegistered() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("msg")), "p1");

        vm.expectRevert(CrossAttestationBridge.AlreadyRegistered.selector);
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("msg2")), "p2");
    }

    function test_RegisterDstack_EmitsEvent() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);

        vm.expectEmit(true, false, false, true);
        emit CrossAttestationBridge.DstackAttested(channelId, appId);
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("m")), "");
    }

    function test_RegisterDstack_WrongAppId() public {
        // Channel requires appId 0xDEAD, but we construct proof for a different appId
        bytes32 wrongAppId = bytes32(bytes20(uint160(0xBEEF)));
        bridge.createChannel(channelId, repoHash, commitSha, wrongAppId);

        // The proof's KMS message embeds appId 0xDEAD (hardcoded in _buildDstackProof)
        // so KMS recovery will fail since the contract uses requiredAppId=0xBEEF
        CrossAttestationBridge.DstackProof memory proof = _buildDstackProof(keccak256("m"));
        vm.expectRevert(CrossAttestationBridge.InvalidDstackSignature.selector);
        bridge.registerDstack(channelId, proof, "");
    }

    // --- Mutual attestation ---

    function test_NotMutuallyAttestedInitially() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        assertFalse(bridge.isMutuallyAttested(channelId));
    }

    function test_NotMutuallyAttestedWithOnlyGitHub() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "gh");
        assertFalse(bridge.isMutuallyAttested(channelId));
    }

    function test_NotMutuallyAttestedWithOnlyDstack() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("m")), "ds");
        assertFalse(bridge.isMutuallyAttested(channelId));
    }

    function test_GetPayloads_RevertsIfNotMutual() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "gh");

        vm.expectRevert(CrossAttestationBridge.NotMutuallyAttested.selector);
        bridge.getPayloads(channelId);
    }

    // --- Full integration: both sides attest ---

    function test_FullMutualAttestation_GitHubFirst() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);

        // GitHub first
        mockVerifier.setAttestation(sha256("github-artifact"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "github-pubkey");
        assertFalse(bridge.isMutuallyAttested(channelId));

        // Then Dstack
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("handshake")), "dstack-secret");
        assertTrue(bridge.isMutuallyAttested(channelId));

        (bytes memory ghP, bytes memory dsP) = bridge.getPayloads(channelId);
        assertEq(ghP, "github-pubkey");
        assertEq(dsP, "dstack-secret");
    }

    function test_FullMutualAttestation_DstackFirst() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);

        // Dstack first
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("handshake")), "dstack-secret");
        assertFalse(bridge.isMutuallyAttested(channelId));

        // Then GitHub
        mockVerifier.setAttestation(sha256("github-artifact"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "github-pubkey");
        assertTrue(bridge.isMutuallyAttested(channelId));
    }

    function test_MutuallyAttested_EmitsEvent_OnSecondRegistration() public {
        bridge.createChannel(channelId, repoHash, commitSha, appId);
        mockVerifier.setAttestation(sha256("art"), repoHash, commitSha);
        bridge.registerGitHub(channelId, "", new bytes32[](0), "gh");

        vm.expectEmit(true, false, false, false);
        emit CrossAttestationBridge.MutuallyAttested(channelId);
        bridge.registerDstack(channelId, _buildDstackProof(keccak256("m")), "ds");
    }

    // --- Multiple independent channels ---

    function test_IndependentChannels() public {
        bytes32 ch1 = keccak256("ch1");
        bytes32 ch2 = keccak256("ch2");

        bridge.createChannel(ch1, repoHash, commitSha, appId);
        bridge.createChannel(ch2, sha256("other/repo"), bytes20(0), appId);

        // Attest ch1 fully
        mockVerifier.setAttestation(sha256("art1"), repoHash, commitSha);
        bridge.registerGitHub(ch1, "", new bytes32[](0), "g1");
        bridge.registerDstack(ch1, _buildDstackProof(keccak256("m1")), "d1");

        // ch2 is independent
        assertTrue(bridge.isMutuallyAttested(ch1));
        assertFalse(bridge.isMutuallyAttested(ch2));
    }
}
