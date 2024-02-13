// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.18;

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {IVRFProxy} from "./IVRFProxy.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UNAUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @notice BetStatus defines the current status of a given bet.
 * When bets are created, they are immediately in a proposed status.
 * Proposed bets can either be canceled by their proposer, or taken
 * by another account. If a bet is taken, it can no longer be canceled.
 * Taken bets are completed once they're random value is provided and a
 * winner and loser is determined. Only taken bets can be completed.
 */
enum BetStatus {
    PROPOSED,
    CANCELED,
    TAKEN,
    COMPLETED
}

/**
 * @notice Bet tracks all information related to a specific bet offered.
 * Status represents the current status of the bet as described above. The max value of a bet is the maximum value
 * the random oracle can provide (in a range of 0 to UINT256_MAX) such tha the proposer of the bet "wins". If the
 * random value provided is higher than the max value, then the taker "wins" the bet. The value of the the bet is
 * the random value provided by the randomness source to complete the bet once it is taken, and the winner is only
 * set according to the rules described once the value is provided.
 */
struct Bet {
    BetStatus status;
    uint32 maxValue;
    address proposer;
    address taker;
    uint256 vrfRequestID;
    uint256 value;
    address winner;
}

/**
 * @notice SimpleBettingGame is a contract that demonstrates the use a verifiable random function.
 * Accounts are able to propose "bets" by specifying the maximum value provided by the random
 * oracle (in the range 0 to 100) such that the proposer will "win". Other accounts are
 * able to take proposed bets, at which point a random value is requested from the VRF to determine
 * the outcome of the bet. When the random value is provided via fulfillRandomWords, the winner
 * of the bet is determined.
 */
