// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./interfaces/ISpokeBridge.sol";
import {IDstSpokeBridge} from "./interfaces/IDstSpokeBridge.sol";
import {IWrappedERC721} from "./interfaces/IWrappedERC721.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This contract implements the functonalities for a bridge on the destination chain.
 */
abstract contract DstSpokeBridge is IDstSpokeBridge, SpokeBridge {
    using Counters for Counters.Counter;

    constructor(address _hub) SpokeBridge(_hub) {
    }

    function createBid(
        address _receiver,
        uint256 _tokenId,
        address _erc721Contract,
        uint256 _incomingBidId) public override payable {
        require(msg.value > 0, "DstSpokeBridge: there is no fee for relayers!");
        require(incomingBids[_incomingBidId].status == IncomingBidStatus.Relayed, "DstSpokeBridge: incoming bid is not relayed!");
        require(incomingBids[_incomingBidId].timestampOfRelayed + 4 hours < block.timestamp, "DstSpokeBridge: too early unwrapping!");

        IWrappedERC721(_erc721Contract).safeTransferFrom(msg.sender, address(this), _tokenId);

        outgoingBids[id.current()] = OutgoingBid({
            status:OutgoingBidStatus.Created,
            fee:msg.value,
            maker:_msgSender(),
            receiver:_receiver,
            tokenId:_tokenId,
            localErc721Contract:_erc721Contract,
            remoteErc721Contract:address(0),
            timestampOfBought:0,
            buyer:address(0)
        });

        id.increment();
    }

    function buyBid(uint256 _bidId) public override(ISpokeBridge, SpokeBridge) onlyActiveRelayer() {
        super.buyBid(_bidId);
        IWrappedERC721(outgoingBids[_bidId].localErc721Contract).burn(outgoingBids[_bidId].tokenId);
    }

    function challengeMinting(uint256 _bidId) public override payable {
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
                bid.localErc721Contract,
                bid.buyer
            );

            data = abi.encode(data, true);

            _sendMessage(data);
        } else {
            require(incomingBids[_bidId].timestampOfRelayed + 4 hours < block.timestamp,
                "DstSpokeBridge: too early to send proof!");

            IncomingBid memory bid = incomingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.status,
                bid.receiver,
                bid.tokenId,
                bid.remoteErc721Contract,
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
            // On the dest chain during minting(wrong relaying), revert minting
            (
                uint256 bidId,
                OutgoingBidStatus status,
                address receiver,
                uint256 tokenId,
                address localContract,
                address relayer
            ) = abi.decode(bidBytes, (uint256, OutgoingBidStatus, address, uint256, address, address));

            IncomingBid memory localChallengedBid = incomingBids[bidId];

            require(localChallengedBid.status != IncomingBidStatus.None, "DstSpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfRelayed + 4 hours > block.timestamp, "DstSpokeBridge: Time window is expired!");

            if (status == OutgoingBidStatus.Bought &&
                localChallengedBid.receiver == receiver &&
                localChallengedBid.tokenId == tokenId &&
                localChallengedBid.remoteErc721Contract == localContract &&
                localChallengedBid.relayer == relayer) {
                // False challenging
                localChallengedBid.status = IncomingBidStatus.Relayed;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Active;
                challengedIncomingBids[bidId].status = ChallengeStatus.None;
            } else {
                // Proved malicious bid(behavior)
                localChallengedBid.status = IncomingBidStatus.Malicious;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Malicious;

                // Burning the wrong minted token
                IWrappedERC721(localChallengedBid.remoteErc721Contract).burn(localChallengedBid.tokenId);

                // Dealing with the challenger
                if (challengedIncomingBids[bidId].status == ChallengeStatus.Challenged) {
                    incomingChallengeRewards[bidId].challenger = challengedIncomingBids[bidId].challenger;
                    incomingChallengeRewards[bidId].amount = CHALLENGE_AMOUNT + STAKE_AMOUNT / 4;
                }
                challengedIncomingBids[bidId].status = ChallengeStatus.Proved;
            }
        } else {
            // On the dest chain during burning(no relaying), revert burning
            (
                uint256 bidId,
                IncomingBidStatus status,
                address receiver,
                uint256 tokenId,
                address localContract,
                address relayer,
                address challenger
            ) = abi.decode(bidBytes, (uint256, IncomingBidStatus, address, uint256, address, address, address));

            OutgoingBid memory localChallengedBid = outgoingBids[bidId];

            require(localChallengedBid.status != OutgoingBidStatus.None, "DstSpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfBought + 4 hours < block.timestamp, "DstSpokeBridge: Time window is not expired!");

            if (status == IncomingBidStatus.Relayed &&
                localChallengedBid.receiver == receiver &&
                localChallengedBid.tokenId == tokenId &&
                localChallengedBid.localErc721Contract == localContract &&
                localChallengedBid.buyer == relayer
            ) {
                // False challenging
                require(false, "DstSpokeBridge: False challenging!");
            } else {
                // Proved malicious bid(behavior)
                localChallengedBid.status = OutgoingBidStatus.Malicious;
                relayers[localChallengedBid.buyer].status = RelayerStatus.Malicious;

                // Minting the wrong burned token
                IWrappedERC721(localChallengedBid.localErc721Contract).mint(
                    localChallengedBid.maker, localChallengedBid.tokenId);

                outgoingChallengeRewards[bidId].challenger = challenger;
                outgoingChallengeRewards[bidId].amount = STAKE_AMOUNT / 4;

                challengedIncomingBids[bidId].status = ChallengeStatus.Proved;
            }
        }
    }

    function minting(
        uint256 _bidId,
        address _to,
        uint256 _tokenId,
        address _erc721Contract
    )  public override onlyActiveRelayer {
        require(incomingBids[_bidId].status == IncomingBidStatus.None);

        IWrappedERC721(_erc721Contract).mint(_to, _tokenId);

        incomingBids[_bidId] = IncomingBid({
            outgoingId:0,
            status:IncomingBidStatus.Relayed,
            receiver:_to,
            tokenId:_tokenId,
            remoteErc721Contract:_erc721Contract,
            timestampOfRelayed:block.timestamp,
            relayer:_msgSender()
        });
    }
}