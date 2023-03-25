// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./ISpokeBridge.sol";

import {LibBid} from "../libraries/LibBid.sol";

interface ISrcSpokeBridge is ISpokeBridge {
    function createBid(address _receiver, uint256 _tokenId, address _erc721Contract) external payable;

    function claimNFT(uint256 _incomingBidId, LibBid.Transaction calldata _transaction) external;
}