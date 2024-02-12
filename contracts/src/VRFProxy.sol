// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.18;

import {VRFRequestInfo, VRFResponseInfo, IVRFProxy} from "./IVRFProxy.sol";
import {
    TeleporterMessageInput, TeleporterFeeInfo
} from "@teleporter/contracts/src/Teleporter/ITeleporterMessenger.sol";
import {TeleporterOwnerUpgradeable} from "@teleporter/contracts/src/Teleporter/upgrades/TeleporterOwnerUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {GasUtils} from "./GasUtils.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT INTERFACE THAT USES UNAUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @notice VRFProxy is a contract that serves as a proxy to request random values from a VRFProvider on a partner
 * chain. The implementation uses Teleporter to request and receive back values from the VRFProvider at the
 * blockchain and contract address specified in the constrctor. Application contracts that require random values
 * can request and receive them from the VRFProxy using the same interface as they would use for requesting random
 * values from a Chainlink VRF coordinator contract.
 *
 * Application contract using the VRFProxy must be added as allowed consumers using the addConsumer function.
 * VRF requests are forwarded to the VRFProvider contract on the partner blockchain, which in turn requests the
 * random values from a Chainlink VRF coordinator on that blockchain. All allowed consumers of the VRFProxy are
 * capable of using VRF subscriptions available to the VRFProvider contract on the partner chain.
 */
