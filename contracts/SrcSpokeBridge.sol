// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";
import {ISrcSpokeBridge} from "./interfaces/ISrcSpokeBridge.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {LibBid} from "./libraries/LibBid.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

abstract contract SrcSpokeBridge is ISrcSpokeBridge, SpokeBridge {
    using Counters for Counters.Counter;
    using LibBid for LibBid.Transaction;

    address public contractMap;

    constructor(address _contractMap, address _hub) SpokeBridge(_hub) {
        contractMap = _contractMap;
    }

    function createBid(
        address _receiver,
        uint256 _tokenId,
        address _erc721Contract) public override payable {
        require(msg.value > 0, "SrcSpokeBridge: there is no fee for relayers!");

        IERC721(_erc721Contract).safeTransferFrom(msg.sender, address(this), _tokenId);

        outgoingBids[id.current()].status = OutgoingBidStatus.Created;
        outgoingBids[id.current()].fee = msg.value;
        outgoingBids[id.current()].hashedTransaction = keccak256(abi.encode(_tokenId, _msgSender(), _receiver, _erc721Contract, IContractMap(contractMap).getRemote(_erc721Contract)));

        id.increment();
    }

    function addIncomingBid(
        uint256 _bidId,
        bytes32 _hashedTransaction,
        LibBid.Transaction calldata _transaction
    ) public override onlyActiveRelayer {
        require(incomingBids[_bidId].status == IncomingBidStatus.None, "SrcSpokeBridge: there is an incoming bid with the same id!");
        require(keccak256(abi.encode(_transaction.tokenId, _transaction.owner, _transaction.receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract)) == _hashedTransaction, "SrcSpokeBridge: Not matching hash!");
        require(IERC721(_transaction.localErc721Contract).ownerOf(_transaction.tokenId) == address(this),  "SrcSpokeBridge: there is no locked token!");

        incomingBids[_bidId] = IncomingBid({
            status:IncomingBidStatus.Relayed,
            hashedTransaction:_hashedTransaction,
            timestampOfRelayed:block.timestamp,
            relayer:_msgSender()
        });
    }

    function claimNFT(
        uint256 _incomingBidId, 
        LibBid.Transaction calldata _transaction
    ) public override {
        require(incomingBids[_incomingBidId].status == IncomingBidStatus.Relayed,
            "SrcSpokeBride: incoming bid has no Relayed state!");
        require(incomingBids[_incomingBidId].timestampOfRelayed + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");
        require(keccak256(abi.encode(_transaction.tokenId, _transaction.owner, _transaction.receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract)) == incomingBids[_incomingBidId].hashedTransaction, "SrcSpokeBridge: Not matching hash!");

        require(_transaction.receiver == _msgSender(), "SrcSpokeBridge: claimer is not the owner!");

        incomingBids[_incomingBidId].status = IncomingBidStatus.Unlocked;
        IERC721(_transaction.localErc721Contract).safeTransferFrom(address(this), _msgSender(), _transaction.tokenId);
    }
}