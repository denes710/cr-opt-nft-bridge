// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {LibBid} from "../libraries/LibBid.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @notice This interface will send and receive messages.
 */
interface ISpokeBridge is IERC721Receiver {
    // TODO defines and uses these events
    event BidCreated();

    event BidBought(address relayer, uint256 bidId);

    event BidChallenged(address challenger, address relayer, uint256 bidId);

    event ProofSent();

    event NFTUnwrapped(address contractAddress, uint256 bidId, uint256 id, address owner);

    function buyBid(uint256 _bidId) external;

    function addIncomingBid(uint256 _bidId, bytes32 _hashedTransaction, LibBid.Transaction calldata _transaction) external;

    function challengeIncomingBid(uint256 _bidId) external payable;

    function sendProof(bool _isOutgoingBid, uint256 _bidId) external;

    function receiveProof(bytes memory _proof) external;

    function deposite() external payable;

    function undeposite() external;

    function claimDeposite() external;

    function claimChallengeReward(uint256 _challengeId, bool _isOutgoingBid) external;
}