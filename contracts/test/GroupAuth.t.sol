// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {GroupAuth} from "../examples/GroupAuth.sol";
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

contract GroupAuthTest is Test {
    GroupAuth ga;
    MockSigstoreVerifier mockVerifier;

    // Dstack key hierarchy (same as CrossAttestationBridge tests)
    uint256 kmsPriv = 0xA11CE;
    uint256 appPriv = 0xB0B;
    uint256 derivedPriv = 0xCA7;

    bytes constant APP_PUBKEY = hex"035d45cb81aa765d69ca52e3869491ecf0e8fdf6a63d64e65b5213647ee4973ae5";
    bytes constant DERIVED_PUBKEY = hex"0203dffc4af6214b639839fbc2b949621a35ae41bbe7679eee5798afbe85919f69";

    address kmsRoot;
    bytes32 appId = bytes32(bytes20(uint160(0xDEAD)));
    bytes20 commitSha = bytes20(hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    bytes32 repoHash = sha256("owner/repo");

    // GitHub "nodes" with real keypairs (for ownership signatures)
    uint256 ghPriv1 = 0xD00D1;
    uint256 ghPriv2 = 0xD00D2;
    bytes constant GH_PUBKEY1 = hex"0320c97283c8dbee8a3c74443f5aa8a383071903f21277e8945732686283c04497";
    bytes constant GH_PUBKEY2 = hex"034b1084f2310ebc9590a0a2d57e34cebf8c0f589f71be94d0b98a500fdb1d9d5a";

    bytes32 ghCodeId; // bytes32(commitSha)

    function setUp() public {
        kmsRoot = vm.addr(kmsPriv);
        mockVerifier = new MockSigstoreVerifier();
        ga = new GroupAuth(address(mockVerifier), kmsRoot);
        ghCodeId = bytes32(commitSha);

        // Owner allows both code identities
        ga.addAllowedCode(ghCodeId);
        ga.addAllowedCode(appId);

        // Set up mock verifier for GitHub proofs
        mockVerifier.setAttestation(sha256("artifact"), repoHash, commitSha);
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

    function _buildDstackProof(bytes32 messageHash) internal pure returns (GroupAuth.DstackProof memory) {
        bytes32 appId_ = bytes32(bytes20(uint160(0xDEAD)));
        string memory derivedHex = _bytesToHex(DERIVED_PUBKEY);
        string memory appMessage = string(abi.encodePacked("ethereum:", derivedHex));
        bytes memory appSignature = _sign(0xB0B, keccak256(bytes(appMessage)));
        bytes memory kmsSignature = _sign(0xA11CE, keccak256(abi.encodePacked("dstack-kms-issued:", bytes20(appId_), APP_PUBKEY)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        bytes memory messageSignature = _sign(0xCA7, ethHash);

        return GroupAuth.DstackProof({
            messageHash: messageHash,
            messageSignature: messageSignature,
            appSignature: appSignature,
            kmsSignature: kmsSignature,
            derivedCompressedPubkey: DERIVED_PUBKEY,
            appCompressedPubkey: APP_PUBKEY,
            purpose: "ethereum"
        });
    }

    function _registerGitHub(uint256 privKey, bytes memory pubkey) internal returns (bytes32) {
        bytes memory proof = "";
        bytes32 proofHash = keccak256(proof);
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", proofHash));
        bytes memory ownershipSig = _sign(privKey, ethHash);
        return ga.registerGitHub(proof, new bytes32[](0), pubkey, ownershipSig);
    }

    function _registerDstack() internal returns (bytes32) {
        return ga.registerDstack(appId, _buildDstackProof(keccak256("handshake")));
    }

    // --- Admin ---

    function test_AddAllowedCode() public {
        bytes32 newCode = keccak256("new-code");
        vm.expectEmit(true, false, false, false);
        emit GroupAuth.AllowedCodeAdded(newCode);
        ga.addAllowedCode(newCode);
        assertTrue(ga.allowedCode(newCode));
    }

    function test_RemoveAllowedCode() public {
        ga.removeAllowedCode(ghCodeId);
        assertFalse(ga.allowedCode(ghCodeId));
    }

    function test_OnlyOwnerCanManageCode() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(GroupAuth.NotOwner.selector);
        ga.addAllowedCode(keccak256("x"));
    }

    // --- GitHub registration ---

    function test_RegisterGitHub() public {
        bytes32 memberId = _registerGitHub(ghPriv1, GH_PUBKEY1);
        assertEq(memberId, keccak256(GH_PUBKEY1));
        assertTrue(ga.isMember(memberId));

        (bytes32 codeId, bytes memory pubkey, uint256 registeredAt) = ga.getMember(memberId);
        assertEq(codeId, ghCodeId);
        assertEq(pubkey, GH_PUBKEY1);
        assertGt(registeredAt, 0);
    }

    function test_RegisterGitHub_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit GroupAuth.MemberRegistered(keccak256(GH_PUBKEY1), ghCodeId, GH_PUBKEY1);
        _registerGitHub(ghPriv1, GH_PUBKEY1);
    }

    function test_RegisterGitHub_RevertCodeNotAllowed() public {
        mockVerifier.setAttestation(sha256("art"), repoHash, bytes20(hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"));
        vm.expectRevert(GroupAuth.CodeNotAllowed.selector);
        _registerGitHub(ghPriv1, GH_PUBKEY1);
    }

    function test_RegisterGitHub_RevertDuplicate() public {
        _registerGitHub(ghPriv1, GH_PUBKEY1);
        vm.expectRevert(GroupAuth.AlreadyRegistered.selector);
        _registerGitHub(ghPriv1, GH_PUBKEY1);
    }

    function test_RegisterGitHub_RevertBadOwnershipSig() public {
        bytes memory proof = "";
        bytes32 proofHash = keccak256(proof);
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", proofHash));
        bytes memory wrongSig = _sign(ghPriv2, ethHash); // sign with wrong key
        vm.expectRevert(GroupAuth.InvalidOwnershipProof.selector);
        ga.registerGitHub(proof, new bytes32[](0), GH_PUBKEY1, wrongSig);
    }

    // --- Dstack registration ---

    function test_RegisterDstack() public {
        bytes32 memberId = _registerDstack();
        assertEq(memberId, keccak256(DERIVED_PUBKEY));
        assertTrue(ga.isMember(memberId));

        (bytes32 codeId,,) = ga.getMember(memberId);
        assertEq(codeId, appId);
    }

    function test_RegisterDstack_RevertBadChain() public {
        bytes32 wrongAppId = bytes32(bytes20(uint160(0xBEEF)));
        ga.addAllowedCode(wrongAppId);
        vm.expectRevert(GroupAuth.InvalidDstackSignature.selector);
        ga.registerDstack(wrongAppId, _buildDstackProof(keccak256("m")));
    }

    function test_RegisterDstack_RevertCodeNotAllowed() public {
        ga.removeAllowedCode(appId);
        vm.expectRevert(GroupAuth.CodeNotAllowed.selector);
        ga.registerDstack(appId, _buildDstackProof(keccak256("m")));
    }

    // --- Onboarding ---

    function test_Onboard() public {
        bytes32 m1 = _registerGitHub(ghPriv1, GH_PUBKEY1);
        bytes32 m2 = _registerGitHub(ghPriv2, GH_PUBKEY2);

        ga.onboard(m1, m2, "encrypted_secret");

        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(m2);
        assertEq(msgs.length, 1);
        assertEq(msgs[0].fromMember, m1);
        assertEq(msgs[0].encryptedPayload, "encrypted_secret");
    }

    function test_Onboard_EmitsEvent() public {
        bytes32 m1 = _registerGitHub(ghPriv1, GH_PUBKEY1);
        bytes32 m2 = _registerGitHub(ghPriv2, GH_PUBKEY2);

        vm.expectEmit(true, true, false, false);
        emit GroupAuth.OnboardingPosted(m2, m1);
        ga.onboard(m1, m2, "secret");
    }

    function test_Onboard_RevertFromNotMember() public {
        bytes32 m2 = _registerGitHub(ghPriv2, GH_PUBKEY2);
        bytes32 fakeId = keccak256("nobody");

        vm.expectRevert(GroupAuth.MemberNotFound.selector);
        ga.onboard(fakeId, m2, "secret");
    }

    function test_Onboard_RevertToNotMember() public {
        bytes32 m1 = _registerGitHub(ghPriv1, GH_PUBKEY1);
        bytes32 fakeId = keccak256("nobody");

        vm.expectRevert(GroupAuth.MemberNotFound.selector);
        ga.onboard(m1, fakeId, "secret");
    }

    function test_Onboard_MultipleHelpers() public {
        bytes32 m1 = _registerGitHub(ghPriv1, GH_PUBKEY1);
        bytes32 m2 = _registerDstack();
        bytes32 m3 = _registerGitHub(ghPriv2, GH_PUBKEY2);

        ga.onboard(m1, m3, "from_gh");
        ga.onboard(m2, m3, "from_ds");

        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(m3);
        assertEq(msgs.length, 2);
        assertEq(msgs[0].fromMember, m1);
        assertEq(msgs[1].fromMember, m2);
    }

    // --- Integration: GitHub → GitHub ---

    function test_Integration_GitHubToGitHub() public {
        // Node A registers via GitHub proof
        bytes32 nodeA = _registerGitHub(ghPriv1, GH_PUBKEY1);
        assertTrue(ga.isMember(nodeA));

        // Node B registers via GitHub proof (different pubkey, same code)
        bytes32 nodeB = _registerGitHub(ghPriv2, GH_PUBKEY2);
        assertTrue(ga.isMember(nodeB));

        // Node A onboards Node B with encrypted group secret
        bytes memory encryptedSecret = abi.encodePacked("gh-to-gh-secret-encrypted-to-B");
        ga.onboard(nodeA, nodeB, encryptedSecret);

        // Node B reads its onboarding messages
        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(nodeB);
        assertEq(msgs.length, 1);
        assertEq(msgs[0].fromMember, nodeA);
        assertEq(msgs[0].encryptedPayload, encryptedSecret);

        // Both are peers — verify codeIds match
        (bytes32 codeA,,) = ga.getMember(nodeA);
        (bytes32 codeB,,) = ga.getMember(nodeB);
        assertEq(codeA, codeB);
        assertEq(codeA, ghCodeId);
    }

    // --- Integration: GitHub → Dstack ---

    function test_Integration_GitHubToDstack() public {
        // GitHub runner registers first
        bytes32 ghNode = _registerGitHub(ghPriv1, GH_PUBKEY1);

        // Dstack TEE registers
        bytes32 dsNode = _registerDstack();

        // GitHub runner onboards Dstack TEE
        bytes memory encryptedSecret = abi.encodePacked("gh-to-ds-secret");
        ga.onboard(ghNode, dsNode, encryptedSecret);

        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(dsNode);
        assertEq(msgs.length, 1);
        assertEq(msgs[0].fromMember, ghNode);

        // Verify different code identities but both are members
        (bytes32 codeGH,,) = ga.getMember(ghNode);
        (bytes32 codeDS,,) = ga.getMember(dsNode);
        assertEq(codeGH, ghCodeId);
        assertEq(codeDS, appId);
    }

    // --- Integration: Dstack → GitHub ---

    function test_Integration_DstackToGitHub() public {
        // Dstack TEE registers first (long-running, watching events)
        bytes32 dsNode = _registerDstack();

        // GitHub runner spins up and registers
        bytes32 ghNode = _registerGitHub(ghPriv1, GH_PUBKEY1);

        // Dstack sees MemberRegistered event, onboards the GitHub runner
        bytes memory encryptedSecret = abi.encodePacked("ds-to-gh-secret");
        ga.onboard(dsNode, ghNode, encryptedSecret);

        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(ghNode);
        assertEq(msgs.length, 1);
        assertEq(msgs[0].fromMember, dsNode);

        // GitHub runner can now also onboard future members
        bytes32 ghNode2 = _registerGitHub(ghPriv2, GH_PUBKEY2);
        ga.onboard(ghNode, ghNode2, abi.encodePacked("gh-chain-onboard"));

        GroupAuth.OnboardMsg[] memory msgs2 = ga.getOnboarding(ghNode2);
        assertEq(msgs2.length, 1);
        assertEq(msgs2[0].fromMember, ghNode);
    }

    // --- Views ---

    function test_GetMember_NonExistent() public view {
        (bytes32 codeId, bytes memory pubkey, uint256 registeredAt) = ga.getMember(keccak256("nobody"));
        assertEq(codeId, bytes32(0));
        assertEq(pubkey.length, 0);
        assertEq(registeredAt, 0);
    }

    function test_IsMember_False() public view {
        assertFalse(ga.isMember(keccak256("nobody")));
    }

    function test_GetOnboarding_Empty() public view {
        GroupAuth.OnboardMsg[] memory msgs = ga.getOnboarding(keccak256("nobody"));
        assertEq(msgs.length, 0);
    }
}
