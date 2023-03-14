// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./ISpokeBridge.sol";

interface ISrcSpokeBridge is ISpokeBridge {
    function createBid(address _receiver, uint256 _tokenId, address _erc721Contract) external payable;

    function challengeUnlocking(uint256 _bidId) external payable;

    function unlocking(uint256 _lockingBidId, uint256 _bidId, address _to) external;

    function claimNFT(uint256 _bidId) external;
}