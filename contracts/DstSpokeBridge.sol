// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./interfaces/ISpokeBridge.sol";
import {IDstSpokeBridge} from "./interfaces/IDstSpokeBridge.sol";
import {IWrappedERC721} from "./interfaces/IWrappedERC721.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {LibBid} from "./libraries/LibBid.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This contract implements the functonalities for a bridge on the destination chain.
 */
abstract contract DstSpokeBridge is IDstSpokeBridge, SpokeBridge {
    using Counters for Counters.Counter;
    using LibBid for LibBid.Transaction;

    constructor(address _hub) SpokeBridge(_hub) {
    }

    function createBid(
        address _receiver,
        uint256 _incomingBidId,
        LibBid.Transaction calldata _transaction
    ) public override payable {
        require(msg.value > 0, "DstSpokeBridge: there is no fee for relayers!");
        require(incomingBids[_incomingBidId].status == IncomingBidStatus.Relayed, "DstSpokeBridge: incoming bid is not relayed!");
        require(incomingBids[_incomingBidId].timestampOfRelayed + 4 hours < block.timestamp, "DstSpokeBridge: too early unwrapping!");
        require(keccak256(abi.encode(_transaction.tokenId, _transaction.owner, _transaction.receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract)) == incomingBids[_incomingBidId].hashedTransaction, "DstSpokeBridge: Not matching hash!");

        require(IWrappedERC721(_transaction.remoteErc721Contract).ownerOf(_transaction.tokenId) == _msgSender(), "DstSpokeBridge: caller is not the owner!");

        IWrappedERC721( _transaction.remoteErc721Contract).burn(_transaction.tokenId);

        outgoingBids[id.current()].status = OutgoingBidStatus.Created;
        outgoingBids[id.current()].fee = msg.value;
        outgoingBids[id.current()].hashedTransaction = keccak256(abi.encode(_transaction.tokenId, _msgSender(), _receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract));

        id.increment();
    }

    function addIncomingBid(
        uint256 _bidId,
        bytes32 _hashedTransaction,
        LibBid.Transaction calldata _transaction
    )  public override onlyActiveRelayer {
        require(incomingBids[_bidId].status == IncomingBidStatus.None, "DstSpokeBridge: there is an incoming bid with the same id!");
        require(keccak256(abi.encode(_transaction.tokenId, _transaction.owner, _transaction.receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract)) == _hashedTransaction, "DstSpokeBridge: Not matching hash!");

        IWrappedERC721(_transaction.remoteErc721Contract).mint(_transaction.receiver, _transaction.tokenId);

        incomingBids[_bidId] = IncomingBid({
            status:IncomingBidStatus.Relayed,
            hashedTransaction:_hashedTransaction,
            timestampOfRelayed:block.timestamp,
            relayer:_msgSender()
        });
    }
}