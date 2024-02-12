// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem
pragma solidity 0.8.18;

/**
 * THIS IS AN EXAMPLE CONTRACT INTERFACE THAT USES UNAUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @notice Represents all of the relevant information for a given
 * VRF request message to the VRF partner on a partner chain. This
 * struct is ABI encoded/decoded in the Teleporter message passing.
 */
struct VRFRequestInfo {
    uint256 requestID;
    bytes32 keyHash;
    uint64 subID;
    uint16 minimumRequestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
}

/**
 * @notice Represents all of the relevant information for a given VRF
 * response message received back from the VRF provided on a partner chain.
 * This struct is ABI encoded/decoded in the Teleporter message passing.
 */
struct VRFResponseInfo {
    uint256 requestID;
    uint256[] randomWords;
    uint32 callbackGasLimit;
}

/**
 * @dev IVRFProxy defines the interface for a contract deployed on a subnet that is meant to act as a proxy to a
 * VRFCoordinator deployed on another chain. Approved dApps deployed on the same chain as the VRFProxy can request values
 * from it in the same way that dApps could request random values from a VRFCoordinator contract.
 */
interface IVRFProxy {
    /**
     * @notice Adds the provided consumer to be allowed to request random values
     * via this contract. Allowed consumers can use any VRF subscriptions that
     * the corresponding VRFProvider contract instance has access to on the VRF
     * provider chain.
     * @param consumer the address that should be allowed to call requestRandomWords
     */
    function addConsumer(address consumer) external;

    /**
     * @notice Removes the provided consumer such that it is no longer allowed to
     * request random values via this contract.
     * @param consumer the address that should no longer be allowed to call requestRandomWords
     */
    function removeConsumer(address consumer) external;

    /**
     * @notice Request a set of random words.
     * The request is passed on to the partner chain where the VRFProvider is deployed via Teleporter message.
     * See https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol#L13
     * for further documentation of how each value is used within Chainlink VRF reuests.
     * @param keyHash - Corresponds to the VRF keyHash to be used on the partner chain that provides the VRF functionality.
     * @param subId - The ID of the VRF subscription to be used by the VRF provider on the partner chain.
     * @param minimumRequestConfirmations - How many blocks you'd like the VRF service on the partner chain to wait prior
     * to fulfilling the request once the VRF provider submits the request on the partner chain.
     * @param callbackGasLimit - How much gas needs to be provided to the fulfillRandomWords call to complete this randomness request.
     * @param numWords - The number of uint256 values requested.
     * @return requestID - A unique identifier of the request. Can be used to match a request to a reponse in fulfillRandomWords. This
     * request ID is separate from any VRF request ID assigned on the partner chain by the VRFProdiver.
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestID);
}
