// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IContractMap} from "./interfaces/IContractMap.sol";
import {ISrcSpokeBridge} from "./interfaces/ISrcSpokeBridge.sol";

import {SpokeBridge} from "./SpokeBridge.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

// FIXME comments
/**
 * @notice
 */
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

        ERC721(_erc721Contract).safeTransferFrom(msg.sender, address(this), _tokenId);

        outgoingBids[id.current()] = OutgoingBid({
            id:id.current(),
            status:OutgoingBidStatus.Created,
            fee:uint16(msg.value),
            maker:_msgSender(),
            receiver:_receiver,
            tokenId:_tokenId,
            erc721Contract:_erc721Contract,
            timestampOfBought:0,
            buyer:address(0)
        });

        id.increment();
    }

    function challengeUnlocking(uint256 _bidId) public override payable {
        require(msg.value == CHALLENGE_AMOUNT);
        require(incomingBids[_bidId].status == IncomingBidStatus.Relayed);
        require(incomingBids[_bidId].timestampOfRelayed + 4 hours > block.timestamp);

        incomingBids[_bidId].status = IncomingBidStatus.Challenged;

        challengedIncomingBids[_bidId].challenger = _msgSender();
        challengedIncomingBids[_bidId].status = ChallengeStatus.Challenged;

        relayers[incomingBids[_bidId].relayer].status = RelayerStatus.Challenged;
    }

    function sendProof(bool _isOutgoingBid, uint256 _bidId) public override {
        // FIXME some kind of time check
        if (_isOutgoingBid) {
            OutgoingBid memory bid = outgoingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.status,
                bid.receiver,
                bid.tokenId,
                bid.erc721Contract,
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
                // FIXME it could be better with remote and local contract following
                bid.status == IncomingBidStatus.None ?
                    bid.erc721Contract : IContractMap(contractMap).getRemote(bid.erc721Contract),
                bid.relayer,
                _msgSender()
            );

            data = abi.encode(data, false);

            _sendMessage(data);
        }
    }

    function receiveProof(bytes memory _proof) public override onlyHub {
        (bytes memory bidBytes, bool isOutgoingBid) = abi.decode(_proof, (bytes, bool));
        if (isOutgoingBid) {
            // On the source chain during unlocking(wrong relaying), revert the incoming messsage
            (
                uint256 bidId,
                OutgoingBidStatus status,
                address receiver,
                uint256 tokenId,
                address localContract,
                address relayer // FIXME challenger has to include
            ) = abi.decode(bidBytes, (uint256, OutgoingBidStatus, address, uint256, address, address));

            // FIXME time window check
            IncomingBid memory localChallengedBid = incomingBids[bidId];

            require(localChallengedBid.status != IncomingBidStatus.None, "SrcSpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfRelayed + 4 hours > block.timestamp, "SrcSpokeBridge: Time window is expired!");

            if (status == OutgoingBidStatus.Bought &&
                localChallengedBid.receiver == receiver &&
                localChallengedBid.tokenId == tokenId &&
                localChallengedBid.erc721Contract == localContract &&
                localChallengedBid.relayer == relayer) {
                // False challenging
                localChallengedBid.status = IncomingBidStatus.Relayed;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Active;

                if (challengedIncomingBids[bidId].status == ChallengeStatus.Challenged) {
                    // Dealing with the challenger
                    challengedIncomingBids[bidId].status = ChallengeStatus.None;

                    // FIXME: Claim can be better !!!
                    (bool isSent,) = challengedIncomingBids[bidId].challenger.call{value: CHALLENGE_AMOUNT/4}("");
                    require(isSent, "Failed to send Ether");
                }
            } else {
                // Proved malicious bid(behavior)
                localChallengedBid.status = IncomingBidStatus.Malicious;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Malicious;

                // Burning the wrong minted token - it is not possible to claim from the incoming
                // IWrappedERC721(localChallengedBid.localContract).burn(localChallengedBid.tokenId);

                // FIXME do something with lockedId

                // Dealing with the challenger
                if (challengedIncomingBids[bidId].status == ChallengeStatus.Challenged) {

                    (bool isSent,) = challengedIncomingBids[bidId].challenger.call{
                        value: CHALLENGE_AMOUNT + STAKE_AMOUNT/3}("");

                    require(isSent, "Failed to send Ether");
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
                IContractMap(contractMap).getRemote(localChallengedBid.erc721Contract) == remoteContract &&
                localChallengedBid.buyer == relayer
            ) {
                // False challenging
                require(false, "SrcSpokeBridge: False challenging!");

            } else {
                // Proved malicious bid(behavior)
                // localChallengedBid data is not corresponding to the bid
                localChallengedBid.status = OutgoingBidStatus.Malicious;
                relayers[localChallengedBid.buyer].status = RelayerStatus.Malicious;

                // FIXME unlock NFT
                // Burning the wrong minted token
                // IWrappedERC721(localChallengedBid.localContract).mint(
                //    localChallengedBid.maker, localChallengedBid.tokenId);

                // Dealing with the challenger
                (bool isSent,) = challenger.call{value: CHALLENGE_AMOUNT + STAKE_AMOUNT/3}("");
                // FIXME it is questionable
                require(isSent, "Failed to send Ether");
            }
        }
    }

    function unlocking(
        uint256 _lockingBidId,
        uint256 _bidId,
        address _to,
        uint256 _tokenId,
        address _remoteErc721Contract
    )  public override onlyActiveRelayer {
        require(outgoingBids[_lockingBidId].status == OutgoingBidStatus.Bought, "SrcSpokeBridge: the outgoing bid is not bought!");
        require(incomingBids[_bidId].status == IncomingBidStatus.None, "SrcSpokeBridge: there is an incoming bid with the same id!");
        require(outgoingBids[_lockingBidId].timestampOfBought + 4 hours < block.timestamp,
            "SrcSpokeBridge: the challenging period is not expired yet!");
        address localErc721Contract = IContractMap(contractMap).getLocal(_remoteErc721Contract);
        require(ERC721(localErc721Contract).ownerOf(_tokenId) == address(this),  "SrcSpokeBridge: there is no locked token!");

        outgoingBids[_lockingBidId].status = OutgoingBidStatus.Unlocked;

        incomingBids[_bidId] = IncomingBid({
            remoteId:_bidId,
            outgoingId:_lockingBidId,
            status:IncomingBidStatus.Relayed,
            receiver:_to,
            tokenId:_tokenId,
            erc721Contract:localErc721Contract,
            timestampOfRelayed:block.timestamp,
            relayer:_msgSender()
        });

        // FIXME missing transfer / claim / something
    }
}