// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.18;

import {VRFRequestInfo, VRFResponseInfo} from "./IVRFProxy.sol";
import {
    TeleporterMessageInput, TeleporterFeeInfo
} from "@teleporter/contracts/src/Teleporter/ITeleporterMessenger.sol";
import {TeleporterOwnerUpgradeable} from "@teleporter/contracts/src/Teleporter/upgrades/TeleporterOwnerUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT INTERFACE THAT USES UNAUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @notice VRFProvider is a contract that provides random values to its partner VRFProxy on a different blockchain via
 * Teleporter messages. Its implementation uses Chainlink VRF to obtain random values on the blockchain that is deployed
 * on. Random words can only be requested by the specified VRFProxy partner contract. When a request is received, it is
 * passed along to the specified Chainlink VRF coordinator. When that request is fulfilled by the Chainlink VRF, the
 * results are passed on the to the VRFProxy by sending a Teleporter message back to that blockchain and address.
 *
 * For VRF requests to be successfully submitted to the Chainlink VRF Coordinator, the VRFProvider instance must
 * be an allowed consumer of the Chainlink VRF subscription ID used, and must have sufficient funds in the subscription
 * to pay for the request. The partner VRFProxy contract and all of its allowed consumers are able to use any
 * subscription ID the VRFProvider has access to.
 */
