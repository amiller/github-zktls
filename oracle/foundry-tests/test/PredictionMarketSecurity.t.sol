// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarket.sol";

/**
 * @title Security Tests for PredictionMarket
 * @notice Tests all critical security issues identified in audit
 */
contract PredictionMarketSecurityTest is Test {
    PredictionMarket public market;
    
    address public owner = address(this);
    address public trustedSettler = address(0xA);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public attacker = address(0x666);
    
    uint256 constant DEADLINE = 1000000;
    
    function setUp() public {
        market = new PredictionMarket();
        market.setTrustedSettler(trustedSettler);
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(attacker, 100 ether);
    }
    
    // ========== CRITICAL ISSUE #1: Parameter Binding ==========
    
    function testParameterBindingRequired() public {
        vm.warp(100);
        
        // Create market with specific parameters
        uint256 marketId = market.createMarket(
            "Will 'radicle' be mentioned in topic 12345?",
            "12345",        // topicId
            "radicle",      // keyword
            "first",        // oracleType
            "repo",
            "sha",
            DEADLINE
        );
        
        // Place bets
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        // Try to settle with DIFFERENT parameters
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(
            marketId,
            "99999",        // ❌ Different topic!
            "bitcoin",      // ❌ Different keyword!
            "first",
            true,
            true,
            ""
        );
    }
    
    function testParameterBindingTopicMismatch() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",  // Correct topic
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        
        // Wrong topic
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(marketId, "99999", "radicle", "first", true, true, "");
    }
    
    function testParameterBindingKeywordMismatch() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",  // Correct keyword
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        
        // Wrong keyword
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(marketId, "12345", "bitcoin", "first", true, true, "");
    }
    
    function testParameterBindingOracleTypeMismatch() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",  // Correct type
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        
        // Wrong oracle type
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(marketId, "12345", "radicle", "any", true, true, "");
    }
    
    function testParameterBindingCorrectParameters() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        
        // Correct parameters - should succeed
        market.settle(marketId, "12345", "radicle", "first", true, true, "");
        
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertTrue(settled);
    }
    
    // ========== CRITICAL ISSUE #2: Authorization ==========
    
    function testUnauthorizedSettlementBlocked() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Attacker tries to settle
        vm.prank(attacker);
        vm.expectRevert(PredictionMarket.NotAuthorized.selector);
        market.settle(marketId, "12345", "radicle", "first", true, false, "");
    }
    
    function testOnlyTrustedSettlerCanSettle() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Alice can't settle (not trusted)
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.NotAuthorized.selector);
        market.settle(marketId, "12345", "radicle", "first", true, true, "");
        
        // Trusted settler can settle
        vm.prank(trustedSettler);
        market.settle(marketId, "12345", "radicle", "first", true, true, "");
        
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertTrue(settled);
    }
    
    function testOwnerCanChangeTrustedSettler() public {
        address newSettler = address(0xB);
        
        // Owner can change
        market.setTrustedSettler(newSettler);
        assertEq(market.trustedSettler(), newSettler);
        
        // Non-owner cannot change
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.NotAuthorized.selector);
        market.setTrustedSettler(alice);
    }
    
    // ========== CRITICAL ISSUE #3: Settleable Check ==========
    
    function testCannotSettleWhenNotSettleable() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Try to settle with settleable=false (NO_COMMENTS state)
        vm.prank(trustedSettler);
        vm.expectRevert(PredictionMarket.NotSettleable.selector);
        market.settle(
            marketId,
            "12345",
            "radicle",
            "first",
            false,  // ❌ Not settleable!
            false,
            ""
        );
    }
    
    function testCanSettleWhenSettleable() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        
        // Can settle with settleable=true
        vm.prank(trustedSettler);
        market.settle(marketId, "12345", "radicle", "first", true, true, "");
        
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertTrue(settled);
    }
    
    // ========== HIGH ISSUE #4: Division by Zero ==========
    
    function testDivisionByZeroProtection() public {
        vm.warp(100);
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        // Only YES bets
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, true);
        
        // Settle as NO wins (but no one bet NO)
        vm.warp(DEADLINE + 1);
        vm.prank(trustedSettler);
        market.settle(marketId, "12345", "radicle", "first", true, false, "");
        
        // Alice tries to claim (has no NO shares)
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.NoWinningBet.selector);
        market.claim(marketId);
        
        // If there was logic that tried to claim with 0 winning shares,
        // it would hit NoWinners error (division by zero protection)
    }
    
    // ========== Security Attack Scenarios ==========
    
    function testAttackScenarioWrongOracleData() public {
        vm.warp(100);
        
        // Create market: "Will 'radicle' be in topic 12345 first comment?"
        uint256 marketId = market.createMarket(
            "Will radicle be mentioned?",
            "12345",
            "radicle",
            "first",
            "claw-tee-dah/github-zktls",
            "abc123",
            DEADLINE
        );
        
        // Alice bets YES (radicle will be mentioned)
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true);
        
        // Bob bets NO
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        vm.warp(DEADLINE + 1);
        
        // ATTACK: Attacker tries to settle with oracle data from different topic
        // where "bitcoin" was mentioned (not "radicle")
        vm.prank(trustedSettler);
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(
            marketId,
            "99999",    // Different topic where bitcoin mentioned
            "bitcoin",  // Different keyword
            "first",
            true,       // Oracle found it
            true,       // Would make attacker win
            ""
        );
        
        // Market is NOT settled
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertFalse(settled);
    }
    
    function testAttackScenarioPrematureSettlement() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Test",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        vm.warp(DEADLINE + 1);
        
        // ATTACK: Try to settle before first comment exists
        // (oracle would return NO_COMMENTS, settleable=false)
        vm.prank(trustedSettler);
        vm.expectRevert(PredictionMarket.NotSettleable.selector);
        market.settle(
            marketId,
            "12345",
            "radicle",
            "first",
            false,  // Not settleable (NO_COMMENTS)
            false,  // Attacker claims NOT_FOUND
            ""
        );
        
        // Market is NOT settled
        (,,,,,bool settled,,,) = market.getMarket(marketId);
        assertFalse(settled);
        
        // Later, when first comment exists with keyword
        vm.prank(trustedSettler);
        market.settle(
            marketId,
            "12345",
            "radicle",
            "first",
            true,   // Now settleable
            true,   // FOUND
            ""
        );
        
        // Now settled correctly
        bool finalSettled;
        bool finalResult;
        (,,,,, finalSettled, finalResult,,) = market.getMarket(marketId);
        assertTrue(finalSettled);
        assertTrue(finalResult);  // YES wins (correct outcome)
    }
    
    function testMultipleMarketsWithDifferentParameters() public {
        vm.warp(100);
        
        // Market 1: topic 12345, keyword "radicle"
        uint256 market1 = market.createMarket(
            "Market 1",
            "12345",
            "radicle",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        // Market 2: topic 99999, keyword "bitcoin"
        uint256 market2 = market.createMarket(
            "Market 2",
            "99999",
            "bitcoin",
            "first",
            "repo",
            "sha",
            DEADLINE
        );
        
        vm.prank(alice);
        market.bet{value: 1 ether}(market1, true);
        
        vm.prank(bob);
        market.bet{value: 1 ether}(market2, true);
        
        vm.warp(DEADLINE + 1);
        vm.startPrank(trustedSettler);
        
        // Cannot settle market1 with market2's parameters
        vm.expectRevert(PredictionMarket.ParameterMismatch.selector);
        market.settle(market1, "99999", "bitcoin", "first", true, true, "");
        
        // Can settle each with correct parameters
        market.settle(market1, "12345", "radicle", "first", true, true, "");
        market.settle(market2, "99999", "bitcoin", "first", true, false, "");
        
        vm.stopPrank();
        
        (,,,,,bool settled1,bool result1,,) = market.getMarket(market1);
        (,,,,,bool settled2,bool result2,,) = market.getMarket(market2);
        
        assertTrue(settled1);
        assertTrue(settled2);
        assertTrue(result1);   // Market 1: YES
        assertFalse(result2);  // Market 2: NO
    }
}
