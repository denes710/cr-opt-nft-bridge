// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

/**
 * @notice This interface sends and receives messages from the spoke bridge contracts.
 */
interface IHub {
    event MessageSent(address _srcContract, address _dstContract);

    event SpokeBridgePairAdded(address _srcContract, address _dstContract);

    function processMessage(bytes memory _data) external;

    function addSpokeBridge(address _srcContract, address _dstContract) external;
}