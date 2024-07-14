// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SendParam, MessagingReceipt, OFTReceipt} from "@layerzerolabs/oft/interfaces/IOFT.sol";
import {MessagingFee, Origin} from "@layerzerolabs/oft/interfaces/ILayerZeroEndpointV2.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft/libs/OFTComposeMsgCodec.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft/libs/OFTMsgCodec.sol";
import {OFTWrappedERC20} from "./OFTWrappedERC20.sol";
import {PoolKey} from "./PancakeV4Structs.sol";
import {ICaptainHook} from "./ICaptainHook.sol";

contract CaptainHookOFT is OFTWrappedERC20 {
    ICaptainHook public immutable captainHook;

    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _baseToken,
        address _captainHook
    ) OFTWrappedERC20(_name, _symbol, _lzEndpoint, _delegate, _baseToken) {
        captainHook = ICaptainHook(_captainHook);
    }

    function sendAsCollateral(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress,
        PoolKey calldata key
    ) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        (uint256 amountSentLD, uint256 amountReceivedLD) =
            _debit(_sendParam.amountLD, _sendParam.minAmountLD, _sendParam.dstEid);

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        bytes memory keyWithMessage = abi.encode(key, message);

        msgReceipt = _lzSend(_sendParam.dstEid, keyWithMessage, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD, amountReceivedLD);
    }

    function quoteSendAsCollateral(SendParam calldata _sendParam, PoolKey calldata key, bool _payInLzToken)
        external
        view
        virtual
        returns (MessagingFee memory msgFee)
    {
        (, uint256 amountReceivedLD) = _debitView(_sendParam.amountLD, _sendParam.minAmountLD, _sendParam.dstEid);

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        bytes memory keyWithMessage = abi.encode(key, message);

        // @dev Calculates the LayerZero fee for the send() operation.
        return _quote(_sendParam.dstEid, keyWithMessage, options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address, /*_executor*/ // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    ) internal virtual override {
        bool isCollateralSend;
        address toAddress;
        uint256 amountReceivedLD;

        bytes memory lzMessage;

        try this.tryDecodeMsg(_message) {
            isCollateralSend = true;
        } catch (bytes memory) {}

        if (isCollateralSend) {
            (bytes memory message, PoolKey memory key) = abi.decode(_message, (bytes, PoolKey));
            toAddress = sendTo(message).bytes32ToAddress();
            amountReceivedLD = _credit(toAddress, _toLD(amountSD(message)), _origin.srcEid);

            captainHook.depositCollateral(key, amountReceivedLD);

            lzMessage = message;
        } else {
            toAddress = _message.sendTo().bytes32ToAddress();
            // @dev Credit the amountLD to the recipient and return the ACTUAL amount the recipient received in local decimals
            amountReceivedLD = _credit(toAddress, _toLD(_message.amountSD()), _origin.srcEid);
            lzMessage = _message;
        }

        if (isComposed(lzMessage)) {
            // @dev Proprietary composeMsg format for the OFT.
            bytes memory composeMsg =
                OFTComposeMsgCodec.encode(_origin.nonce, _origin.srcEid, amountReceivedLD, composeMsgMemory(lzMessage));

            // @dev Stores the lzCompose payload that will be executed in a separate tx.
            // Standardizes functionality for executing arbitrary contract invocation on some non-evm chains.
            // @dev The off-chain executor will listen and process the msg based on the src-chain-callers compose options passed.
            // @dev The index is used when a OApp needs to compose multiple msgs on lzReceive.
            // For default OFT implementation there is only 1 compose msg per lzReceive, thus its always 0.
            endpoint.sendCompose(toAddress, _guid, 0, /* the index of the composed message*/ composeMsg);
        }

        emit OFTReceived(_guid, _origin.srcEid, toAddress, amountReceivedLD);
    }

    function tryDecodeMsg(bytes calldata _message) external view {
        if (msg.sender != address(this)) revert();
        abi.decode(_message, (bytes, PoolKey));
    }

    function sendTo(bytes memory _msg) internal pure returns (bytes32) {
        // Ensure the message is at least 32 bytes long
        require(_msg.length >= 32, "Message too short");

        // Decode the first 32 bytes as bytes32
        bytes32 sendToAddress;
        assembly {
            sendToAddress := mload(add(_msg, 32))
        }
        return sendToAddress;
    }

    function amountSD(bytes memory _msg) internal pure returns (uint64) {
        // Ensure the message is at least 40 bytes long
        require(_msg.length >= 40, "Message too short");

        // Decode the bytes from offset 32 to 40 as uint64
        uint64 amount;
        assembly {
            amount := mload(add(_msg, 40))
        }
        return amount;
    }

    function isComposed(bytes memory _msg) internal pure returns (bool) {
        uint8 SEND_AMOUNT_SD_OFFSET = 40;
        return _msg.length > SEND_AMOUNT_SD_OFFSET;
    }

    function composeMsgMemory(bytes memory _msg) internal pure returns (bytes memory) {
        uint8 SEND_AMOUNT_SD_OFFSET = 40;
        require(_msg.length >= SEND_AMOUNT_SD_OFFSET, "Message too short");

        // Calculate the length of the new message
        uint256 newLength = _msg.length - SEND_AMOUNT_SD_OFFSET;

        // Create a new bytes array to hold the result
        bytes memory result = new bytes(newLength);

        // Copy the data from the original message starting from SEND_AMOUNT_SD_OFFSET to the end
        for (uint256 i = 0; i < newLength; i++) {
            result[i] = _msg[SEND_AMOUNT_SD_OFFSET + i];
        }

        return result;
    }
}
