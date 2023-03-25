// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

library LibBid {
    struct Transaction {
        uint256 tokenId;
        address owner;
        address receiver;
        address localErc721Contract;
        address remoteErc721Contract;
    }
}