contract SimpleBettingGame is VRFConsumerBaseV2, ReentrancyGuard {
    /**
     * @dev Total number of bets proposed. Used as bet IDs.
     */
    uint256 public betNonce;

    /**
     * @dev State of each best proposed.
     */
    mapping(uint256 betNonce => Bet bet) internal _bets;

    /**
     * @dev Maps VRF request IDs to the bet ID that the request will determine the outcome of.
     */
    mapping(uint256 vrfRequestID => uint256 betID) internal _vrfRequestIDs;

    /**
     * @dev VRF settings, as documented at https://docs.chain.link/vrf/v2/subscription
     */
    IVRFProxy internal immutable _vrfCoordinator;
    uint64 public immutable vrfSubscriptionID;
    bytes32 public immutable vrfKeyHash;
    uint32 public constant VRF_CALLBACK_GAS_LIMIT = 200_000;
    uint32 public constant MAX_VALUE = 100;

    /**
     * @dev Emitted when a new bet is proposed.
     * @param betID - The ID of the bet.
     * @param proposer - The proposer of the bet.
     * @param maxValue - The maximum random value that can be provided for this bet such that the proposer wins.
     */
    event BetProposed(uint256 indexed betID, address indexed proposer, uint32 maxValue);

    /**
     * @dev Emitted when a proposed bet is canceled. Canceled bets can no longer be taken.
     * @param betID - The ID of the bet.
     * @param proposer - The proposer of the bet.
     */
    event BetCanceled(uint256 indexed betID, address indexed proposer);

    /**
     * @dev Emitted when a proposed bet is taken. Taken bets can no longer be canceled.
     * @param betID - The ID of the bet.
     * @param proposer - The proposer of the bet.
     * @param taker - The taker of the bet.
     * @param maxValue - The maximum random value that can be provided for this bet such that the proposer wins.
     * @param vrfRequestID - The ID of the VRF request made to determine the outcome of the bet.
     */
    event BetTaken(
        uint256 indexed betID, address indexed proposer, address indexed taker, uint32 maxValue, uint256 vrfRequestID
    );

    /**
     * @dev Emiited when a taken bet is completed by a random value being provided by the VRF.
     * @param betID - The ID of the bet.
     * @param winner - The winner of the bet.
     * @param maxValue - The maximum random value that can be provided for this bet such that the proposer wins.
     * @param value - The random value that was provided the VRF to complete this bet.
     */
    event BetCompleted(uint256 indexed betID, address indexed winner, uint32 maxValue, uint32 value);

    constructor(address vrfCoordinator, uint64 vrfSubscriptionID_, bytes32 vrfKeyHash_)
        VRFConsumerBaseV2(vrfCoordinator)
    {
        vrfSubscriptionID = vrfSubscriptionID_;
        vrfKeyHash = vrfKeyHash_;
        _vrfCoordinator = IVRFProxy(vrfCoordinator);
    }

    /**
     * @dev Proposes a new bet where the proposer is the caller, and the maxValue is the
     * maximum value the VRF can provide such that the proposer will win the bet.
     * Emits BetProposed.
     */
    function proposeNewBet(uint32 maxValue) external nonReentrant returns (uint256) {
        // The max value must be between 0 and UINT256_MAX, exclusive.
        require(maxValue > 1 && maxValue < MAX_VALUE, "SimpleBettingGame: invalid maxValue");

        // Assigned the next bet ID to be used, and save the newly proposed bet to state.
        uint256 betID = ++betNonce;
        _bets[betID] = Bet({
            status: BetStatus.PROPOSED,
            maxValue: maxValue,
            proposer: msg.sender,
            taker: address(0),
            vrfRequestID: 0,
            value: 0,
            winner: address(0)
        });

        emit BetProposed(betID, msg.sender, maxValue);
        return betID;
    }

    /**
     * @dev Cancels a proposed bet identified by its bet ID. Only the proposer
     * of a bet is able to cancel it, and only bets in a proposed state can
     * be canceled.
     * Emits BetCanceled.
     */
    function cancelBet(uint256 betID) external nonReentrant {
        // Get the given bet, and check that it can be canceled by the caller.
        require(betID != 0 && betID <= betNonce, "SimpleBettingGame: invalid betID");
        Bet memory bet = _bets[betID];
        require(bet.status == BetStatus.PROPOSED, "SimpleBettingGame: can only cancel proposed bets");
        require(msg.sender == bet.proposer, "SimpleBettingGame: only proposer can cancel");

        // Update the bet status and save it to state.
        bet.status = BetStatus.CANCELED;
        _bets[betID] = bet;

        emit BetCanceled(betID, msg.sender);
    }

    /**
     * @dev Takes a proposed bet identified by its bet ID. Bets must be taken by different
     * account than they were proposed by. When a bet is taken, a random value is requested
     * from the VRF in order to determine the outcome of the bet.
     * Emits BetTaken.
     */
    function takeBet(uint256 betID) external nonReentrant {
        require(betID != 0 && betID <= betNonce, "SimpleBettingGame: invalid betID");
        Bet memory bet = _bets[betID];
        require(bet.status == BetStatus.PROPOSED, "SimpleBettingGame: can only take proposed bets");
        require(msg.sender != bet.proposer, "SimpleBettingGame: proposer cannot take bet");

        // Request a random value from the VRF coordinator.
        uint256 vrfRequestID = _vrfCoordinator.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionID,
            1, // Only 1 required confirmation on Avalanche
            VRF_CALLBACK_GAS_LIMIT,
            1 // Only need 1 word
        );

        // Update the bet information.
        bet.status = BetStatus.TAKEN;
        bet.vrfRequestID = vrfRequestID;
        bet.taker = msg.sender;

        // Save to state.
        _vrfRequestIDs[vrfRequestID] = betID;
        _bets[betID] = bet;

        emit BetTaken(betID, bet.proposer, msg.sender, bet.maxValue, vrfRequestID);
    }

    function getBet(uint256 betID) external view returns (Bet memory) {
        return _bets[betID];
    }

    /**
     * @dev Fulfills the VRF request identified by the given request ID with the randomWords
     * provided. Called from VRFConsumerBaseV2, where authentication occurs requiring that
     * the random words must be provided by the VRFCoordinator contract, which verifies the
     * randomness proof.
     * When random value requests are fulfilled, _handleResult is called to determine the
     * outcome of the bet the request was made for.
     */
    // Need to provide an implementation of fulfillRandomWords (without a leading "_") for VRFConsumerBaseV2
    // solhint-disable-next-line
    function fulfillRandomWords(uint256 vrfRequestID, uint256[] memory randomWords) internal override nonReentrant {
        require(randomWords.length == 1, "SimpleBettingGame: invalid random words length");
        _handleResult(vrfRequestID, randomWords[0]);
    }

    /**
     * @dev Handles the receival of a random value by determining the outcome of the
     * bet for which the random value was request.
     * Emits BetCompleted.
     */
    function _handleResult(uint256 vrfRequestID, uint256 randomValue) private {
        // Get the bet associated with the given VRF request ID.
        uint256 betID = _vrfRequestIDs[vrfRequestID];
        require(betID != 0, "SimpleBettingGame: invalid VRF request ID");
        Bet memory bet = _bets[betID];
        require(bet.status == BetStatus.TAKEN, "SimpleBettingGame: can only complete taken bets");

        uint32 resultValue = uint32(randomValue % MAX_VALUE) + 1;

        // Determine the outcome of the bet given the random result value provided.
        bet.status = BetStatus.COMPLETED;
        bet.value = resultValue;
        if (resultValue <= bet.maxValue) {
            bet.winner = bet.proposer;
        } else {
            bet.winner = bet.taker;
        }

        // Save to state.
        _bets[betID] = bet;

        emit BetCompleted(betID, bet.winner, bet.maxValue, resultValue);
    }
}
