// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./interfaces/ISpokeBridge.sol";

import {LibLocalTransaction} from "./libraries/LibLocalTransaction.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @notice This abstract contract is the common base class for src and dst bridges.
 * The src and dst bridges have lots of common functionalities.
 */
abstract contract SpokeBridge is ISpokeBridge, Ownable {
    using Counters for Counters.Counter;
    using LibLocalTransaction for LibLocalTransaction.LocalTransaction;

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
        Counters.Counter againstChallenges;
    }

    /**
     * @dev Status of a challenge:
     *      0 - no challenge
     *      1 - challenge is in progress
     *      2 - challenge was correct
     */
    enum ChallengeStatus {
        None,
        Challenged,
        Proved,
        Malicious
    }

    struct Challenge {
        address challenger;
        ChallengeStatus status;
    }

    struct Reward {
        uint256 amount;
        bool isClaimed;
    }

    enum BridgeStatus {
        Active,
        Challenged,
        Paused
    }

    BridgeStatus public status;

    mapping(address => Relayer) public relayers;

    // local block
    mapping(uint256 => LibLocalTransaction.LocalBlock) internal localBlocks;
    Counters.Counter public localBlockId;

    // incoming block
    mapping(uint256 => IncomingBlock) public incomingBlocks;
    uint256 incomingBlockId;

    // challenge
    mapping(uint256 => Challenge) public challengedIncomingBlocks;
    mapping(address => Reward) public incomingChallengeRewards;
    Counters.Counter public numberOfChallenges;
    uint256 public firstMaliciousBlockHeight;

    // constant
    uint256 public immutable STAKE_AMOUNT;

    uint256 public immutable CHALLENGE_AMOUNT;

    uint256 public immutable TIME_LIMIT_OF_UNDEPOSIT;

    uint256 public immutable TRANS_PER_BLOCK;

    uint256 public immutable TRANS_FEE;

    address public immutable HUB;

    constructor(address _hub, uint256 _transferPerBlock, uint256 _transFee) {
        HUB = _hub;
        STAKE_AMOUNT = 20 ether;
        CHALLENGE_AMOUNT = 10 ether;
        TIME_LIMIT_OF_UNDEPOSIT = 2 days;
        TRANS_PER_BLOCK = _transferPerBlock;
        TRANS_FEE = _transFee;
    }

    modifier onlyInActiveStatus() {
        require(status == BridgeStatus.Active, "SpokeBridge: bridge is not active!");
        _;
    }

    modifier onlyInChallengedStatus() {
        require(status == BridgeStatus.Challenged, "SpokeBridge: bridge is not challenged!");
        _;
    }

    modifier onlyInPausedStatus() {
        require(status == BridgeStatus.Paused, "SpokeBridge: bridge is not paused!");
        _;
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
        // we can send a calculated merkle proof about localBlocks, it is always a trusted event
        bytes32 calculatedRoot = _height > localBlockId.current() ?
            bytes32(0) : _getMerkleRoot(_height);
        bytes memory data = abi.encode(_height, calculatedRoot);
        _sendMessage(data);
        emit ProofSent(_height);
    }

    function receiveProof(bytes memory _root) public override onlyHub {
        require(status != BridgeStatus.Active, "SpokeBridge: bride status is active!");

        (uint32 height, bytes32 calculatedRoot) = abi.decode(_root, (uint32, bytes32));

        IncomingBlock storage incomingBlock = incomingBlocks[height];

        require(incomingBlock.status == IncomingBlockStatus.Challenged,
            "SpokeBridge: incoming block has no challenged status!");

        if (incomingBlock.transactionRoot == calculatedRoot) {
            // False challenging
            incomingBlock.status = IncomingBlockStatus.Relayed;

            relayers[incomingBlock.relayer].againstChallenges.decrement();

            if (relayers[incomingBlock.relayer].againstChallenges.current() == 0 &&
                relayers[incomingBlock.relayer].status == RelayerStatus.Challenged) {
                // there is no more challenge against the relayer
                // nobody found that this relayer is malicious
                relayers[incomingBlock.relayer].status = RelayerStatus.Active;
            }

            challengedIncomingBlocks[height].status = ChallengeStatus.None;

            numberOfChallenges.decrement();
            if (numberOfChallenges.current() == 0 && status == BridgeStatus.Challenged) {
                // this is the last challenge in progress
                // nobody found malicious action
                status = BridgeStatus.Active;
            }

            emit ProofReceived(height, false);
        } else {
            // True challenging, proved malicious action
            incomingBlock.status = IncomingBlockStatus.Malicious;

            relayers[incomingBlock.relayer].againstChallenges.decrement();
            relayers[incomingBlock.relayer].status = RelayerStatus.Malicious;

            if (status == BridgeStatus.Challenged || firstMaliciousBlockHeight > height) {
                // This is the first proved malicious block during this dispute period
                // Or the current height is smaller than previos one
                firstMaliciousBlockHeight = height;
            }

            numberOfChallenges.decrement();
            status = BridgeStatus.Paused;

            // Dealing with the challenger
            if (challengedIncomingBlocks[height].status == ChallengeStatus.Challenged) {
                incomingChallengeRewards[challengedIncomingBlocks[height].challenger].amount += CHALLENGE_AMOUNT + STAKE_AMOUNT / 4;
                incomingChallengeRewards[_msgSender()].isClaimed = false;
            }
            challengedIncomingBlocks[height].status = ChallengeStatus.Proved;

            emit ProofReceived(height, true);
        }
    }

    function deposite() public override payable onlyInActiveStatus {
        require(RelayerStatus.None == relayers[_msgSender()].status, "SpokeBridge: caller cannot be a relayer!");
        require(msg.value == STAKE_AMOUNT, "SpokeBridge: msg.value is not appropriate!");

        relayers[_msgSender()].status = RelayerStatus.Active;
        relayers[_msgSender()].stakedAmount = msg.value;
    }

    function undeposite() public override onlyInActiveStatus onlyActiveRelayer {
        relayers[_msgSender()].status = RelayerStatus.Undeposited;
        relayers[_msgSender()].dateOfUndeposited = block.timestamp;
    }

    function claimDeposite() public override onlyInActiveStatus onlyUndepositedRelayer {
        require(block.timestamp > relayers[_msgSender()].dateOfUndeposited + TIME_LIMIT_OF_UNDEPOSIT,
            "SpokeBridge: 2 days is not expired from the undepositing!");

        (bool isSent,) = _msgSender().call{value: STAKE_AMOUNT}("");
        require(isSent, "Failed to send Ether");

        relayers[_msgSender()].status = RelayerStatus.None;
    }

    function claimChallengeReward() public override onlyInActiveStatus {
        require(incomingChallengeRewards[_msgSender()].amount != 0, "SpokeBridge: there is no reward!");
        require(!incomingChallengeRewards[_msgSender()].isClaimed, "SpokeBridge: reward is already claimed!");

        incomingChallengeRewards[_msgSender()].isClaimed = true;

        (bool isSent,) = _msgSender().call{value: incomingChallengeRewards[_msgSender()].amount}("");
        require(isSent, "Failed to send Ether");

        incomingChallengeRewards[_msgSender()].amount = 0;
    }

    function addIncomingBlock(bytes32 _transactionRoot) public override onlyInActiveStatus onlyActiveRelayer {
        incomingBlocks[incomingBlockId] = IncomingBlock({
            transactionRoot:_transactionRoot,
            timestampOfIncoming:block.timestamp,
            status:IncomingBlockStatus.Relayed,
            relayer:_msgSender()
        });

        incomingBlockId++;

        emit IncomingBlockAdded(_transactionRoot, incomingBlockId - 1);
    }

    function challengeIncomingBlock(uint256 _height) public override payable {
        require(msg.value == CHALLENGE_AMOUNT, "SpokeBridge: No enough amount of ETH to stake!");
        require(incomingBlocks[_height].status == IncomingBlockStatus.Relayed,
            "SpokeBridge: Corresponding incoming bid status is not relayed!");
        require(incomingBlocks[_height].timestampOfIncoming + 4 hours > block.timestamp,
            "SpokeBridge: The dispute period is expired!");
        require(challengedIncomingBlocks[_height].status == ChallengeStatus.None,
            "SpokeBridge: bid is already challenged!");

        require(status != BridgeStatus.Paused, "SpokeBridge: the status of the bridge is paused!");

        status = BridgeStatus.Challenged;
        numberOfChallenges.increment();

        incomingBlocks[_height].status = IncomingBlockStatus.Challenged;

        challengedIncomingBlocks[_height].challenger = _msgSender();
        challengedIncomingBlocks[_height].status = ChallengeStatus.Challenged;

        relayers[incomingBlocks[_height].relayer].againstChallenges.increment();
        relayers[incomingBlocks[_height].relayer].status = RelayerStatus.Challenged;

        emit IncomingBlockChallenged(incomingBlocks[_height].transactionRoot, _height);
    }

    function restore() public override onlyInPausedStatus {
        status = BridgeStatus.Active;

        for (uint i = firstMaliciousBlockHeight; i < incomingBlockId; i++) {
            incomingBlocks[i].status = IncomingBlockStatus.None;
            challengedIncomingBlocks[i].status = ChallengeStatus.None;
        }

        // set the next incoming block id
        incomingBlockId = firstMaliciousBlockHeight;

        firstMaliciousBlockHeight = 0;
        emit Restored(incomingBlockId);
    }

    function getLocalTransaction(
        uint256 _blockNum,
        uint256 _txIdx
    ) public view override returns (bytes32) {
        return localBlocks[_blockNum].transactions[_txIdx];
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _sendMessage(bytes memory _data) internal virtual;

    function _getCrossMessageSender() internal virtual returns (address);

    function _getMerkleRoot(uint256 _height) internal view returns (bytes32) {
        uint size = localBlocks[_height].length.current();

        bytes32[] memory hashes = new bytes32[](size * 2 - 1);

        uint32 idx = 0;
        for (uint i = 0; i < size; i++) {
            hashes[idx++] = localBlocks[_height].transactions[i];
        }

        uint offset = 0;

        while (size > 0) {
            for (uint i = 0; i < size - 1; i += 2) {
                hashes[idx++] = keccak256(abi.encodePacked(hashes[offset + i], hashes[offset + i + 1]));
            }
            offset += size;
            size = size / 2;
        }

        return hashes[hashes.length - 1];
    }

    function _verifyMerkleProof(
        bytes32[] calldata _proof,
        bytes32 _root,
        LibLocalTransaction.LocalTransaction calldata _transaction,
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