contract VRFProvider is VRFConsumerBaseV2, TeleporterOwnerUpgradeable, ReentrancyGuard {
    /**
     * @dev  The components of VRFRequestInfo that need to be persisted when requesting
     * random values from the Chainlink VRF coordinator. These values will be sent
     * back to the partner VRFCoorindator as part of the message to fulfill
     * the request.
     */
    struct InternalRequestInfo {
        uint256 proxyRequestID;
        uint32 messageCallbackGasLimit;
    }

    /**
     * @dev Tracks the request information by the Chainlink VRF request ID.
     */
    mapping(uint256 chainlinkVRFRequestID => InternalRequestInfo requestInfo) internal _requests;

    /**
     * @dev The Chainlink VRF coodinator used for requesting random values to fulfill requests.
     */
    VRFCoordinatorV2Interface internal immutable _chainlinkVRFCoordinator;

    /**
     * @dev The blockchain ID where the partner VRFProxy contract is deployed.
     */
    bytes32 public immutable vrfProxyBlockchainID;

    /**
     * @dev The contract address of the VRFProxy on the partner blockchain.
     */
    address public immutable vrfProxyAddress;

    /**
     * @dev Gas limits for receiving random words from the Chainlink VRF coordinator, and sending
     * them in a Teleporter message to the partner Teleporter VRF coordinator contract.
     */
    uint32 public constant TELEPORTER_CALLBACK_GAS_LIMIT_BASE = 100_000;
    uint32 public constant TELEPORTER_CALLBACK_GAS_LIMIT_PER_WORD = 1_000;
    uint32 public constant TELEPORTER_RECEIVE_MESSAGE_GAS_OVERHEAD = 20_000;

    /**
     * @dev Emitted when a message is received from the partner VRFProxy requesting random values.
     * @param proxyRequestID - The request ID specified in the message from the VRFProxy. Separate from the
     * Chainlink VRF request ID assigned when the request is submitted to the Chainlink VRF coordinator.
     * @param chainlinkVRFRequestID - The request ID assigned by the Chainlink VRF coordinator for
     * the random value request. Separate from the proxy request ID.
     * @param numWords - The number of random uint256 words requested.
     */
    event VRFRequestReceived(uint256 indexed proxyRequestID, uint256 indexed chainlinkVRFRequestID, uint32 numWords);

    /**
     * @dev Emitted when a VRF request is fulfilled by the Chainlink VRF Coordinator, and the random
     * values are sent back the partner VRFProxy via Teleporter message.
     * @param proxyRequestID - The request ID specified in the message from the VRFProxy. Separate from the
     * Chainlink VRF request ID assigned when the request is submitted to the Chainlink VRF coordinator.
     * @param chainlinkVRFRequestID - The request ID assigned by the Chainlink VRF coordinator for
     * the random value request. Separate from the proxy request ID.
     * @param numWords - The number of random uint256 words.
     */
    event VRFRequestFulfilled(uint256 indexed proxyRequestID, uint256 indexed chainlinkVRFRequestID, uint32 numWords);

    constructor(
        address teleporterRegistryAddress_,
        address chainlinkVRFCoordinatorAddress_,
        bytes32 vrfProxyBlockchainID_,
        address vrfProxyAddress_
    ) TeleporterOwnerUpgradeable(teleporterRegistryAddress_) VRFConsumerBaseV2(chainlinkVRFCoordinatorAddress_) {
        require(vrfProxyAddress_ != address(0), "VRFProvider: zero VRF proxy address");
        _chainlinkVRFCoordinator = VRFCoordinatorV2Interface(chainlinkVRFCoordinatorAddress_);
        vrfProxyBlockchainID = vrfProxyBlockchainID_;
        vrfProxyAddress = vrfProxyAddress_;
    }

    /**
     * @dev Fulfills the VRF request identified by the given request ID with the randomWords provided. Called from
     * VRFConsumerBaseV2, where authentication occurs requiring that the random words must be provided by the
     * VRFCoordinator contract, which verifies the randomness proof.
     *
     * When random value requests are fulfilled, their corresponding VRFProxy request is looked up,
     * and the resulting random values with relevant information are sent back to the VRFProxy via Teleporter message.
     */
    // Need to provide an implementation of fulfillRandomWords (without a leading "_") for VRFConsumerBaseV2
    // solhint-disable-next-line
    function fulfillRandomWords(uint256 chainlinkVRFRequestID, uint256[] memory randomWords)
        internal
        override
        nonReentrant
    {
        // Look up the corresponding VRFProxy request info for this chainlinkVRFRequestID to know
        // the correct data to include in the response.
        InternalRequestInfo memory requestInfo = _requests[chainlinkVRFRequestID];
        require(requestInfo.proxyRequestID != 0, "VRFProvider: invalid Chainlink VRF request ID");

        emit VRFRequestFulfilled(requestInfo.proxyRequestID, chainlinkVRFRequestID, uint32(randomWords.length));

        // Send the result back to the VRFProxy via Teleporter message.
        VRFResponseInfo memory response = VRFResponseInfo({
            requestID: requestInfo.proxyRequestID,
            randomWords: randomWords,
            callbackGasLimit: requestInfo.messageCallbackGasLimit
        });
        _getTeleporterMessenger().sendCrossChainMessage(
            TeleporterMessageInput({
                destinationBlockchainID: vrfProxyBlockchainID,
                destinationAddress: vrfProxyAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}),
                requiredGasLimit: requestInfo.messageCallbackGasLimit + TELEPORTER_RECEIVE_MESSAGE_GAS_OVERHEAD,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(response)
            })
        );
    }

    /**
     * @dev Called when a Teleporter message is delivered to this VRFProvider. Verifies the sender of the message
     * is the partner VRFProxy, and then passes the random value request on the Chainlink VRF Coordinator.
     * @param sourceBlockchainID - The blockchain ID where the message originated. The only allowed sender is
     * the vrfProxyBlockchainID.
     * @param originSenderAddress - The address of the message sender on the source blockchain. The only allowed sender
     * is the vrfProxyAddress.
     * @param message - The raw Teleporter message payload. Expected to be an ABI encoded VRFRequestInfo instance.
     */
    function _receiveTeleporterMessage(bytes32 sourceBlockchainID, address originSenderAddress, bytes memory message)
        internal
        override
        nonReentrant
    {
        // Verify the sender.
        require(sourceBlockchainID == vrfProxyBlockchainID, "VRFProvider: invalid source blockchain ID");
        require(originSenderAddress == vrfProxyAddress, "VRFProvider: invalid origin sender address");

        // Decode the request.
        VRFRequestInfo memory request = abi.decode(message, (VRFRequestInfo));
        require(request.requestID != 0, "VRFProvider: invalid proxy request ID");

        // Pass the request on the Chainlink VRF coordinator
        uint256 chainlinkVRFRequestID = _chainlinkVRFCoordinator.requestRandomWords(
            request.keyHash,
            request.subID,
            request.minimumRequestConfirmations,
            TELEPORTER_CALLBACK_GAS_LIMIT_BASE + (TELEPORTER_CALLBACK_GAS_LIMIT_PER_WORD * request.numWords),
            request.numWords
        );

        emit VRFRequestReceived(request.requestID, chainlinkVRFRequestID, request.numWords);

        _requests[chainlinkVRFRequestID] =
            InternalRequestInfo({proxyRequestID: request.requestID, messageCallbackGasLimit: request.callbackGasLimit});
    }
}
