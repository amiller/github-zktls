// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {GitHubFaucet} from "../examples/GitHubFaucet.sol";
import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

contract MockSigstoreVerifier is ISigstoreVerifier {
    bytes32 public artifactHash;
    bytes32 public repoHash;
    bytes20 public commitSha;

    function setAttestation(bytes32 _artifact, bytes32 _repo, bytes20 _commit) external {
        artifactHash = _artifact;
        repoHash = _repo;
        commitSha = _commit;
    }

    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }

    function verifyAndDecode(bytes calldata, bytes32[] calldata)
        external view returns (Attestation memory)
    {
        return Attestation(artifactHash, repoHash, commitSha);
    }

    function decodePublicInputs(bytes32[] calldata)
        external pure returns (Attestation memory)
    {
        return Attestation(bytes32(0), bytes32(0), bytes20(0));
    }
}

contract GitHubFaucetTest is Test {
    GitHubFaucet faucet;
    MockSigstoreVerifier mockVerifier;
    address owner;

    function setUp() public {
        owner = address(this);
        mockVerifier = new MockSigstoreVerifier();
        faucet = new GitHubFaucet(address(mockVerifier), bytes20(0));
        vm.deal(address(faucet), 10 ether);
        vm.warp(100 days);
    }

    // ==================== Security Tests ====================

    function test_SetRequirements_RequiresOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(GitHubFaucet.NotOwner.selector);
        faucet.setRequirements(bytes20(uint160(0xdead)));
    }

    function test_SetRequirements_OwnerCanSet() public {
        faucet.setRequirements(bytes20(uint160(0xdead)));
        assertEq(faucet.requiredCommitSha(), bytes20(uint160(0xdead)));
    }

    function test_RecipientMustMatchCertificate() public {
        address payable alice = payable(address(0x1111111111111111111111111111111111111111));
        address payable attacker = payable(address(0x2222222222222222222222222222222222222222));

        bytes memory certificate = bytes(
            '{"github_actor": "alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certificate), bytes32(0), bytes20(0));

        vm.expectRevert(GitHubFaucet.RecipientMismatch.selector);
        faucet.claim("", new bytes32[](0), certificate, "alice", attacker);
    }

    function test_CaseInsensitiveCooldown() public {
        address payable alice = payable(address(0x1111111111111111111111111111111111111111));

        bytes memory certLower = bytes(
            '{"github_actor": "alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certLower), bytes32(0), bytes20(0));
        faucet.claim("", new bytes32[](0), certLower, "alice", alice);

        bytes memory certUpper = bytes(
            '{"github_actor": "Alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certUpper), bytes32(0), bytes20(0));

        vm.expectRevert(GitHubFaucet.AlreadyClaimedToday.selector);
        faucet.claim("", new bytes32[](0), certUpper, "Alice", alice);
    }

    function test_CommitRequirementEnforced() public {
        address payable alice = payable(address(0x1111111111111111111111111111111111111111));

        faucet.setRequirements(bytes20(uint160(0x123456)));

        bytes memory certificate = bytes(
            '{"github_actor": "alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certificate), bytes32(0), bytes20(uint160(0xBAD)));

        vm.expectRevert(GitHubFaucet.WrongCommit.selector);
        faucet.claim("", new bytes32[](0), certificate, "alice", alice);
    }

    // ==================== Happy Path Tests ====================

    function test_LegitimateClaimSucceeds() public {
        address payable alice = payable(address(0x1111111111111111111111111111111111111111));

        bytes memory certificate = bytes(
            '{"github_actor": "alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certificate), bytes32(0), bytes20(0));

        uint256 balanceBefore = alice.balance;
        faucet.claim("", new bytes32[](0), certificate, "alice", alice);
        assertGt(alice.balance, balanceBefore);
    }

    function test_ClaimWithPinnedCommit() public {
        address payable alice = payable(address(0x1111111111111111111111111111111111111111));
        bytes20 commit = bytes20(uint160(0xABCDEF));

        faucet.setRequirements(commit);

        bytes memory certificate = bytes(
            '{"github_actor": "alice", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mockVerifier.setAttestation(sha256(certificate), bytes32(0), commit);

        uint256 balanceBefore = alice.balance;
        faucet.claim("", new bytes32[](0), certificate, "alice", alice);
        assertGt(alice.balance, balanceBefore);
    }
}
