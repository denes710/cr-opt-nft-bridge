// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IWrappedERC721} from "./interfaces/IWrappedERC721.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {LibLocalTransaction} from "./libraries/LibLocalTransaction.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This contract implements the functonalities for a bridge on the destination chain.
 */
abstract contract DstSpokeBridge is SpokeBridge {
    using Counters for Counters.Counter;
    using LibLocalTransaction for LibLocalTransaction.LocalTransaction;

    struct Claim {
        uint256 timestampOfClaiming;
        bool isClaimed;
    }

    constructor(
        address _hub,
        uint256 _transferPerBlock,
        uint256 _transFee
    ) SpokeBridge(_hub, _transferPerBlock, _transFee) {
    }

    function addNewTransactionToBlock(
        address _newReceiver,
        uint256 _incomingBlockId,
        LibLocalTransaction.LocalTransaction calldata _transaction,
        bytes32[] calldata _proof,
        uint _index
    ) public {
        require(_verifyMerkleProof(_proof, incomingBlocks[_incomingBlockId].transactionRoot, _transaction, _index),
            "DstSpokeBridge: proof is not correct unwrapping!");
        require(IWrappedERC721(_transaction.remoteErc721Contract).ownerOf(_transaction.tokenId) == _msgSender(),
            "DstSpokeBridge: owner is not the caller!");
        require(incomingBlocks[_incomingBlockId].timestampOfIncoming + 4 hours < block.timestamp,
            "DesSpokeBridge: challenging time window is not expired yet!");

        IWrappedERC721(_transaction.remoteErc721Contract).burn(_transaction.tokenId);

        localBlocks[localBlockId.current()].transactions.push(LibLocalTransaction.LocalTransaction({
            tokenId:_transaction.tokenId,
            maker:_msgSender(),
            receiver:_newReceiver,
            localErc721Contract:_transaction.localErc721Contract, // it is not used / maybe?
            remoteErc721Contract:_transaction.remoteErc721Contract
        }));

        if (localBlocks[localBlockId.current()].transactions.length == TRANS_PER_BLOCK) {
            localBlockId.increment();
        }
    }

    function claimNFT(
        uint256 _incomingBlockId,
        LibLocalTransaction.LocalTransaction calldata _transaction,
        bytes32[] calldata _proof,
        uint _index
    ) public override payable onlyInActiveStatus {
        IncomingBlock memory incomingBlock = incomingBlocks[_incomingBlockId];

        require(msg.value == TRANS_FEE, "DstSpokeBridge: there is no enough fee for relayers!");

        require(incomingBlock.status == IncomingBlockStatus.Relayed,
            "DstSpokeBridge: incoming block has no Relayed state!");

        // there is no timestamp check only druing adding to the block

        require(relayers[incomingBlock.relayer].status == RelayerStatus.Active,
            "DstSpokeBridge: the relayer has no active status");

        require(_verifyMerkleProof(_proof, incomingBlock.transactionRoot, _transaction, _index),
            "DstSpokeBridge: proof is not correct during claming!");

        require(_transaction.receiver == _msgSender(),
            "DstSpokeBridge: receiver is not the message sender!");

        (bool isSent,) = incomingBlock.relayer.call{value: TRANS_FEE}("");
        require(isSent, "Failed to send Ether");

        if (_isMinted(_transaction.remoteErc721Contract, _transaction.tokenId) != address(0)) {
            IWrappedERC721(_transaction.remoteErc721Contract).burn(_transaction.tokenId);
        }

        IWrappedERC721(_transaction.remoteErc721Contract).mint(_transaction.receiver, _transaction.tokenId);
    }

    function _isMinted(address _contract, uint256 _tokenId) internal view returns (address) {
        try IWrappedERC721(_contract).ownerOf(_tokenId) returns (address addr) {
            return addr;
        } catch Error(string memory) {
        }

        return address(0);
    }
}