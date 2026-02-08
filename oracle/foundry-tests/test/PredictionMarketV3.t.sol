// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarketV3.sol";
import {ISigstoreVerifier} from "../../../contracts/src/ISigstoreVerifier.sol";

/**
 * @title Unit Tests for PredictionMarket V3
 * @notice Tests ISigstoreVerifier integration and trustless settlement
 */

contract MockSigstoreVerifier is ISigstoreVerifier {
    bytes32 public artifactHash;
    bytes32 public repoHash;
    bytes20 public commitSha;
    bool public shouldRevert;

    function setAttestation(bytes32 _artifact, bytes32 _repo, bytes20 _commit) external {
        artifactHash = _artifact;
        repoHash = _repo;
        commitSha = _commit;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function verify(bytes calldata, bytes32[] calldata) external view returns (bool) {
        if (shouldRevert) revert("Mock verification failed");
        return true;
    }

    function verifyAndDecode(bytes calldata, bytes32[] calldata)
        external view returns (Attestation memory)
    {
        if (shouldRevert) revert("Mock verification failed");
        return Attestation(artifactHash, repoHash, commitSha);
    }

    function decodePublicInputs(bytes32[] calldata)
        external pure returns (Attestation memory)
    {
        return Attestation(bytes32(0), bytes32(0), bytes20(0));
    }
}

contract PredictionMarketV3Test is Test {
    PredictionMarket public market;
    MockSigstoreVerifier public mockVerifier;
    
    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public settler = address(0x3);
    
    uint256 constant DEADLINE = 1000000;
    string constant REPO = "claw-tee-dah/github-zktls";
    bytes20 constant COMMIT_SHA = bytes20(uint160(0xabcdef123456));
    
    function setUp() public {
        mockVerifier = new MockSigstoreVerifier();
        market = new PredictionMarket(address(mockVerifier));
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(settler, 100 ether);
    }
    
    // ========== Market Creation Tests ==========
    
    function testCreateMarket() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Will 'radicle' be mentioned?",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        assertEq(marketId, 0);
        
        (
            string memory description,
            bytes32 conditionHash,
            bytes32 repoHash,
            bytes20 oracleCommitSha,
            uint256 deadline,
            bool settled,
            bool result,
            uint256 yesPool,
            uint256 noPool
        ) = market.getMarket(marketId);
        
        assertEq(description, "Will 'radicle' be mentioned?");
        assertEq(conditionHash, keccak256(abi.encode("12345", "radicle", "first")));
        assertEq(repoHash, keccak256(bytes(REPO)));
        assertEq(oracleCommitSha, COMMIT_SHA);
        assertEq(deadline, DEADLINE);
        assertFalse(settled);
        assertFalse(result);
        assertEq(yesPool, 0);
        assertEq(noPool, 0);
    }
    
    function testCreateMarketRevertsIfDeadlineInPast() public {
        vm.warp(DEADLINE + 1);
        
        vm.expectRevert(PredictionMarket.InvalidDeadline.selector);
        market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
    }
    
    // ========== Betting Tests ==========
    
    function testBetYes() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        (uint256 yesShares, uint256 noShares, bool claimed) = market.getBet(marketId, alice);
        assertEq(yesShares, 1 ether);
        assertEq(noShares, 0);
        assertFalse(claimed);
        
        (,,,,,,,uint256 yesPool,) = market.getMarket(marketId);
        assertEq(yesPool, 1 ether);
    }
    
    function testBetNo() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, false);
        
        (uint256 yesShares, uint256 noShares, bool claimed) = market.getBet(marketId, bob);
        assertEq(yesShares, 0);
        assertEq(noShares, 2 ether);
        assertFalse(claimed);
        
        (,,,,,,,,uint256 noPool) = market.getMarket(marketId);
        assertEq(noPool, 2 ether);
    }
    
    function testBetRevertsIfZero() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.ZeroBet.selector);
        market.bet{value: 0}(marketId, true);
    }
    
    function testBetRevertsAfterDeadline() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.warp(DEADLINE + 1);
        
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.BettingClosed.selector);
        market.bet{value: 1 ether}(marketId, true);
    }
    
    // ========== Settlement Tests (ISigstoreVerifier Integration) ==========
    
    function testSettleWithValidProof() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Create oracle certificate
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Mock verifier to return correct attestation
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        // Anyone can settle (no authorization needed)
        vm.prank(settler);
        market.settle(
            marketId,
            "", // proof
            new bytes32[](0), // publicInputs
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        (,,,,,bool settled, bool result,,) = market.getMarket(marketId);
        assertTrue(settled);
        assertTrue(result); // YES wins (found=true)
    }
    
    function testSettleRevertsIfInvalidProof() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Make verifier revert
        mockVerifier.setShouldRevert(true);
        
        vm.prank(settler);
        vm.expectRevert("Mock verification failed");
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
    
    function testSettleRevertsIfCertificateHashMismatch() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Wrong certificate hash
        mockVerifier.setAttestation(
            bytes32(uint256(0xdeadbeef)),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.CertificateMismatch.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
    
    function testSettleRevertsIfWrongCommit() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Wrong commit SHA
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            bytes20(uint160(0xBADC0FFEE))
        );
        
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.WrongCommit.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
    
    function testSettleRevertsIfWrongRepo() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Wrong repo hash
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes("attacker/fake-repo")),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.WrongRepo.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
    
    function testSettleRevertsIfParameterMismatch() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "99999", "keyword": "bitcoin", "oracle_type": "any"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        // Try to settle with wrong parameters
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "99999", // Wrong topic
            "bitcoin", // Wrong keyword
            "any" // Wrong oracle type
        );
    }
    
    function testSettleRevertsIfNotSettleable() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Certificate with settleable=false (NO_COMMENTS state)
        bytes memory certificate = bytes(
            '{"settleable": false, "found": false, "result": "NO_COMMENTS", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.NotSettleable.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
    
    function testSettleYesWins() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // found=true means YES wins
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        (,,,,,bool settled, bool result,,) = market.getMarket(marketId);
        assertTrue(settled);
        assertTrue(result); // YES wins
    }
    
    function testSettleNoWins() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        vm.warp(DEADLINE + 1);
        
        // found=false means NO wins
        bytes memory certificate = bytes(
            '{"settleable": true, "found": false, "result": "NOT_FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        (,,,,,bool settled, bool result,,) = market.getMarket(marketId);
        assertTrue(settled);
        assertFalse(result); // NO wins
    }
    
    // ========== Claim Tests ==========
    
    function testClaimWinnings() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true); // Alice bets YES
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false); // Bob bets NO
        
        vm.warp(DEADLINE + 1);
        
        // Settle as YES wins
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        // Alice claims (she bet YES and won)
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        market.claim(marketId);
        
        // Alice gets entire pool (3 ETH + 1 ETH = 4 ETH)
        assertEq(alice.balance - aliceBalanceBefore, 4 ether);
    }
    
    function testClaimProportionalPayout() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        // Alice bets 2 ETH on YES
        vm.prank(alice);
        market.bet{value: 2 ether}(marketId, true);
        
        // Bob bets 2 ETH on YES
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, true);
        
        // Settler bets 4 ETH on NO
        vm.prank(settler);
        market.bet{value: 4 ether}(marketId, false);
        
        vm.warp(DEADLINE + 1);
        
        // Settle as YES wins
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        // Total pot: 8 ETH
        // Alice has 2/4 YES shares = 50%
        // Bob has 2/4 YES shares = 50%
        
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        market.claim(marketId);
        assertEq(alice.balance - aliceBalanceBefore, 4 ether);
        
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        market.claim(marketId);
        assertEq(bob.balance - bobBalanceBefore, 4 ether);
    }
    
    function testClaimRevertsIfNoWinningBet() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, false); // Alice bets NO
        
        vm.warp(DEADLINE + 1);
        
        // Settle as YES wins
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        // Alice bet NO but YES won
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.NoWinningBet.selector);
        market.claim(marketId);
    }
    
    function testClaimRevertsIfAlreadyClaimed() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        vm.prank(alice);
        market.claim(marketId);
        
        // Try to claim again
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.AlreadyClaimed.selector);
        market.claim(marketId);
    }
    
    // ========== View Function Tests ==========
    
    function testGetOdds() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        // Initial odds (no bets)
        (uint256 yesOdds, uint256 noOdds) = market.getOdds(marketId);
        assertEq(yesOdds, 5000); // 50%
        assertEq(noOdds, 5000); // 50%
        
        // After bets (3 ETH YES, 1 ETH NO)
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        (yesOdds, noOdds) = market.getOdds(marketId);
        assertEq(yesOdds, 7500); // 75%
        assertEq(noOdds, 2500); // 25%
    }
    
    function testGetPotentialPayout() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 2 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, false);
        
        (uint256 ifYesWins, uint256 ifNoWins) = market.getPotentialPayout(marketId, alice);
        assertEq(ifYesWins, 4 ether); // Alice gets entire pot if YES wins
        assertEq(ifNoWins, 0); // Alice gets nothing if NO wins
    }
    
    // ========== Security Tests ==========
    
    function testAnyoneCanSettle() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": true, "result": "FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes(REPO)),
            COMMIT_SHA
        );
        
        // Random address can settle (no authorization required)
        address randomSettler = address(0x999);
        vm.prank(randomSettler);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
        
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertTrue(settled);
    }
    
    function testCannotSettleWithoutValidProof() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            REPO,
            COMMIT_SHA,
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        bytes memory certificate = bytes(
            '{"settleable": true, "found": false, "result": "NOT_FOUND", '
            '"topic_id": "12345", "keyword": "radicle", "oracle_type": "first"}'
        );
        
        // Attacker tries to settle with wrong attestation
        mockVerifier.setAttestation(
            sha256(certificate),
            keccak256(bytes("attacker/repo")),
            COMMIT_SHA
        );
        
        vm.prank(settler);
        vm.expectRevert(PredictionMarket.WrongRepo.selector);
        market.settle(
            marketId,
            "",
            new bytes32[](0),
            certificate,
            "12345",
            "radicle",
            "first"
        );
    }
}
