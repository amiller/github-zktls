// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {EmailNFT} from "../examples/EmailNFT.sol";
import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

contract MockVerifier is ISigstoreVerifier {
    bytes32 public artifactHash;
    bytes32 public repoHash;
    bytes20 public commitSha;

    function setAttestation(bytes32 _artifact, bytes32 _repo, bytes20 _commit) external {
        artifactHash = _artifact;
        repoHash = _repo;
        commitSha = _commit;
    }

    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) { return true; }

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

contract EmailNFTTest is Test {
    EmailNFT nft;
    MockVerifier mock;
    address payable alice = payable(address(0x1111111111111111111111111111111111111111));
    address payable bob = payable(address(0x2222222222222222222222222222222222222222));

    function setUp() public {
        mock = new MockVerifier();
        nft = new EmailNFT(address(mock), bytes20(0));
    }

    // --- Happy path ---

    function test_ClaimMintsNFT() public {
        bytes memory cert = bytes(
            '{"type": "email-identity", "email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));

        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);

        bytes32 emailKey = keccak256(bytes("alice@example.com"));
        assertEq(nft.ownerOf(uint256(emailKey)), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.totalSupply(), 1);
        assertTrue(nft.isClaimed("alice@example.com"));
    }

    function test_TwoDistinctEmailsClaim() public {
        bytes memory cert1 = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert1), bytes32(0), bytes20(0));
        nft.claim("", new bytes32[](0), cert1, "alice@example.com", alice);

        bytes memory cert2 = bytes(
            '{"email": "bob@example.com", "recipient_address": "0x2222222222222222222222222222222222222222"}'
        );
        mock.setAttestation(sha256(cert2), bytes32(0), bytes20(0));
        nft.claim("", new bytes32[](0), cert2, "bob@example.com", bob);

        assertEq(nft.totalSupply(), 2);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(bob), 1);
    }

    // --- Security ---

    function test_RevertDuplicateEmail() public {
        bytes memory cert = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));
        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);

        // Same email again
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));
        vm.expectRevert(EmailNFT.AlreadyClaimed.selector);
        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);
    }

    function test_RevertDuplicateEmailCaseInsensitive() public {
        bytes memory cert1 = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert1), bytes32(0), bytes20(0));
        nft.claim("", new bytes32[](0), cert1, "alice@example.com", alice);

        bytes memory cert2 = bytes(
            '{"email": "Alice@Example.COM", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert2), bytes32(0), bytes20(0));
        vm.expectRevert(EmailNFT.AlreadyClaimed.selector);
        nft.claim("", new bytes32[](0), cert2, "Alice@Example.COM", alice);
    }

    function test_RevertRecipientMismatch() public {
        bytes memory cert = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));

        vm.expectRevert(EmailNFT.RecipientMismatch.selector);
        nft.claim("", new bytes32[](0), cert, "alice@example.com", bob);
    }

    function test_RevertEmailMismatch() public {
        bytes memory cert = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));

        vm.expectRevert(EmailNFT.EmailMismatch.selector);
        nft.claim("", new bytes32[](0), cert, "bob@example.com", alice);
    }

    function test_RevertCertificateMismatch() public {
        bytes memory cert = bytes('{"email": "alice@example.com"}');
        mock.setAttestation(bytes32(uint256(0xdead)), bytes32(0), bytes20(0)); // wrong hash

        vm.expectRevert(EmailNFT.CertificateMismatch.selector);
        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);
    }

    function test_RevertWrongCommit() public {
        nft.setRequirements(bytes20(uint160(0x123)));

        bytes memory cert = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(uint160(0xBAD)));

        vm.expectRevert(EmailNFT.WrongCommit.selector);
        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);
    }

    function test_SetRequirementsOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(EmailNFT.NotOwner.selector);
        nft.setRequirements(bytes20(uint160(0x123)));
    }

    // --- ERC-721 ---

    function test_Transfer() public {
        bytes memory cert = bytes(
            '{"email": "alice@example.com", "recipient_address": "0x1111111111111111111111111111111111111111"}'
        );
        mock.setAttestation(sha256(cert), bytes32(0), bytes20(0));
        nft.claim("", new bytes32[](0), cert, "alice@example.com", alice);

        uint256 tokenId = uint256(keccak256(bytes("alice@example.com")));
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), bob);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(bob), 1);
    }

    function test_SupportsInterface() public view {
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(nft.supportsInterface(0x01ffc9a7)); // ERC165
        assertFalse(nft.supportsInterface(0xdeadbeef));
    }
}
