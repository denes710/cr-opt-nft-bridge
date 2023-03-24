// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {LibLocalTransaction} from "../libraries/LibLocalTransaction.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @notice This interface will send and receive messages.
 */
interface ISpokeBridge is IERC721Receiver {
    event ProofSent(uint256 _height);

    event ProofReceived(uint256 _height, bool _isSuccessfulChallenge);

    // current block id which is not finalized
    event Restored(uint256 _currentBlockId);

    event NewTransactionAddedToBlock(
        uint256 _blockId,
        uint256 _TxId,
        uint256 _tokenId,
        address _maker,
        address _receiver,
        address _localERC721,
        address _remoteERC721
    );

    event NFTClaimed(uint256 _incomingBlockId, address _localERC721, address _receiver, uint256 _tokenId);

    event IncomingBlockAdded(bytes32 _transactionRoot, uint256 _blockId);

    event IncomingBlockChallenged(bytes32 _transactionRoot, uint256 _blockId);

    function sendProof(uint256 _height) external;

    function receiveProof(bytes memory _root) external;

    function deposite() external payable;

    function undeposite() external;

    function claimDeposite() external;

    function claimChallengeReward() external;

    function addIncomingBlock(bytes32 _transactionRoot) external;

    function challengeIncomingBlock(uint256 _height) external payable;

    function claimNFT(
        uint256 _incomingBlockId,
        LibLocalTransaction.LocalTransaction memory _transaction,
        bytes32[] memory _proof,
        uint _index
    ) external payable;

    function restore() external;

    function getLocalTransaction(uint256 _blockNum, uint256 _txIdx) external view returns (bytes32);
}