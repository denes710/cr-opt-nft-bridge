// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {LibLocalTransaction} from "./libraries/LibLocalTransaction.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

abstract contract SrcSpokeBridge is SpokeBridge {
    using Counters for Counters.Counter;
    using LibLocalTransaction for LibLocalTransaction.LocalTransaction;

    address public contractMap;

    mapping(bytes32 => mapping(address => mapping(uint256 => bool))) claimedProofs;

    constructor(
        address _contractMap,
        address _hub,
        uint256 _transferPerBlock,
        uint256 _transFee
    ) SpokeBridge(_hub, _transferPerBlock, _transFee) {
        contractMap = _contractMap;
    }

    function addNewTransactionToBlock(address _receiver, uint256 _tokenId, address _erc721Contract) public {
        IERC721(_erc721Contract).safeTransferFrom(msg.sender, address(this), _tokenId);

        address remoteContract = IContractMap(contractMap).getRemote(_erc721Contract);
        uint256 currentTxId = localBlocks[localBlockId.current()].length.current();

        localBlocks[localBlockId.current()].transactions[currentTxId] = 
            keccak256(abi.encode(_tokenId, _msgSender(), _receiver, _erc721Contract, remoteContract));

        localBlocks[localBlockId.current()].length.increment();

        emit NewTransactionAddedToBlock(
            localBlockId.current(),
            currentTxId,
            _tokenId,
            _msgSender(),
            _receiver,
            _erc721Contract,
            remoteContract
        );

        if (currentTxId + 1 == TRANS_PER_BLOCK) {
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

        require(msg.value == TRANS_FEE, "SrcSpokeBridge: there is no enough fee for relayers!");

        require(incomingBlock.status == IncomingBlockStatus.Relayed,
            "SrcSpokeBride: incoming block has no Relayed state!");

        require(incomingBlock.timestampOfIncoming + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");

        require(relayers[incomingBlock.relayer].status == RelayerStatus.Active,
            "SrcSpokeBridge: the relayer has no active status");

        require(_verifyMerkleProof(_proof, incomingBlock.transactionRoot, _transaction, _index),
            "SrcSpokeBridge: proof is not correct during claming!");
        require(_transaction.receiver == _msgSender(),
            "SrcSpokeBridge: receiver is not the message sender!");

        require(!claimedProofs[incomingBlock.transactionRoot]
            [_transaction.localErc721Contract]
            [_transaction.tokenId], "SrcSpokeBridge: token is already claimed!");

        claimedProofs[incomingBlock.transactionRoot]
            [_transaction.localErc721Contract]
            [_transaction.tokenId] = true;

        (bool isSent,) = incomingBlock.relayer.call{value: TRANS_FEE}("");
        require(isSent, "Failed to send Ether");

        IERC721(IContractMap(contractMap).getLocal(_transaction.remoteErc721Contract))
            .safeTransferFrom(address(this), _transaction.receiver, _transaction.tokenId);

        emit NFTClaimed(_incomingBlockId, _transaction.remoteErc721Contract, _transaction.receiver,  _transaction.tokenId);
    }
}