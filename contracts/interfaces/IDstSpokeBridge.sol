pragma solidity >=0.4.22 <0.9.0;

import {ISpokeBridge} from "./ISpokeBridge.sol";

interface IDstSpokeBridge is ISpokeBridge {
    function createBid(
        address _receiver,
        uint256 _tokenId,
        address _erc721Contract,
        uint256 _incomingBidId
    ) external payable;

    function challengeMinting(uint256 _bidId) external payable;

    function minting(uint256 _bidId, address _to, uint256 _tokenId, address erc721Contract) external;
}