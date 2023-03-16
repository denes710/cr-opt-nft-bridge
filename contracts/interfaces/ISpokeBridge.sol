// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {LibLocalTransaction} from "../libraries/LibLocalTransaction.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @notice This interface will send and receive messages.
 */
interface ISpokeBridge is IERC721Receiver {
    // FIXME defines and uses these events
    event BidCreated();

    event BidBought(address relayer, uint256 bidId);

    event BidChallenged(address challenger, address relayer, uint256 bidId);

    event ProofSent();

    event NFTUnwrapped(address contractAddress, uint256 bidId, uint256 id, address owner);

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

    function getLocalTransaction(uint256 _blockNum, uint256 _txIdx) external view returns (LibLocalTransaction.LocalTransaction memory);
}