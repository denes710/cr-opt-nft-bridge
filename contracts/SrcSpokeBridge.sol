// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

abstract contract SrcSpokeBridge is SpokeBridge {
    using Counters for Counters.Counter;

    address public contractMap;

    mapping(bytes32 => mapping(address => mapping(uint256 => bool))) claimedProofs;

    constructor(address _contractMap, address _hub) SpokeBridge(_hub) {
        contractMap = _contractMap;
    }

    function addNewTransactionToBlock(address _receiver, uint256 _tokenId, address _erc721Contract) public override {
        IERC721(_erc721Contract).safeTransferFrom(msg.sender, address(this), _tokenId);

        localBlocks[localBlockId.current()].transactions.push(LocalTransaction({
            tokenId:_tokenId,
            maker:_msgSender(),
            receiver:_receiver,
            localErc721Contract:_erc721Contract,
            remoteErc721Contract:IContractMap(contractMap).getRemote(_erc721Contract)
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

        IERC721(_transaction.localErc721Contract)
            .safeTransferFrom(address(this), _transaction.receiver, _transaction.tokenId);
    }
}