contract VRFProxy is IVRFProxy, ReentrancyGuard, TeleporterOwnerUpgradeable {
    using GasUtils for *;

    /**
     * @dev The estimated amount of gas used by the VRFProvider on the partner chain to request random values from the
     * Chainlink VRF coordinator. This is the required gas limit for the Teleporter message sent to request the values.
     */
    uint256 public constant VRF_REQUEST_REQUIRED_GAS = 100_000;

    /**
     * @dev The blockchain ID of the partner blockchain where the VRFProvider contract is deployed.
     */
    bytes32 public immutable vrfProviderBlockchainID;

    /**
     * @dev The contract adddress of the VRFProvider to be used on the partner blockchain.
     */
    address public immutable vrfProviderAddress;

    /**
     * @dev The number of requests for random values that have been made to this VRFPRoxy. Used as unique request IDs.
     */
    uint256 public requestNonce;

    /**
     * @dev The set of addresses that are allowed to request random values from this VRFProxy.
     * @notice All allowed consumers are capabale of using any VRF subscription available to the VRFProvider contract
     * on the partner blockchain. Those subscriptions are used to pay VRF fees on the partner blockchain.
     */
    mapping(address consumer => bool allowed) public allowedConsumers;

    /**
     * @dev The address that request the random values for each request ID.
     */
    mapping(uint256 requestID => address requester) public requesters;

    /**
     * @dev Emitted when an account is added as an allowed consumer.
     * @param consumer - The address of the account added as an allowed consumer.
     */
    event ConsumerAdded(address indexed consumer);

    /**
     * @dev Emitted when an account is removed from the allowed consumers set.
     * @param consumer - The address of the account removed from the allowed consumers set.
     */
    event ConsumerRemoved(address indexed consumer);

    /**
     * @dev Emitted when random words are requested from this VRFProxy.
     * @param requestID - A unique ID for the request. This is assigned by the VRFProxy, and separate from the request
     * ID assigned by the Chainlink VRF Coordinator on the partner chain.
     * @param requester - The address of the account requesing the random values.
     * @param keyHash - The keyHash to be used by the partner VRFProvider contract when requesting the random values
     * from the Chainlink VRF Coordinator on the partner chain.
     * @param subID - The subID to be used by the partner VRFProvider contract when requesting the random values
     * from the Chainlink VRF Coordinator on the partner chain.
     * @param minimumRequestConfirmations - The minimumRequestConfirmations to be used by the partner VRFProvider
     * contract when requesting the random values from the Chainlink VRF Coordinator on the partner chain. These
     * are confirmations on the partner chain, not the chain of this VRFProxy contract.
     * @param callbackGasLimit - The amount of gas required to be available to the requester to execute its
     * fulfillRandomWords function.
     * @param numWords - The number of uint256 random words requested.
     */
    event RandomWordsRequested(
        uint256 indexed requestID,
        address indexed requester,
        bytes32 indexed keyHash,
        uint64 subID,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    );

    /**
     * @dev Emitted when a request for random words is fulfilled.
     * @param requestID - A unique ID for the request. This is assigned by the VRFProxy, and separate from the request
     * ID assigned by the Chainlink VRF Coordinator on the partner chain.
     * @param success - Whether or not the call to the requester's fulfillRandomWords fundction succeeded. The requesters
     * are responsible for the correctness of their own implementation. Success cannot be ensured by the VRFProxy.
     */
    event RandomWordsFulfilled(uint256 indexed requestID, bool success);

    constructor(address teleporterRegistryAddress_, bytes32 vrfProviderBlockchainID_, address vrfProviderAddress_)
        TeleporterOwnerUpgradeable(teleporterRegistryAddress_)
    {
        vrfProviderBlockchainID = vrfProviderBlockchainID_;
        vrfProviderAddress = vrfProviderAddress_;
    }

    /**
     * @dev Adds the provider consumer account to the set of allowed consumers, if it is not already included.
     * @param consumer - The address of the account added as an allowed consumer.
     */
    function addConsumer(address consumer) external onlyOwner {
        require(consumer != address(0), "VRFProxy: zero consumer address");
        if (!allowedConsumers[consumer]) {
            allowedConsumers[consumer] = true;
            emit ConsumerAdded(consumer);
        }
    }

    /**
     * @dev Removes the provided consumer account from the set of allowed consumers, if present.
     * @param consumer - The address of the account removed from the allowed consumers set.
     */
    function removeConsumer(address consumer) external onlyOwner {
        require(allowedConsumers[consumer], "VRFProxy: invalid consumer");
        allowedConsumers[consumer] = false;
        emit ConsumerRemoved(consumer);
    }

    /**
     * @notice Request a set of random words.
     * The request is passed on to the partner chain where the VRFProvider is deployed via Teleporter message.
     * See https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol#L13
     * for further documentation of how each value is used within Chainlink VRF reuests.
     * @param keyHash - Corresponds to the VRF keyHash to be used on the partner chain that provides the VRF functionality.
     * @param subID - The ID of the VRF subscription to be used by the VRF provider on the partner chain.
     * @param minimumRequestConfirmations - How many blocks you'd like the VRF service on the partner chain to wait prior
     * to fulfilling the request once the VRF provider submits the request on the partner chain.
     * @param callbackGasLimit - How much gas needs to be provided to the fulfillRandomWords call to complete this randomness request.
     * @param numWords - The number of uint256 values requested.
     * @return requestID - A unique identifier of the request. Can be used to match a request to a reponse in fulfillRandomWords. This
     * request ID is separate from any VRF request ID assigned on the partner chain by the VRFProdiver.
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subID,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256) {
        require(allowedConsumers[msg.sender], "VRFProxy: unauthorized consumer");

        // Assign the next nonce to be used at the request ID.
        uint256 nonce = ++requestNonce;
        VRFRequestInfo memory requestInfo = VRFRequestInfo({
            requestID: nonce,
            keyHash: keyHash,
            subID: subID,
            minimumRequestConfirmations: minimumRequestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords
        });

        // Store the address requesting the random value to be called
        // when the random value is fulfilled via receival of a Teleporter
        // message.
        requesters[nonce] = msg.sender;

        // Submit the VRF request to the partner VRFProvider via Teleporter message.
        _getTeleporterMessenger().sendCrossChainMessage(
            TeleporterMessageInput({
                destinationBlockchainID: vrfProviderBlockchainID,
                destinationAddress: vrfProviderAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}),
                requiredGasLimit: VRF_REQUEST_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(requestInfo)
            })
        );

        emit RandomWordsRequested({
            requestID: nonce,
            requester: msg.sender,
            keyHash: keyHash,
            subID: subID,
            minimumRequestConfirmations: minimumRequestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords
        });

        return nonce;
    }

    /**
     * @dev Called when a Teleporter message is delivered to this VRFProxyContract. Verifies the sender of the message
     * and then processes it by passing the random values back to their original requester.
     * @param sourceBlockchainID - The blockchain ID where the message originated. The only allowed sender is
     * the vrfProviderBlockchainID.
     * @param originSenderAddress - The address of the message sender on the source blockchain. The only allowed sender
     * is the vrfProviderAddress.
     * @param message - The raw Teleporter message payload. Expected to be an ABI encoded VRFResponseInfo instance.
     */
    function _receiveTeleporterMessage(bytes32 sourceBlockchainID, address originSenderAddress, bytes memory message)
        internal
        override
        nonReentrant
    {
        // Verify the sender.
        require(sourceBlockchainID == vrfProviderBlockchainID, "VRFProxy: invalid source blockchain ID");
        require(originSenderAddress == vrfProviderAddress, "VRFProxy: invalid origin sender address");

        // Decode the response.
        VRFResponseInfo memory response = abi.decode(message, (VRFResponseInfo));

        // Look up the requester.
        address requester = requesters[response.requestID];
        require(requester != address(0), "VRFProxy: invalid requester");

        // Clear the requesting address since the request is now fulfilled.
        delete requesters[response.requestID];

        // Pass the result to the destination with the exact gas limit.
        VRFConsumerBaseV2 v;
        bytes memory resp =
            abi.encodeWithSelector(v.rawFulfillRandomWords.selector, response.requestID, response.randomWords);

        // Call with explicitly the amount of callback gas requested.
        // Note that _callWithExactGas will revert if we do not have sufficient gas
        // to give the callee their requested amount.
        bool success = GasUtils._callWithExactGas(response.callbackGasLimit, requester, resp);
        emit RandomWordsFulfilled(response.requestID, success);
    }
}
