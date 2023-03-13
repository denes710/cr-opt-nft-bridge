// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// FIXME comments
/**
 * @notice This interface wrappes the original IERC721interface.
 */
interface IWrappedERC721 is IERC721 {
    function burn(uint256 _id) external;

    function mint(address _to, uint256 _id) external;
}