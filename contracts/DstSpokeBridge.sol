// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IWrappedERC721} from "./interfaces/IWrappedERC721.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This contract implements the functonalities for a bridge on the destination chain.
 */
abstract contract DstSpokeBridge is SpokeBridge {
    using Counters for Counters.Counter;

    struct Claim {
        uint256 timestampOfClaiming;
        bool isClaimed;
    }

    mapping(bytes32 => mapping(address => mapping(uint256 => bool))) claimedProofs;
    mapping(address => mapping(uint256 => uint256)) claimedTokens;

    constructor(address _hub) SpokeBridge(_hub) {
    }

    function addNewTransactionToBlock(address _receiver, uint256 _tokenId, address _erc721Contract) public override {
        require(IWrappedERC721(_erc721Contract).ownerOf(_tokenId) == _msgSender(), "DstSpokeBridge: owner is not the caller!");
        require(claimedTokens[_erc721Contract][_tokenId] + 4 hours < block.timestamp, "DesSpokeBridge: challenging time window is not expired yet!");

        IWrappedERC721(_erc721Contract).burn(_tokenId);

        localBlocks[localBlockId.current()].transactions.push(LocalTransaction({
            tokenId:_tokenId,
            maker:_msgSender(),
            receiver:_receiver,
            localErc721Contract:address(0), // it is not used
            remoteErc721Contract:_erc721Contract
        }));

        if (localBlocks[localBlockId.current()].transactions.length == TRANS_PER_BLOCK) {
            localBlockId.increment();
        }
    }

    function claimNFT(
        uint256 _incomingBlockId,
        LocalTransaction calldata _transaction,
        bytes32[] calldata _proof,
        uint _index
    ) public override payable {
        IncomingBlock memory incomingBlock = incomingBlocks[_incomingBlockId];

        require(msg.value == TRANS_FEE, "DstSpokeBridge: there is no enough fee for relayers!");

        require(incomingBlock.status == IncomingBlockStatus.Relayed,
            "DstSpokeBride: incoming block has no Relayed state!");

        // there is no timestamp check only druing adding to the block

        // TODO versioning, better check for malicious block
        require(relayers[incomingBlock.relayer].status == RelayerStatus.Active,
            "DstSpokeBridge: the relayer has no active status");

        require(_verifyMerkleProof(_proof, incomingBlock.transactionRoot, _transaction, _index),
            "DstSpokeBridge: proof is not correct during claming!");

        require(_transaction.receiver == _msgSender(),
            "DstSpokeBridge: receiver is not the message sender!");


        require(!claimedProofs[incomingBlock.transactionRoot]
            [_transaction.remoteErc721Contract]
            [_transaction.tokenId], "DstSpokeBridge: token is already claimed!");

        claimedProofs[incomingBlock.transactionRoot]
            [_transaction.remoteErc721Contract]
            [_transaction.tokenId] = true;

        claimedTokens[_transaction.remoteErc721Contract][_transaction.tokenId] = block.timestamp;
        

        IWrappedERC721(_transaction.remoteErc721Contract).mint(_transaction.receiver, _transaction.tokenId);
    }
}