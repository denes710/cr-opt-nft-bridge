// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

abstract contract SrcSpokeBridge is SpokeBridge {
    using Counters for Counters.Counter;

    address public contractMap;

    constructor(address _contractMap, address _hub) SpokeBridge(_hub) {
        contractMap = _contractMap;
    }

    function addNewTransactionToBlock(address _receiver, uint256 _tokenId, address _erc721Contract) public override {
        // it is on nft claim        require(msg.value > 0, "SrcSpokeBridge: there is no fee for relayers!");

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

    function claimNFT(uint256 _incomingBidId) public override payable {
//        IncomingBid memory bid = incomingBids[_incomingBidId];
/*
        require(bid.status == IncomingBidStatus.Relayed,
            "SrcSpokeBride: incoming bid has no Relayed state!");
        require(bid.timestampOfRelayed + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");
        require(bid.receiver == _msgSender(), "SrcSpokeBridge: claimer is not the owner!");

        bid.status = IncomingBidStatus.Unlocked;
        IERC721(outgoingBids[incomingBids[_incomingBidId].outgoingId].localErc721Contract)
            .safeTransferFrom(address(this), _msgSender(), bid.tokenId);
            */
    }
}