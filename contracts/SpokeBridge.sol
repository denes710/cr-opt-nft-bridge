// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./interfaces/ISpokeBridge.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This abstract contract is the common base class for src and dst bridges.
 * The src and dst bridges have lots of common functionalities.
 */
abstract contract SpokeBridge is ISpokeBridge, Ownable {
    using Counters for Counters.Counter;

    // TODO every value is necessary?
    enum OutgoingBidStatus {
        None,
        Created,
        Bought,
        Challenged,
        Malicious,
        Unlocked
    }

    // TODO every value is necessary?
    enum IncomingBidStatus {
        None,
        Relayed,
        Challenged,
        Malicious
    }

    struct OutgoingBid {
        uint256 id;
        OutgoingBidStatus status;
        uint256 fee;
        address maker;
        address receiver;
        uint256 tokenId;
        address erc721Contract; // FIXME better name
        uint256 timestampOfBought;
        address buyer;
    }

    struct IncomingBid {
        uint256 remoteId;
        uint256 outgoingId; // FIXME it is not relevant on the  dst side
        IncomingBidStatus status;
        address receiver;
        uint256 tokenId;
        address erc721Contract; // FIXME better name
        uint256 timestampOfRelayed; // FIXME better name
        address relayer;
    }

    // TODO every value is necessary?
    enum RelayerStatus {
        None,
        Active,
        Undeposited,
        Challenged,
        Malicious
    }

    struct Relayer {
        RelayerStatus status;
        uint dateOfUndeposited;
        // TODO use versioning chain for managing bridge interactions
        uint256 stakedAmount;
    }

    // TODO every value is necessary?
    /**
     * @dev Status of a challenge:
     *      0 - no challenge
     *      1 - challenge is in progress
     *      2 - challenge was correct/
     */
    enum ChallengeStatus {
        None,
        Challenged,
        Proved
    }

    struct Challenge {
        address challenger;
        ChallengeStatus status;
    }

    mapping(address => Relayer) public relayers;

    mapping(uint256 => IncomingBid) public incomingBids;
    mapping(uint256 => OutgoingBid) public outgoingBids;

    mapping(uint256 => Challenge) public challengedIncomingBids;

    uint256 public immutable STAKE_AMOUNT;

    uint256 public immutable CHALLENGE_AMOUNT;

    uint256 public immutable TIME_LIMIT_OF_UNDEPOSIT;

    Counters.Counter public id;

    address public immutable HUB;

    constructor(address _hub) {
        HUB = _hub;
        STAKE_AMOUNT = 20 ether;
        CHALLENGE_AMOUNT = 10 ether;
        TIME_LIMIT_OF_UNDEPOSIT = 2 days;
    }

    modifier onlyActiveRelayer() {
        require(RelayerStatus.Active == relayers[_msgSender()].status, "SpokeBridge: caller is not a relayer!");
        _;
    }

    modifier onlyUndepositedRelayer() {
        require(RelayerStatus.Undeposited == relayers[_msgSender()].status,
            "SpokeBridge: caller is not in undeposited state!");
        _;
    }

    modifier onlyHub() {
        require(_getCrossMessageSender() == HUB, "SpokeBridge: caller is not the hub!");
        _;
    }

    function buyBid(uint256 _bidId) public virtual override onlyActiveRelayer() {
        require(outgoingBids[_bidId].status == OutgoingBidStatus.Created,
            "SpokeBridge: bid does not have Created state");
        outgoingBids[_bidId].status = OutgoingBidStatus.Bought;
        outgoingBids[_bidId].buyer = _msgSender();
        outgoingBids[_bidId].timestampOfBought = block.timestamp;
    }

    function deposite() public override payable {
        require(RelayerStatus.None == relayers[_msgSender()].status, "SpokeBridge: caller cannot be a relayer!");
        require(msg.value == STAKE_AMOUNT, "SpokeBridge: msg.value is not appropriate!");

        relayers[_msgSender()].status = RelayerStatus.Active;
        relayers[_msgSender()].stakedAmount = msg.value;
    }

    function undeposite() public override onlyActiveRelayer {
        relayers[_msgSender()].status = RelayerStatus.Undeposited;
        relayers[_msgSender()].dateOfUndeposited = block.timestamp;
    }

    function claimDeposite() public override onlyUndepositedRelayer {
        require(block.timestamp > relayers[_msgSender()].dateOfUndeposited + TIME_LIMIT_OF_UNDEPOSIT,
            "SpokeBridge: 2 days is not expired from the undepositing!");

        (bool isSent,) = _msgSender().call{value: STAKE_AMOUNT}("");
        require(isSent, "Failed to send Ether");

        relayers[_msgSender()].status = RelayerStatus.None;
    }

    function _sendMessage(bytes memory _data) internal virtual;

    function _getCrossMessageSender() internal virtual returns (address);

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}