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

    // FIXME outgoing and incoming bid are different a little bit on dst and src sides
    enum OutgoingBidStatus {
        None,
        Created,
        Bought,
        Challenged,
        Malicious,
        Unlocked // it is used only on src
    }

    enum IncomingBidStatus {
        None,
        Relayed,
        Challenged,
        Malicious,
        Unlocked // it is used only on src
    }

    struct OutgoingBid {
        OutgoingBidStatus status;
        uint256 fee;
        // the original owner
        address maker;
        // the new owner
        address receiver;
        uint256 tokenId;
        address localErc721Contract;
        address remoteErc721Contract; // it is not relevant on the dst side
        uint256 timestampOfBought;
        // the relayer
        address buyer;
    }

    struct IncomingBid {
        uint256 outgoingId; // it is not relevant on the dst side
        IncomingBidStatus status;
        address receiver;
        uint256 tokenId;
        // it is always an address on the dst chain
        address remoteErc721Contract; // it is not relevant on the src side
        uint256 timestampOfRelayed;
        address relayer;
    }

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

    struct Reward {
        address challenger;
        uint256 amount;
        bool isClaimed;
    }

    mapping(address => Relayer) public relayers;

    mapping(uint256 => IncomingBid) public incomingBids;
    mapping(uint256 => OutgoingBid) public outgoingBids;

    mapping(uint256 => Challenge) public challengedIncomingBids;

    mapping(uint256 => Reward) public incomingChallengeRewards;
    mapping(uint256 => Reward) public outgoingChallengeRewards;

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

        (bool isSent,) = _msgSender().call{value: outgoingBids[_bidId].fee}("");
        require(isSent, "Failed to send Ether");
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

    function claimChallengeReward(uint256 _challengeId, bool _isOutgoingBid) public override {
        if (_isOutgoingBid) {
            require(!outgoingChallengeRewards[_challengeId].isClaimed, "SpokeBridge: reward is already claimed!");
            require(outgoingChallengeRewards[_challengeId].challenger == _msgSender(),
                "SpokeBridge: challenger is not the sender!");

            outgoingChallengeRewards[_challengeId].isClaimed = true;

            (bool isSent,) = _msgSender().call{value: outgoingChallengeRewards[_challengeId].amount}("");
            require(isSent, "Failed to send Ether");
        } else {
            require(!incomingChallengeRewards[_challengeId].isClaimed, "SpokeBridge: reward is already claimed!");
            require(incomingChallengeRewards[_challengeId].challenger == _msgSender(),
                "SpokeBridge: challenger is not the sender!");

            incomingChallengeRewards[_challengeId].isClaimed = true;
            
            (bool isSent,) = _msgSender().call{value: incomingChallengeRewards[_challengeId].amount}("");
            require(isSent, "Failed to send Ether");
        }
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _sendMessage(bytes memory _data) internal virtual;

    function _getCrossMessageSender() internal virtual returns (address);

    function _challengeUnlocking(uint256 _bidId) internal {
        require(msg.value == CHALLENGE_AMOUNT, "SpokeBridge: No enough amount of ETH to stake!");
        require(incomingBids[_bidId].status == IncomingBidStatus.Relayed, "SpokeBridge: Corresponding incoming bid status is not relayed!");
        require(incomingBids[_bidId].timestampOfRelayed + 4 hours > block.timestamp, "SpokeBridge: The dispute period is expired!");
        require(challengedIncomingBids[_bidId].status == ChallengeStatus.None, "SpokeBridge: bid is already challenged!");

        incomingBids[_bidId].status = IncomingBidStatus.Challenged;

        challengedIncomingBids[_bidId].challenger = _msgSender();
        challengedIncomingBids[_bidId].status = ChallengeStatus.Challenged;

        relayers[incomingBids[_bidId].relayer].status = RelayerStatus.Challenged;
    }
}