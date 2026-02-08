// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarket.sol";

contract PredictionMarketTest is Test {
    PredictionMarket public market;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 constant DEADLINE = 1000000;
    
    function setUp() public {
        market = new PredictionMarket();
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    function testCreateMarket() public {
        vm.warp(100);
        
        uint256 marketId = market.createMarket(
            "Will radicle be mentioned?",
            "claw-tee-dah/github-zktls",
            "abc123",
            DEADLINE
        );
        
        assertEq(marketId, 0);
        
        (
            string memory description,
            string memory repo,
            string memory commitSHA,
            uint256 deadline,
            bool settled,
            bool result,
            uint256 yesPool,
            uint256 noPool
        ) = market.getMarket(0);
        
        assertEq(description, "Will radicle be mentioned?");
        assertEq(repo, "claw-tee-dah/github-zktls");
        assertEq(commitSHA, "abc123");
        assertEq(deadline, DEADLINE);
        assertEq(settled, false);
        assertEq(result, false);
        assertEq(yesPool, 0);
        assertEq(noPool, 0);
    }
    
    function testBetYes() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        (,,,, bool settled,, uint256 yesPool, uint256 noPool) = market.getMarket(marketId);
        assertEq(yesPool, 1 ether);
        assertEq(noPool, 0);
        assertEq(settled, false);
        
        (uint256 yesShares, uint256 noShares, bool claimed) = market.getBet(marketId, alice);
        assertEq(yesShares, 1 ether);
        assertEq(noShares, 0);
        assertEq(claimed, false);
    }
    
    function testBetNo() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, false);
        
        (,,,,,, uint256 yesPool, uint256 noPool) = market.getMarket(marketId);
        assertEq(yesPool, 0);
        assertEq(noPool, 2 ether);
    }
    
    function testParimutuelOdds() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets 3 ETH on YES
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true);
        
        // Bob bets 1 ETH on NO
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        // Odds should be 75% YES, 25% NO (basis points)
        (uint256 yesOdds, uint256 noOdds) = market.getOdds(marketId);
        assertEq(yesOdds, 7500); // 75%
        assertEq(noOdds, 2500);  // 25%
    }
    
    function testParimutuelPayout_YesWins() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets 3 ETH on YES
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true);
        
        // Bob bets 1 ETH on NO
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        // Total pot: 4 ETH
        // YES wins
        vm.warp(DEADLINE + 1);
        market.settle(marketId, true, "");
        
        // Alice should get entire 4 ETH pot (she was only YES better)
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        market.claim(marketId);
        
        assertEq(alice.balance - aliceBalanceBefore, 4 ether);
    }
    
    function testParimutuelPayout_NoWins() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets 3 ETH on YES
        vm.prank(alice);
        market.bet{value: 3 ether}(marketId, true);
        
        // Bob bets 1 ETH on NO
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        // NO wins
        vm.warp(DEADLINE + 1);
        market.settle(marketId, false, "");
        
        // Bob should get entire 4 ETH pot
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        market.claim(marketId);
        
        assertEq(bob.balance - bobBalanceBefore, 4 ether);
    }
    
    function testMultipleBettors_ProportionalPayout() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets 2 ETH on YES
        vm.prank(alice);
        market.bet{value: 2 ether}(marketId, true);
        
        // Bob bets 4 ETH on YES
        vm.prank(bob);
        market.bet{value: 4 ether}(marketId, true);
        
        // Charlie bets 3 ETH on NO
        vm.prank(charlie);
        market.bet{value: 3 ether}(marketId, false);
        
        // Total pot: 9 ETH
        // YES pool: 6 ETH (Alice 2, Bob 4)
        // NO pool: 3 ETH (Charlie)
        
        // YES wins
        vm.warp(DEADLINE + 1);
        market.settle(marketId, true, "");
        
        // Alice has 2/6 of YES shares = 1/3 of 9 ETH = 3 ETH
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        market.claim(marketId);
        assertEq(alice.balance - aliceBalanceBefore, 3 ether);
        
        // Bob has 4/6 of YES shares = 2/3 of 9 ETH = 6 ETH
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        market.claim(marketId);
        assertEq(bob.balance - bobBalanceBefore, 6 ether);
    }
    
    function testBothSidesBetting() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets on both sides (hedging)
        vm.startPrank(alice);
        market.bet{value: 1 ether}(marketId, true);  // YES
        market.bet{value: 1 ether}(marketId, false); // NO
        vm.stopPrank();
        
        (uint256 yesShares, uint256 noShares,) = market.getBet(marketId, alice);
        assertEq(yesShares, 1 ether);
        assertEq(noShares, 1 ether);
        
        // Bob bets YES only
        vm.prank(bob);
        market.bet{value: 2 ether}(marketId, true);
        
        // YES wins
        vm.warp(DEADLINE + 1);
        market.settle(marketId, true, "");
        
        // Total pot: 4 ETH
        // YES shares: 3 ETH (Alice 1, Bob 2)
        // Alice gets 1/3 = 1.333... ETH
        // Bob gets 2/3 = 2.666... ETH
        
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        market.claim(marketId);
        assertApproxEqAbs(alice.balance - aliceBalanceBefore, 1.333 ether, 0.001 ether);
    }
    
    function testCannotBetAfterDeadline() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.warp(DEADLINE + 1);
        
        vm.prank(alice);
        vm.expectRevert(PredictionMarket.BettingClosed.selector);
        market.bet{value: 1 ether}(marketId, true);
    }
    
    function testCannotSettleBeforeDeadline() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.warp(DEADLINE - 1);
        
        vm.expectRevert(PredictionMarket.BettingStillOpen.selector);
        market.settle(marketId, true, "");
    }
    
    function testCannotClaimTwice() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.warp(DEADLINE + 1);
        market.settle(marketId, true, "");
        
        vm.startPrank(alice);
        market.claim(marketId);
        
        vm.expectRevert(PredictionMarket.AlreadyClaimed.selector);
        market.claim(marketId);
        vm.stopPrank();
    }
    
    function testLoserCannotClaim() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        vm.prank(alice);
        market.bet{value: 1 ether}(marketId, true);
        
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, false);
        
        vm.warp(DEADLINE + 1);
        market.settle(marketId, true, ""); // YES wins
        
        // Bob lost, cannot claim
        vm.prank(bob);
        vm.expectRevert(PredictionMarket.NoWinningBet.selector);
        market.claim(marketId);
    }
    
    function testGetPotentialPayout() public {
        vm.warp(100);
        uint256 marketId = market.createMarket("Test", "repo", "sha", DEADLINE);
        
        // Alice bets 2 ETH on YES, 1 ETH on NO
        vm.startPrank(alice);
        market.bet{value: 2 ether}(marketId, true);
        market.bet{value: 1 ether}(marketId, false);
        vm.stopPrank();
        
        // Bob bets 1 ETH on YES
        vm.prank(bob);
        market.bet{value: 1 ether}(marketId, true);
        
        // Total pot: 4 ETH
        // YES pool: 3 ETH (Alice 2, Bob 1)
        // NO pool: 1 ETH (Alice 1)
        
        (uint256 ifYesWins, uint256 ifNoWins) = market.getPotentialPayout(marketId, alice);
        
        // If YES wins: Alice gets 2/3 of 4 ETH = 2.666... ETH
        assertApproxEqAbs(ifYesWins, 2.666 ether, 0.001 ether);
        
        // If NO wins: Alice gets 1/1 of 4 ETH = 4 ETH
        assertEq(ifNoWins, 4 ether);
    }
}
