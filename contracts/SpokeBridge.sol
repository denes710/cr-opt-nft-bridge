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

    struct LocalBlock {
        LocalTransaction[] transactions;
    }

    enum IncomingBlockStatus {
        None,
        Relayed,
        Challenged,
        Malicious
    }

    struct IncomingBlock {
        bytes32 transactionRoot;
        uint256 timestampOfIncoming;
        IncomingBlockStatus status;
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
        uint256 dateOfUndeposited;
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

    mapping(uint256 => IncomingBlock) public incomingBlocks;
    mapping(uint256 => LocalBlock) internal localBlocks;

    mapping(uint256 => Challenge) public challengedIncomingBlocks;

    mapping(uint256 => Reward) public incomingChallengeRewards;

    uint256 public immutable STAKE_AMOUNT;

    uint256 public immutable CHALLENGE_AMOUNT;

    uint256 public immutable TIME_LIMIT_OF_UNDEPOSIT;

    uint256 public immutable TRANS_PER_BLOCK;

    uint256 public immutable TRANS_FEE;

    Counters.Counter public localBlockId;
    Counters.Counter public incomingBlockId;

    address public immutable HUB;

    constructor(address _hub) {
        HUB = _hub;
        STAKE_AMOUNT = 20 ether;
        CHALLENGE_AMOUNT = 10 ether;
        TIME_LIMIT_OF_UNDEPOSIT = 2 days;
        TRANS_PER_BLOCK = 16;
        TRANS_FEE = 0.01 ether;
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

    function sendProof(uint256 _height) public override {
        // we can send calculated merkle proof about localBlocks
        bytes32 calculatedRoot = _height < localBlockId.current() ?
            bytes32(0) : _getMerkleRoot(localBlocks[_height].transactions);
        bytes memory data = abi.encode(_height, calculatedRoot);
        _sendMessage(data);
    }

    function receiveProof(bytes memory _root) public override onlyHub {
        (uint32 height, bytes32 calculatedRoot) = abi.decode(_root, (uint32, bytes32));

        IncomingBlock memory incomingBlock = incomingBlocks[height];

        if (incomingBlock.status == IncomingBlockStatus.None) {
            return;
        }

        if (incomingBlock.transactionRoot == calculatedRoot) {
            // False challenging
            incomingBlock.status = IncomingBlockStatus.Relayed;
            relayers[incomingBlock.relayer].status = RelayerStatus.Active;
            challengedIncomingBlocks[height].status = ChallengeStatus.None;
        } else {
            // TODO versioning, after malicious behav
            // Proved malicious bid(behavior)
            incomingBlock.status = IncomingBlockStatus.Malicious;
            relayers[incomingBlock.relayer].status = RelayerStatus.Malicious;

            // Dealing with the challenger
            if (challengedIncomingBlocks[height].status == ChallengeStatus.Challenged) {
                incomingChallengeRewards[height].challenger = challengedIncomingBlocks[height].challenger;
                incomingChallengeRewards[height].amount = CHALLENGE_AMOUNT + STAKE_AMOUNT / 4;
            }
            challengedIncomingBlocks[height].status = ChallengeStatus.Proved;
        }
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

    function claimChallengeReward(uint256 _challengeId) public override {
        require(!incomingChallengeRewards[_challengeId].isClaimed, "SpokeBridge: reward is already claimed!");
        require(incomingChallengeRewards[_challengeId].challenger == _msgSender(),
            "SpokeBridge: challenger is not the sender!");

        incomingChallengeRewards[_challengeId].isClaimed = true;

        (bool isSent,) = _msgSender().call{value: incomingChallengeRewards[_challengeId].amount}("");
        require(isSent, "Failed to send Ether");
    }

    function addIncomingBlock(bytes32 _transactionRoot) public override onlyActiveRelayer {
        incomingBlocks[incomingBlockId.current()] = IncomingBlock({
            transactionRoot:_transactionRoot,
            timestampOfIncoming:block.timestamp,
            status:IncomingBlockStatus.Relayed,
            relayer:_msgSender()
        });

        incomingBlockId.increment();
    }

    function challengeIncomingBlock(uint256 _height) public override payable {
        require(msg.value == CHALLENGE_AMOUNT, "SpokeBridge: No enough amount of ETH to stake!");
        require(incomingBlocks[_height].status == IncomingBlockStatus.Relayed, "SpokeBridge: Corresponding incoming bid status is not relayed!");
        require(incomingBlocks[_height].timestampOfIncoming + 4 hours > block.timestamp, "SpokeBridge: The dispute period is expired!");
        require(challengedIncomingBlocks[_height].status == ChallengeStatus.None, "SpokeBridge: bid is already challenged!");

        incomingBlocks[_height].status = IncomingBlockStatus.Challenged;

        challengedIncomingBlocks[_height].challenger = _msgSender();
        challengedIncomingBlocks[_height].status = ChallengeStatus.Challenged;

        relayers[incomingBlocks[_height].relayer].status = RelayerStatus.Challenged;
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _sendMessage(bytes memory _data) internal virtual;

    function _getCrossMessageSender() internal virtual returns (address);

    function _getMerkleRoot(LocalTransaction[] memory _transactions) internal view returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](_transactions.length);

        uint32 idx = 0;
        for (uint i = 0; i < _transactions.length; i++) {
            hashes[idx++] = keccak256(abi.encode(
                _transactions[i].tokenId,
                _transactions[i].maker,
                _transactions[i].receiver,
                _transactions[i].localErc721Contract,
                _transactions[i].remoteErc721Contract
            ));
        }

        uint n = _transactions.length;
        uint offset = 0;

        while (n > 0) {
            for (uint i = 0; i < n - 1; i += 2) {
                hashes[idx++] = keccak256(abi.encodePacked(hashes[offset + i], hashes[offset + i + 1]));
            }
            offset += n;
            n = n / 2;
        }

        return hashes[hashes.length - 1];
    }

    function _verifyMerkleProof(
        bytes32[] calldata _proof,
        bytes32 _root,
        LocalTransaction calldata _transaction,
        uint _index
    ) internal view returns (bool) {
        bytes32 hash = keccak256(abi.encode(
                _transaction.tokenId,
                _transaction.maker,
                _transaction.receiver,
                _transaction.localErc721Contract,
                _transaction.remoteErc721Contract
            ));

        for (uint i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, proofElement));
            } else {
                hash = keccak256(abi.encodePacked(proofElement, hash));
            }

            _index = _index / 2;
        }

        return hash == _root;
    }
}