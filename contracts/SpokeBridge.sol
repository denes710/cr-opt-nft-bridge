// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./interfaces/ISpokeBridge.sol";

import {LibBid} from "./libraries/LibBid.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This abstract contract is the common base class for src and dst bridges.
 * The src and dst bridges have lots of common functionalities.
 */
abstract contract SpokeBridge is ISpokeBridge, Ownable {
    using Counters for Counters.Counter;
    using LibBid for LibBid.Transaction;

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
        uint256 timestampOfBought;
        uint256 fee;
        address relayer;
        bytes32 hashedTransaction;
    }

    struct IncomingBid {
        IncomingBidStatus status;
        uint256 timestampOfRelayed;
        address relayer;
        bytes32 hashedTransaction;
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
        outgoingBids[_bidId].relayer = _msgSender();
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

    // FIXME restore function
    function challengeIncomingBid(uint256 _bidId) public payable override {
        require(msg.value == CHALLENGE_AMOUNT, "SpokeBridge: No enough amount of ETH to stake!");
        require(incomingBids[_bidId].status == IncomingBidStatus.Relayed, "SpokeBridge: Corresponding incoming bid status is not relayed!");
        require(incomingBids[_bidId].timestampOfRelayed + 4 hours > block.timestamp, "SpokeBridge: The dispute period is expired!");
        require(challengedIncomingBids[_bidId].status == ChallengeStatus.None, "SpokeBridge: bid is already challenged!");

        incomingBids[_bidId].status = IncomingBidStatus.Challenged;

        challengedIncomingBids[_bidId].challenger = _msgSender();
        challengedIncomingBids[_bidId].status = ChallengeStatus.Challenged;

        relayers[incomingBids[_bidId].relayer].status = RelayerStatus.Challenged;
    }

    function receiveProof(bytes memory _proof) public override onlyHub {
        (bytes memory bidBytes, bool isBidOutgoing) = abi.decode(_proof, (bytes, bool));
        if (isBidOutgoing) {
            // On the source chain during unlocking(wrong relaying), revert the incoming messsage
            (
                uint256 bidId,
                bytes32 hashedTransaction,
                address relayer,
                OutgoingBidStatus status
            ) = abi.decode(bidBytes, (uint256, bytes32, address, OutgoingBidStatus));

            IncomingBid memory localChallengedBid = incomingBids[bidId];

            require(localChallengedBid.status != IncomingBidStatus.None, "SpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfRelayed + 4 hours > block.timestamp, "SpokeBridge: Time window is expired!");

            if (incomingBids[bidId].hashedTransaction == hashedTransaction &&
                incomingBids[bidId].relayer == relayer) {
                // False challenging
                localChallengedBid.status = IncomingBidStatus.Relayed;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Active;
                challengedIncomingBids[bidId].status = ChallengeStatus.None;
            } else {
                // Proved malicious bid(behavior)
                localChallengedBid.status = IncomingBidStatus.Malicious;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Malicious;

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
                bytes32 hashedTransaction,
                address relayer,
                IncomingBidStatus status,
                address challenger
            ) = abi.decode(bidBytes, (uint256, bytes32, address, IncomingBidStatus, address));

            OutgoingBid memory localChallengedBid = outgoingBids[bidId];

            require(localChallengedBid.status != OutgoingBidStatus.None, "SpokeBrdige: There is no corresponding local bid!");
            require(localChallengedBid.timestampOfBought + 4 hours < block.timestamp, "SpokeBridge: Time window is not expired!");

            if (localChallengedBid.hashedTransaction == hashedTransaction &&
                localChallengedBid.relayer == relayer) {
                // False challenging
                require(false, "SpokeBridge: False challenging!");

            } else {
                // Proved malicious bid - no relaying
                localChallengedBid.status = OutgoingBidStatus.Malicious;
                relayers[localChallengedBid.relayer].status = RelayerStatus.Malicious;

                outgoingChallengeRewards[bidId].challenger = challenger;
                outgoingChallengeRewards[bidId].amount = STAKE_AMOUNT / 4;

                challengedIncomingBids[bidId].status = ChallengeStatus.Proved;
            }
        }
    }

    function sendProof(bool _isOutgoingBid, uint256 _bidId) public override {
        if (_isOutgoingBid) {
            OutgoingBid memory bid = outgoingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.hashedTransaction,
                bid.relayer,
                bid.status
            );

            data = abi.encode(data, true);

            _sendMessage(data);
        } else {
            require(incomingBids[_bidId].timestampOfRelayed + 4 hours < block.timestamp,
                "SpokeBridge: too early to send proof!");

            IncomingBid memory bid = incomingBids[_bidId];
            bytes memory data = abi.encode(
                _bidId,
                bid.hashedTransaction,
                bid.relayer,
                bid.status,
                _msgSender()
            );

            data = abi.encode(data, false);

            _sendMessage(data);
        }
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getTransactionHash(LibBid.Transaction calldata _transaction) public view returns(bytes32) {
        return keccak256(abi.encode(_transaction.tokenId, _transaction.owner, _transaction.receiver, _transaction.localErc721Contract, _transaction.remoteErc721Contract));
    }

    function _sendMessage(bytes memory _data) internal virtual;

    function _getCrossMessageSender() internal virtual returns (address);
}