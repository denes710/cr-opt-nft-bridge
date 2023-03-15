// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

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

    function sendProof(uint256 _height) external;

    function receiveProof(bytes memory _root) external;

    function deposite() external payable;

    function undeposite() external;

    function claimDeposite() external;

    function claimChallengeReward(uint256 _challengeId) external;

    function addNewTransactionToBlock(address _receiver, uint256 _tokenId, address _erc721Contract) external;

    function addIncomingBlock(uint256 _height, uint32 _transactionRoot) external;

    function challengeIncomingBlock(uint256 _height) external payable;

    function claimNFT(uint256 _height) external payable;
}