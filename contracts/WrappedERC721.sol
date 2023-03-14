// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IWrappedERC721} from "./interfaces/IWrappedERC721.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract WrappedERC721 is IWrappedERC721, ERC721, Ownable {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
    }

    function burn(uint256 _id) public override onlyOwner {
        super._burn(_id);
    }

    function mint(address _to, uint256 _id) public override onlyOwner {
        super._safeMint(_to, _id);
    }
}