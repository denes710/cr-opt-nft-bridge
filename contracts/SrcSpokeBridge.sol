// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";
import {ISrcSpokeBridge} from "./interfaces/ISrcSpokeBridge.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

abstract contract SrcSpokeBridge is ISrcSpokeBridge, SpokeBridge {
    using Counters for Counters.Counter;

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

        outgoingBids[id.current()] = OutgoingBid({
            status:OutgoingBidStatus.Created,
            fee:msg.value,
            maker:_msgSender(),
            receiver:_receiver,
            tokenId:_tokenId,
            localErc721Contract:_erc721Contract,
            remoteErc721Contract:IContractMap(contractMap).getRemote(_erc721Contract),
            timestampOfBought:0,
            buyer:address(0)
        });

        id.increment();
    }

    function challengeUnlocking(uint256 _bidId) public override payable {
        super._challengeUnlocking(_bidId);
    }

    function sendProof(bool _isOutgoingBid, uint256 _bidId) public override {
        if (_isOutgoingBid) {
            OutgoingBid memory bid = outgoingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.status,
                bid.receiver,
                bid.tokenId,
                bid.remoteErc721Contract,
                bid.buyer
            );

            data = abi.encode(data, true);

            _sendMessage(data);
        } else {
            require(incomingBids[_bidId].timestampOfRelayed + 4 hours < block.timestamp,
                "SrcSpokeBridge: too early to send proof!");

            IncomingBid memory bid = incomingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.status,
                bid.receiver,
                bid.tokenId,
                outgoingBids[bid.outgoingId].remoteErc721Contract,
                bid.relayer,
                _msgSender()
            );

            data = abi.encode(data, false);

            _sendMessage(data);
        }
    }

    function receiveProof(bytes memory _proof) public override onlyHub {
        (bytes memory bidBytes, bool isBidOutgoing) = abi.decode(_proof, (bytes, bool));
        if (isBidOutgoing) {
            // On the source chain during unlocking(wrong relaying), revert the incoming messsage
            (
                uint256 bidId,
                OutgoingBidStatus status, // FIXME maybe it is not useful
                address receiver,
                uint256 tokenId,
                address remoteContract,
                address relayer
            ) = abi.decode(bidBytes, (uint256, OutgoingBidStatus, address, uint256, address, address));

            IncomingBid memory localChallengedBid = incomingBids[bidId];

            require(localChallengedBid.status != IncomingBidStatus.None, "SrcSpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfRelayed + 4 hours > block.timestamp, "SrcSpokeBridge: Time window is expired!");

            if (status == OutgoingBidStatus.Bought  &&
                localChallengedBid.receiver == receiver &&
                localChallengedBid.tokenId == tokenId &&
                localChallengedBid.remoteErc721Contract == remoteContract &&
                localChallengedBid.relayer == relayer) {
                // False challenging
                localChallengedBid.status = IncomingBidStatus.Relayed;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Active;
                challengedIncomingBids[bidId].status = ChallengeStatus.None;
            } else {
                // Proved malicious bid(behavior)
                localChallengedBid.status = IncomingBidStatus.Malicious;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Malicious;

                outgoingBids[localChallengedBid.outgoingId].status = OutgoingBidStatus.Bought;

                // Dealing with the challenger
                if (challengedIncomingBids[bidId].status == ChallengeStatus.Challenged) {
                    incomingChallengeRewards[bidId].challenger = challengedIncomingBids[bidId].challenger;
                    incomingChallengeRewards[bidId].amount = CHALLENGE_AMOUNT + STAKE_AMOUNT / 4;
                }
                challengedIncomingBids[bidId].status = ChallengeStatus.Proved;
            }
        } else {
            // On the source chain during locking(no relaying), revert locking
            (
                uint256 bidId,
                IncomingBidStatus status, // FIXME maybe not useful
                address receiver,
                uint256 tokenId,
                address remoteContract,
                address relayer,
                address challenger
            ) = abi.decode(bidBytes, (uint256, IncomingBidStatus, address, uint256, address, address, address));

            OutgoingBid memory localChallengedBid = outgoingBids[bidId];

            require(localChallengedBid.status != OutgoingBidStatus.None, "SrcSpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfBought + 4 hours < block.timestamp, "SrcSpokeBridge: Time window is not expired!");

            if (status != IncomingBidStatus.Malicious &&
                localChallengedBid.receiver == receiver &&
                localChallengedBid.tokenId == tokenId &&
                localChallengedBid.remoteErc721Contract == remoteContract &&
                localChallengedBid.buyer == relayer
            ) {
                // False challenging
                require(false, "SrcSpokeBridge: False challenging!");

            } else {
                // Proved malicious bid - no relaying
                localChallengedBid.status = OutgoingBidStatus.Malicious;
                relayers[localChallengedBid.buyer].status = RelayerStatus.Malicious;

                IERC721(localChallengedBid.localErc721Contract)
                    .safeTransferFrom(address(this), localChallengedBid.maker, localChallengedBid.tokenId);

                outgoingChallengeRewards[bidId].challenger = challenger;
                outgoingChallengeRewards[bidId].amount = STAKE_AMOUNT / 4;

                challengedIncomingBids[bidId].status = ChallengeStatus.Proved;
            }
        }
    }

    function unlocking(
        uint256 _lockingBidId,
        uint256 _bidId,
        address _to
    )  public override onlyActiveRelayer {
        require(outgoingBids[_lockingBidId].status == OutgoingBidStatus.Bought, "SrcSpokeBridge: the outgoing bid is not bought!");
        require(incomingBids[_bidId].status == IncomingBidStatus.None, "SrcSpokeBridge: there is an incoming bid with the same id!");
        require(outgoingBids[_lockingBidId].timestampOfBought + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");

        require(IERC721(outgoingBids[_lockingBidId].localErc721Contract).ownerOf(outgoingBids[_lockingBidId].tokenId) == address(this),  "SrcSpokeBridge: there is no locked token!");

        outgoingBids[_lockingBidId].status = OutgoingBidStatus.Unlocked;

        incomingBids[_bidId] = IncomingBid({
            outgoingId:_lockingBidId,
            status:IncomingBidStatus.Relayed,
            receiver:_to,
            tokenId:outgoingBids[_lockingBidId].tokenId,
            remoteErc721Contract:outgoingBids[_lockingBidId].localErc721Contract,
            timestampOfRelayed:block.timestamp,
            relayer:_msgSender()
        });
    }

    function claimNFT(uint256 _incomingBidId) external {
        IncomingBid memory bid = incomingBids[_incomingBidId];

        require(bid.status == IncomingBidStatus.Relayed,
            "SrcSpokeBride: incoming bid has no Relayed state!");
        require(bid.timestampOfRelayed + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");
        require(bid.receiver == _msgSender(), "SrcSpokeBridge: claimer is not the owner!");

        bid.status = IncomingBidStatus.Unlocked;
        IERC721(outgoingBids[incomingBids[_incomingBidId].outgoingId].localErc721Contract)
            .safeTransferFrom(address(this), _msgSender(), bid.tokenId);
    }
}