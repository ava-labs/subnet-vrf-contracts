// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {SimpleBettingGame, Bet, BetStatus, IVRFProxy} from "../SimpleBettingGame.sol";

contract SimpleBettingGameTest is Test {
    address public constant MOCK_VRF_COORDINATOR = address(0xabcd);
    uint64 public constant MOCK_VRF_SUBSCRIPTION_ID = 987654321;
    bytes32 public constant MOCK_VRF_KEY_HASH =
        bytes32(hex"1234567812345678123456781234567812345678123456781234567812345678");
    address public constant MOCK_BET_TAKER = address(0xc0d3);

    SimpleBettingGame public game;

    // Event emitted by SimpleBetGame
    event BetProposed(uint256 indexed betID, address indexed proposer, uint32 maxValue);
    event BetCanceled(uint256 indexed betID, address indexed proposer);
    event BetTaken(
        uint256 indexed betID, address indexed proposer, address indexed taker, uint32 maxValue, uint256 vrfRequestID
    );
    event BetCompleted(uint256 indexed betID, address indexed winner, uint32 maxValue, uint32 value);

    function setUp() public virtual {
        game = new SimpleBettingGame(MOCK_VRF_COORDINATOR, MOCK_VRF_SUBSCRIPTION_ID, MOCK_VRF_KEY_HASH);
    }

    function testProposeNewBetSuccess() public {
        // Arrange
        uint256 expectedBetID = 1;
        uint32 maxValue = 99;
        vm.expectEmit(true, true, true, true, address(game));
        emit BetProposed(expectedBetID, address(this), maxValue);

        // Place the bet.
        uint256 betID = game.proposeNewBet(99);

        // Get the new bet.
        Bet memory bet = game.getBet(betID);
        assertEq(uint32(bet.status), uint32(BetStatus.PROPOSED));
        assertEq(bet.proposer, address(this));
        assertEq(bet.maxValue, maxValue);
    }

    function testProposeNewBetInvalidMaxValue() public {
        // The valid range of maximum values is 2-99 inclusive.
        vm.expectRevert("SimpleBettingGame: invalid maxValue");
        game.proposeNewBet(100);

        // The valid range of maximum values is 2-99 inclusive.
        vm.expectRevert("SimpleBettingGame: invalid maxValue");
        game.proposeNewBet(1);
    }

    function testCancelBetSuccess() public {
        // Place a bet.
        uint256 betID = game.proposeNewBet(10);

        // Cancel the bet.
        vm.expectEmit(true, true, true, true, address(game));
        emit BetCanceled(betID, address(this));
        game.cancelBet(betID);

        // Check its status.
        Bet memory bet = game.getBet(betID);
        assertEq(uint32(bet.status), uint32(BetStatus.CANCELED));
        assertEq(bet.proposer, address(this));
    }

    function testCancelBetInvalidBetID() public {
        // Bet ID zero is never used.
        vm.expectRevert("SimpleBettingGame: invalid betID");
        game.cancelBet(0);

        // Place a couple mock bets
        game.proposeNewBet(10);
        uint256 latestBetID = game.proposeNewBet(10);

        // Bet ID higher than current max bet ID.
        vm.expectRevert("SimpleBettingGame: invalid betID");
        game.cancelBet(latestBetID + 1);
    }

    function testCancelBetAlreadyTaken() public {
        // Place a bet and take it from another account.
        uint256 betID = _proposeAndTakeBet(10, 123);

        // Check that it can no longer be cancelled.
        vm.expectRevert("SimpleBettingGame: can only cancel proposed bets");
        game.cancelBet(betID);
    }

    function testCancelBetAlreadyCanceled() public {
        // Propose and cancel a bet.
        uint256 betID = game.proposeNewBet(10);
        game.cancelBet(betID);

        // Check that it can not be canceled again.
        vm.expectRevert("SimpleBettingGame: can only cancel proposed bets");
        game.cancelBet(betID);
    }

    function testCancelBetNotProposer() public {
        // Propose a bet.
        uint256 betID = game.proposeNewBet(10);

        // Check that a non-proposer cannot cancel it.
        vm.prank(MOCK_BET_TAKER);
        vm.expectRevert("SimpleBettingGame: only proposer can cancel");
        game.cancelBet(betID);
    }

    function testTakeBetSuccess() public {
        // Propose bet.
        uint32 mockMaxValue = 42;
        uint256 betID = game.proposeNewBet(mockMaxValue);

        // Take it from another account.
        uint256 mockVRFRequestID = 654321;
        vm.mockCall(
            MOCK_VRF_COORDINATOR,
            abi.encodeWithSelector(IVRFProxy.requestRandomWords.selector),
            abi.encode(mockVRFRequestID)
        );
        vm.expectEmit(true, true, true, true, address(game));
        emit BetTaken(betID, address(this), MOCK_BET_TAKER, mockMaxValue, mockVRFRequestID);
        vm.prank(MOCK_BET_TAKER);
        game.takeBet(betID);

        // Check that the bet is properly updated.
        Bet memory bet = game.getBet(betID);
        assertEq(uint32(bet.status), uint32(BetStatus.TAKEN));
        assertEq(bet.proposer, address(this));
        assertEq(bet.taker, MOCK_BET_TAKER);
        assertEq(bet.maxValue, mockMaxValue);
        assertEq(bet.vrfRequestID, mockVRFRequestID);
    }

    function testTakeBetInvalidBetID() public {
        // Bet ID 0 is never used.
        vm.expectRevert("SimpleBettingGame: invalid betID");
        game.takeBet(0);

        // Place a couple mock bets
        game.proposeNewBet(10);
        uint256 latestBetID = game.proposeNewBet(10);

        // Bet ID higher than current max bet ID.
        vm.expectRevert("SimpleBettingGame: invalid betID");
        game.takeBet(latestBetID + 1);
    }

    function testTakeBetAlreadyCanceled() public {
        // Place a bet and cancel it.
        uint256 betID = game.proposeNewBet(10);
        game.cancelBet(betID);

        // Check that you can't take the bet anymore.
        vm.expectRevert("SimpleBettingGame: can only take proposed bets");
        game.takeBet(betID);
    }

    function testTakeBetAlreadyTaken() public {
        // Place and take a bet.
        uint256 betID = _proposeAndTakeBet(10, 123);

        // Check that you can't take the bet again.
        vm.expectRevert("SimpleBettingGame: can only take proposed bets");
        game.takeBet(betID);
    }

    function testTakeBetAlreadyCompleted() public {
        // Propose and take a bet.
        uint256 mockVRFRequestID = 987;
        uint256 betID = _proposeAndTakeBet(90, 987);

        // Complete the bet.
        _fulfillBet(mockVRFRequestID, 91);

        // Check that the bet can no longer be taken
        vm.expectRevert("SimpleBettingGame: can only take proposed bets");
        game.takeBet(betID);
    }

    function testTakeBetAsProposer() public {
        // Propose bet.
        uint256 betID = game.proposeNewBet(10);

        // Try to take it from the same account.
        vm.expectRevert("SimpleBettingGame: proposer cannot take bet");
        game.takeBet(betID);
    }

    function testFulfillRandomWordsInvalidLength() public {
        uint256[] memory randomWords = new uint256[](2);
        randomWords[0] = 67;
        randomWords[1] = 68;

        // The game only allows a single random word.
        vm.prank(MOCK_VRF_COORDINATOR);
        vm.expectRevert("SimpleBettingGame: invalid random words length");
        game.rawFulfillRandomWords(123, randomWords);
    }

    function testHandleResultProposerWins() public {
        // Propose and take a bet.
        uint32 mockMaxValue = 42;
        uint32 mockVRFRequestID = 789;
        uint256 betID = _proposeAndTakeBet(mockMaxValue, mockVRFRequestID);

        // Fulfill it with a value less than the max value.
        uint256 randomValue = mockMaxValue - 1;
        uint32 result = uint32(randomValue) + 1;
        vm.expectEmit(true, true, true, true, address(game));
        emit BetCompleted(betID, address(this), mockMaxValue, result);
        _fulfillBet(mockVRFRequestID, randomValue);

        // Check that the bet is properly updated.
        Bet memory bet = game.getBet(betID);
        assertEq(uint32(bet.status), uint32(BetStatus.COMPLETED));
        assertEq(bet.proposer, address(this));
        assertEq(bet.taker, MOCK_BET_TAKER);
        assertEq(bet.maxValue, mockMaxValue);
        assertEq(bet.vrfRequestID, mockVRFRequestID);
        assertEq(bet.value, result);
        assertEq(bet.winner, address(this));
    }

    function testHandleResultTakerWins() public {
        // Propose and take a bet.
        uint32 mockMaxValue = 42;
        uint32 mockVRFRequestID = 789;
        uint256 betID = _proposeAndTakeBet(mockMaxValue, mockVRFRequestID);

        // Fulfill it with a value less than the max value.
        uint256 randomValue = mockMaxValue;
        uint32 result = uint32(randomValue) + 1;
        vm.expectEmit(true, true, true, true, address(game));
        emit BetCompleted(betID, MOCK_BET_TAKER, mockMaxValue, result);
        _fulfillBet(mockVRFRequestID, randomValue);

        // Check that the bet is properly updated.
        Bet memory bet = game.getBet(betID);
        assertEq(uint32(bet.status), uint32(BetStatus.COMPLETED));
        assertEq(bet.proposer, address(this));
        assertEq(bet.taker, MOCK_BET_TAKER);
        assertEq(bet.maxValue, mockMaxValue);
        assertEq(bet.vrfRequestID, mockVRFRequestID);
        assertEq(bet.value, result);
        assertEq(bet.winner, MOCK_BET_TAKER);
    }

    function testHandleResultInvalidVRFRequestID() public {
        // There are no VRF request IDs stored prior to a bet being taken.
        vm.expectRevert("SimpleBettingGame: invalid VRF request ID");
        _fulfillBet(3, 2345);
    }

    function testHandleResultAlreadyCompleted() public {
        // Propose and take a bet.
        uint32 mockMaxValue = 42;
        uint32 mockVRFRequestID = 789;
        _proposeAndTakeBet(mockMaxValue, mockVRFRequestID);
        _fulfillBet(mockVRFRequestID, 123456789);

        // Check that it can't be fulfilled again.
        vm.expectRevert("SimpleBettingGame: can only complete taken bets");
        _fulfillBet(mockVRFRequestID, 987654321);
    }

    // Proposes a new bet, takes it from a different account, and returns the bet ID.
    function _proposeAndTakeBet(uint32 maxValue, uint256 vrfRequestID) private returns (uint256) {
        uint256 betID = game.proposeNewBet(maxValue);
        vm.mockCall(
            MOCK_VRF_COORDINATOR,
            abi.encodeWithSelector(IVRFProxy.requestRandomWords.selector),
            abi.encode(vrfRequestID)
        );
        vm.prank(MOCK_BET_TAKER);
        game.takeBet(betID);
        return betID;
    }

    // Fulfills the bet with given vrfRequestID with the provided random value.
    function _fulfillBet(uint256 vrfRequestID, uint256 randomValue) private {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomValue;
        vm.prank(MOCK_VRF_COORDINATOR);
        game.rawFulfillRandomWords(vrfRequestID, randomWords);
    }
}
