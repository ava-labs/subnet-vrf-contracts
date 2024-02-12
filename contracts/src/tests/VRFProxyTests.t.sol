// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {VRFProxy, VRFRequestInfo, VRFResponseInfo} from "../VRFProxy.sol";
import {TeleporterRegistry} from "@teleporter/contracts/src/Teleporter/upgrades/TeleporterRegistry.sol";
import {
    ITeleporterMessenger,
    TeleporterMessageInput,
    TeleporterFeeInfo
} from "@teleporter/contracts/src/Teleporter/ITeleporterMessenger.sol";
import {SimpleBettingGame} from "../SimpleBettingGame.sol";

contract VRFProxyTest is Test {
    address public constant MOCK_TELEPOTER_MESSENGER_ADDRESS = address(0x1111);
    uint256 public constant MOCK_LATEST_TELEPORTER_VERSION = 1;
    address public constant MOCK_TELEPORTER_REGISTRY_ADDRESS = address(0x2222);
    bytes32 public constant MOCK_VRF_PROVIDER_BLOCKCHAIN_ID =
        bytes32(hex"1234567812345678123456781234567812345678123456781234567812345678");
    address public constant MOCK_VRF_PROVIDER_ADDRESS = address(0x3333);
    bytes32 public constant MOCK_KEY_HASH =
        bytes32(hex"aaaabbbbaaaabbbbaaaabbbbaaaabbbbaaaabbbbaaaabbbbaaaabbbbaaaabbbb");
    uint64 public constant MOCK_SUB_ID = 42;
    address public constant MOCK_CONSUMER = address(0x4444);

    VRFProxy public proxy;

    // Events emitted by VRFProxy
    event ConsumerAdded(address indexed consumer);
    event ConsumerRemoved(address indexed consumer);
    event RandomWordsRequested(
        uint256 indexed requestID,
        address indexed requester,
        bytes32 indexed keyHash,
        uint64 subID,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    );
    event RandomWordsFulfilled(uint256 indexed requestID, bool success);

    function setUp() public virtual {
        vm.mockCall(
            MOCK_TELEPORTER_REGISTRY_ADDRESS,
            abi.encodeWithSelector(TeleporterRegistry(MOCK_TELEPORTER_REGISTRY_ADDRESS).latestVersion.selector),
            abi.encode(MOCK_LATEST_TELEPORTER_VERSION)
        );
        vm.mockCall(
            MOCK_TELEPORTER_REGISTRY_ADDRESS,
            abi.encodeWithSelector(TeleporterRegistry(MOCK_TELEPORTER_REGISTRY_ADDRESS).getLatestTeleporter.selector),
            abi.encode(MOCK_TELEPOTER_MESSENGER_ADDRESS)
        );
        vm.mockCall(
            MOCK_TELEPORTER_REGISTRY_ADDRESS,
            abi.encodeWithSelector(
                TeleporterRegistry(MOCK_TELEPORTER_REGISTRY_ADDRESS).getVersionFromAddress.selector,
                MOCK_TELEPOTER_MESSENGER_ADDRESS
            ),
            abi.encode(MOCK_LATEST_TELEPORTER_VERSION)
        );
        proxy = new VRFProxy(
            MOCK_TELEPORTER_REGISTRY_ADDRESS,
            MOCK_VRF_PROVIDER_BLOCKCHAIN_ID,
            MOCK_VRF_PROVIDER_ADDRESS
        );
    }

    function testAddConsumerSucess() public {
        address mockConsumer = address(0x5555);
        _addConsumer(mockConsumer);
    }

    function testAddConsumerZeroAddress() public {
        vm.expectRevert("VRFProxy: zero consumer address");
        proxy.addConsumer(address(0));
    }

    function testAddConsumerNotOwner() public {
        address mockConsumer = address(0x5555);
        address nonOwnerAddress = address(0x6666);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwnerAddress);
        proxy.addConsumer(mockConsumer);
    }

    function addConsumerAlreadyAdded() public {
        address mockConsumer = address(0x5555);
        _addConsumer(mockConsumer);
        proxy.addConsumer(mockConsumer);
        assertTrue(proxy.allowedConsumers(mockConsumer));
    }

    function testRemoveConsumerSuccess() public {
        // Add a consumer.
        address mockConsumer = address(0x5555);
        _addConsumer(mockConsumer);

        // Remove the consumer.
        vm.expectEmit(true, true, true, true, address(proxy));
        emit ConsumerRemoved(mockConsumer);
        proxy.removeConsumer(mockConsumer);
        assertFalse(proxy.allowedConsumers(mockConsumer));
    }

    function testRemoveConsumerNotFound() public {
        // Try to remove the consumer that was never added.
        address mockConsumer = address(0x5555);
        vm.expectRevert("VRFProxy: invalid consumer");
        proxy.removeConsumer(mockConsumer);
    }

    function testRemoveConsumerNotOwner() public {
        address mockConsumer = address(0x5555);
        address nonOwnerAddress = address(0x6666);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(nonOwnerAddress);
        proxy.removeConsumer(mockConsumer);
    }

    function testRequestRandomWordsSuccess() public {
        // Add this contract as a consumer to be able to request values.
        _addConsumer(address(this));

        // Submit a request.
        uint256 expectedRequestID = proxy.requestNonce() + 1;
        uint16 mockMinConfs = 1;
        uint32 mockCallbackGasLimit = 213_000;
        uint32 mockNumWords = 20;
        vm.mockCall(
            MOCK_TELEPOTER_MESSENGER_ADDRESS,
            abi.encodeWithSelector(ITeleporterMessenger.sendCrossChainMessage.selector),
            abi.encode(bytes32(0))
        );
        VRFRequestInfo memory expectedRequest = VRFRequestInfo({
            requestID: expectedRequestID,
            keyHash: MOCK_KEY_HASH,
            subID: MOCK_SUB_ID,
            minimumRequestConfirmations: mockMinConfs,
            callbackGasLimit: mockCallbackGasLimit,
            numWords: mockNumWords
        });
        vm.expectCall(
            MOCK_TELEPOTER_MESSENGER_ADDRESS,
            abi.encodeWithSelector(
                ITeleporterMessenger.sendCrossChainMessage.selector,
                TeleporterMessageInput({
                    destinationBlockchainID: MOCK_VRF_PROVIDER_BLOCKCHAIN_ID,
                    destinationAddress: MOCK_VRF_PROVIDER_ADDRESS,
                    feeInfo: TeleporterFeeInfo({feeTokenAddress: address(0), amount: 0}),
                    requiredGasLimit: proxy.VRF_REQUEST_REQUIRED_GAS(),
                    allowedRelayerAddresses: new address[](0),
                    message: abi.encode(expectedRequest)
                })
            )
        );
        vm.expectEmit(true, true, true, true, address(proxy));
        emit RandomWordsRequested({
            requestID: expectedRequestID,
            requester: address(this),
            keyHash: MOCK_KEY_HASH,
            subID: MOCK_SUB_ID,
            minimumRequestConfirmations: mockMinConfs,
            callbackGasLimit: mockCallbackGasLimit,
            numWords: mockNumWords
        });
        uint256 requestID =
            proxy.requestRandomWords(MOCK_KEY_HASH, MOCK_SUB_ID, mockMinConfs, mockCallbackGasLimit, mockNumWords);
        assertEq(requestID, expectedRequestID);
    }

    function testRequestRandomWordsNotAllowedConsumer() public {
        vm.expectRevert("VRFProxy: unauthorized consumer");
        proxy.requestRandomWords(MOCK_KEY_HASH, MOCK_SUB_ID, 1, 200_000, 1);
    }

    function testReceiveTeleporterMessageSuccess() public {
        // Place a request from the expected consumer.
        uint32 callbackGasLimit = 100_000;
        uint256 requestID = _makeRandomWordsRequest(MOCK_CONSUMER, callbackGasLimit);

        // Format the message to be received.
        uint256[] memory mockValues = new uint256[](1);
        mockValues[0] = 321;
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: requestID, randomWords: mockValues, callbackGasLimit: callbackGasLimit});
        SimpleBettingGame consumer;
        vm.mockCall(
            MOCK_CONSUMER,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, mockValues),
            new bytes(0)
        );
        vm.expectCall(
            MOCK_CONSUMER,
            0,
            callbackGasLimit,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, mockValues)
        );
        vm.expectEmit(true, true, true, true, address(proxy));
        emit RandomWordsFulfilled(requestID, true);
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response));
    }

    function testReceiveTeleporterMessageSuccessCallReverts() public {
        // Place a request from the expected consumer.
        uint32 callbackGasLimit = 100_000;
        uint256 requestID = _makeRandomWordsRequest(MOCK_CONSUMER, callbackGasLimit);

        // Format the message to be received.
        uint256[] memory mockValues = new uint256[](1);
        mockValues[0] = 321;
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: requestID, randomWords: mockValues, callbackGasLimit: callbackGasLimit});

        // Mock the consumer reverting in the call to rawFulfillRandomWords
        SimpleBettingGame consumer;
        vm.mockCall(MOCK_CONSUMER, abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector), new bytes(0));
        vm.mockCallRevert(
            MOCK_CONSUMER,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, mockValues),
            new bytes(0)
        );
        vm.expectCall(
            MOCK_CONSUMER,
            0,
            callbackGasLimit,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, mockValues)
        );
        vm.expectEmit(true, true, true, true, address(proxy));
        emit RandomWordsFulfilled(requestID, false);
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response));
    }

    function testReceiveTeleporterMessageInvalidBlockchainID() public {
        bytes32 otherBlockchainID = bytes32(hex"deaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead");
        vm.expectRevert("VRFProxy: invalid source blockchain ID");
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(otherBlockchainID, MOCK_VRF_PROVIDER_ADDRESS, new bytes(0));
    }

    function testReceiveTeleporterMessageInvalidAddress() public {
        address otherAddress = address(0xbeef);
        vm.expectRevert("VRFProxy: invalid origin sender address");
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, otherAddress, new bytes(0));
    }

    function testReceiveTeleporterMessageInvalidRequester() public {
        // Receive a message for a request ID that is not associated with any request.
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: 42, randomWords: new uint256[](1), callbackGasLimit: 10_000});

        vm.expectRevert("VRFProxy: invalid requester");
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response));
    }

    function testReceiveTeleporterMessageInsufficientGasForCheck() public {
        // Place a request from the expected consumer.
        uint32 callbackGasLimit = 100_000;
        uint256 requestID = _makeRandomWordsRequest(MOCK_CONSUMER, callbackGasLimit);

        // Format the response.
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: requestID, randomWords: new uint256[](1), callbackGasLimit: callbackGasLimit});

        // Expect it to revert if the call to receiveTeleporterMessage doesn't have sufficient gas for GAS_FOR_CALL_EXACT_CHECK.
        // 15,000 is just enough gas to reach the _callWithExactGas call with less than 5,000 gas remaining.
        uint32 gasInsufficientForCheck = 15_000;
        SimpleBettingGame consumer;
        vm.mockCall(
            MOCK_CONSUMER,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, new uint256[](1)),
            new bytes(0)
        );
        vm.etch(MOCK_CONSUMER, new bytes(10));
        vm.expectRevert();
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage{gas: gasInsufficientForCheck}(
            MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response)
        );
    }

    function testReceiveTeleporterMessageInsufficientGasForCall() public {
        // Place a request from the expected consumer.
        uint32 callbackGasLimit = 100_000;
        uint256 requestID = _makeRandomWordsRequest(MOCK_CONSUMER, callbackGasLimit);

        // Format the response.
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: requestID, randomWords: new uint256[](1), callbackGasLimit: callbackGasLimit});

        // Expect it to revert if the call to receiveTeleporterMessage doesn't have sufficient gas for the callback gas limit.
        SimpleBettingGame consumer;
        vm.mockCall(
            MOCK_CONSUMER,
            abi.encodeWithSelector(consumer.rawFulfillRandomWords.selector, requestID, new uint256[](1)),
            new bytes(0)
        );
        vm.expectRevert();
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage{gas: callbackGasLimit - 1}(
            MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response)
        );
    }

    function testReceiveTeleporterMessageRequesterIsNotContract() public {
        // Place a request from the expected consumer.
        uint32 callbackGasLimit = 100_000;
        uint256 requestID = _makeRandomWordsRequest(MOCK_CONSUMER, callbackGasLimit);

        // Format the message to be received.
        VRFResponseInfo memory response =
            VRFResponseInfo({requestID: requestID, randomWords: new uint256[](1), callbackGasLimit: callbackGasLimit});

        // Mock the consumer/requesting being an EOA with no code.
        vm.etch(MOCK_CONSUMER, new bytes(0));

        // Expect it to revert.
        vm.expectRevert();
        vm.prank(MOCK_TELEPOTER_MESSENGER_ADDRESS);
        proxy.receiveTeleporterMessage(MOCK_VRF_PROVIDER_BLOCKCHAIN_ID, MOCK_VRF_PROVIDER_ADDRESS, abi.encode(response));
    }

    function _addConsumer(address consumer) internal {
        vm.expectEmit(true, true, true, true, address(proxy));
        emit ConsumerAdded(consumer);
        proxy.addConsumer(consumer);
        assertTrue(proxy.allowedConsumers(consumer));
    }

    function _makeRandomWordsRequest(address requester, uint32 callbackGasLimit) internal returns (uint256) {
        _addConsumer(requester);
        vm.mockCall(
            MOCK_TELEPOTER_MESSENGER_ADDRESS,
            abi.encodeWithSelector(ITeleporterMessenger.sendCrossChainMessage.selector),
            abi.encode(bytes32(0))
        );
        vm.prank(requester);
        return proxy.requestRandomWords(MOCK_KEY_HASH, MOCK_SUB_ID, 1, callbackGasLimit, 1);
    }
}
