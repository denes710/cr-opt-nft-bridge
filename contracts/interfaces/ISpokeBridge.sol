// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// FIXME comments
/**
 * @notice This interface will send and receive messages through.
 */
interface ISpokeBridge is IERC721Receiver {
    // TODO define the parameters of the BID
    event BidCreated();

    event BidBought(address relayer, uint256 bidId);

    event BidChallenged(address challenger, address relayer, uint256 bidId);

    // TODO define the parameters of the proof
    event ProofSent();

    event NFTUnwrapped(address contractAddress, uint256 bidId, uint256 id, address owner);

    function buyBid(uint256 _bidId) external;

    function sendProof(bool _isOutgoingBid, uint256 _bidId) external;

    function receiveProof(bytes memory _proof) external;

    function deposite() external payable;

    function undeposite() external;

    function claimDeposite() external;
}