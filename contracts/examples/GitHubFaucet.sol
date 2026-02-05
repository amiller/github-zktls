// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title GitHubFaucet
/// @notice Testnet faucet that distributes ETH to unique GitHub users (one claim per day)
contract GitHubFaucet {
    ISigstoreVerifier public immutable verifier;
    address public immutable owner;

    uint256 public constant COOLDOWN = 1 days;
    uint256 public constant MAX_CLAIM = 0.001 ether;
    uint256 public constant RESERVE_DIVISOR = 20;

    mapping(bytes32 => uint256) public lastClaim;
    bytes20 public requiredCommitSha;

    event Claimed(address indexed recipient, string indexed username, uint256 amount);
    event RequirementsUpdated(bytes20 commitSha);

    error InvalidProof();
    error CertificateMismatch();
    error UsernameMismatch();
    error RecipientMismatch();
    error WrongCommit();
    error AlreadyClaimedToday();
    error FaucetEmpty();
    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _verifier, bytes20 _requiredCommitSha) {
        verifier = ISigstoreVerifier(_verifier);
        owner = msg.sender;
        requiredCommitSha = _requiredCommitSha;
    }

    receive() external payable {}

    /// @notice Claim testnet ETH by proving GitHub identity
    function claim(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate,
        string calldata username,
        address payable recipient
    ) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();

        bytes memory usernamePattern = abi.encodePacked('"github_actor": "', username, '"');
        if (!containsBytes(certificate, usernamePattern)) revert UsernameMismatch();

        bytes memory recipientPattern = abi.encodePacked('"recipient_address": "', addressToHex(recipient), '"');
        if (!containsBytes(certificate, recipientPattern)) revert RecipientMismatch();

        if (requiredCommitSha != bytes20(0) && att.commitSha != requiredCommitSha) {
            revert WrongCommit();
        }

        bytes32 userKey = keccak256(bytes(toLower(username)));
        if (block.timestamp - lastClaim[userKey] < COOLDOWN) revert AlreadyClaimedToday();
        lastClaim[userKey] = block.timestamp;

        uint256 amount = address(this).balance / RESERVE_DIVISOR;
        if (amount > MAX_CLAIM) amount = MAX_CLAIM;
        if (amount == 0) revert FaucetEmpty();

        emit Claimed(recipient, username, amount);
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    function setRequirements(bytes20 _commitSha) external onlyOwner {
        requiredCommitSha = _commitSha;
        emit RequirementsUpdated(_commitSha);
    }

    function canClaim(string calldata username) external view returns (bool, uint256 nextClaimTime) {
        bytes32 userKey = keccak256(bytes(toLower(username)));
        uint256 last = lastClaim[userKey];
        if (block.timestamp - last >= COOLDOWN) {
            return (true, 0);
        }
        return (false, last + COOLDOWN);
    }

    function claimAmount() external view returns (uint256) {
        uint256 amount = address(this).balance / RESERVE_DIVISOR;
        return amount > MAX_CLAIM ? MAX_CLAIM : amount;
    }

    function containsBytes(bytes calldata haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length > haystack.length) return false;
        uint256 end = haystack.length - needle.length + 1;
        for (uint256 i = 0; i < end; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function toLower(string calldata s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory lower = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                lower[i] = bytes1(uint8(b[i]) + 32);
            } else {
                lower[i] = b[i];
            }
        }
        return string(lower);
    }

    function addressToHex(address a) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";
        uint160 value = uint160(a);
        for (uint256 i = 41; i > 1; i--) {
            result[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        return string(result);
    }
}
