// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title EmailNFT
/// @notice ERC-721 NFT minted by proving email ownership via Sigstore-attested challenge-response
contract EmailNFT {
    ISigstoreVerifier public immutable verifier;
    address public immutable owner;

    string public name = "Email Identity";
    string public symbol = "EMAIL";

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(bytes32 => bool) public claimed;
    mapping(uint256 => string) public emailOf;

    bytes20 public requiredCommitSha;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Claimed(address indexed recipient, string email, uint256 tokenId);
    event RequirementsUpdated(bytes20 commitSha);

    error InvalidProof();
    error CertificateMismatch();
    error EmailMismatch();
    error RecipientMismatch();
    error WrongCommit();
    error AlreadyClaimed();
    error NotOwner();
    error NotAuthorized();
    error InvalidRecipient();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _verifier, bytes20 _requiredCommitSha) {
        verifier = ISigstoreVerifier(_verifier);
        owner = msg.sender;
        requiredCommitSha = _requiredCommitSha;
    }

    function claim(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate,
        string calldata email,
        address recipient
    ) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();

        bytes memory emailPattern = abi.encodePacked('"email": "', email, '"');
        if (!containsBytes(certificate, emailPattern)) revert EmailMismatch();

        bytes memory recipientPattern = abi.encodePacked('"recipient_address": "', addressToHex(recipient), '"');
        if (!containsBytes(certificate, recipientPattern)) revert RecipientMismatch();

        if (requiredCommitSha != bytes20(0) && att.commitSha != requiredCommitSha)
            revert WrongCommit();

        bytes32 emailKey = keccak256(bytes(toLower(email)));
        if (claimed[emailKey]) revert AlreadyClaimed();
        claimed[emailKey] = true;

        uint256 tokenId = uint256(emailKey);
        emailOf[tokenId] = toLower(email);
        _mint(recipient, tokenId);
        totalSupply++;

        emit Claimed(recipient, email, tokenId);
    }

    function setRequirements(bytes20 _commitSha) external onlyOwner {
        requiredCommitSha = _commitSha;
        emit RequirementsUpdated(_commitSha);
    }

    function isClaimed(string calldata email) external view returns (bool) {
        return claimed[keccak256(bytes(toLower(email)))];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (ownerOf[tokenId] == address(0)) revert InvalidRecipient();
        string memory email = emailOf[tokenId];
        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="250" viewBox="0 0 400 250">'
            '<defs><linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">'
            '<stop offset="0%" style="stop-color:#1a1a2e"/><stop offset="100%" style="stop-color:#16213e"/></linearGradient></defs>'
            '<rect width="400" height="250" rx="16" fill="url(#g)"/>'
            '<text x="24" y="40" fill="#4ecca3" font-family="monospace" font-size="12" opacity="0.7">VERIFIED EMAIL</text>'
            '<text x="24" y="80" fill="#fff" font-family="monospace" font-size="18" font-weight="bold">',
            _escapeXml(email),
            '</text>'
            '<circle cx="24" cy="210" r="6" fill="#4ecca3"/><text x="38" y="215" fill="#4ecca3" font-family="monospace" font-size="12">on-chain</text>'
            '<text x="376" y="236" fill="#555" font-family="monospace" font-size="10" text-anchor="end">Email Identity NFT</text>'
            '</svg>'
        ));
        string memory json = string(abi.encodePacked(
            '{"name":"', _escapeJson(email), '","description":"Verified email identity","image":"data:image/svg+xml;base64,', _base64(bytes(svg)), '"}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(json))));
    }

    // --- Minimal ERC-721 ---

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf[tokenId];
        if (msg.sender != tokenOwner && !isApprovedForAll[tokenOwner][msg.sender]) revert NotAuthorized();
        getApproved[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert InvalidRecipient();
        address tokenOwner = ownerOf[tokenId];
        if (from != tokenOwner) revert NotAuthorized();
        if (msg.sender != from && msg.sender != getApproved[tokenId] && !isApprovedForAll[from][msg.sender])
            revert NotAuthorized();
        balanceOf[from]--;
        balanceOf[to]++;
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7; // ERC721 || ERC165
    }

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert InvalidRecipient();
        ownerOf[tokenId] = to;
        balanceOf[to]++;
        emit Transfer(address(0), to, tokenId);
    }

    // --- Helpers (shared with GitHubFaucet) ---

    function containsBytes(bytes calldata haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length > haystack.length) return false;
        uint256 end = haystack.length - needle.length + 1;
        for (uint256 i = 0; i < end; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
            }
            if (found) return true;
        }
        return false;
    }

    function toLower(string calldata s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory lower = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            lower[i] = (b[i] >= 0x41 && b[i] <= 0x5A) ? bytes1(uint8(b[i]) + 32) : b[i];
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

    function _escapeXml(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 5);
        uint256 len;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == "<") { out[len++] = "&"; out[len++] = "l"; out[len++] = "t"; out[len++] = ";"; }
            else if (b[i] == ">") { out[len++] = "&"; out[len++] = "g"; out[len++] = "t"; out[len++] = ";"; }
            else if (b[i] == "&") { out[len++] = "&"; out[len++] = "a"; out[len++] = "m"; out[len++] = "p"; out[len++] = ";"; }
            else if (b[i] == '"') { out[len++] = "&"; out[len++] = "q"; out[len++] = "u"; out[len++] = "o"; out[len++] = "t"; out[len++] = ";"; }
            else out[len++] = b[i];
        }
        bytes memory trimmed = new bytes(len);
        for (uint256 i = 0; i < len; i++) trimmed[i] = out[i];
        return string(trimmed);
    }

    function _escapeJson(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 2);
        uint256 len;
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == '"' || b[i] == "\\") { out[len++] = "\\"; }
            out[len++] = b[i];
        }
        bytes memory trimmed = new bytes(len);
        for (uint256 i = 0; i < len; i++) trimmed[i] = out[i];
        return string(trimmed);
    }

    bytes internal constant B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function _base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 outLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(outLen);
        uint256 i;
        uint256 j;
        for (i = 0; i + 2 < data.length; i += 3) {
            uint256 v = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i+1])) << 8) | uint256(uint8(data[i+2]));
            result[j++] = B64[(v >> 18) & 0x3F];
            result[j++] = B64[(v >> 12) & 0x3F];
            result[j++] = B64[(v >> 6) & 0x3F];
            result[j++] = B64[v & 0x3F];
        }
        if (data.length % 3 == 1) {
            uint256 v = uint256(uint8(data[i])) << 16;
            result[j++] = B64[(v >> 18) & 0x3F];
            result[j++] = B64[(v >> 12) & 0x3F];
            result[j++] = "=";
            result[j++] = "=";
        } else if (data.length % 3 == 2) {
            uint256 v = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i+1])) << 8);
            result[j++] = B64[(v >> 18) & 0x3F];
            result[j++] = B64[(v >> 12) & 0x3F];
            result[j++] = B64[(v >> 6) & 0x3F];
            result[j++] = "=";
        }
        return string(result);
    }
}
