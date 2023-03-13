// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

// FIXME comments
/**
 * @notice This interface sends and receives messages from the spoke contracts.
 */
interface IHub {
    function processMessage(bytes memory _data) external;

    function addSpokeBridge(address _srcContract, address _dstContract) external;
}