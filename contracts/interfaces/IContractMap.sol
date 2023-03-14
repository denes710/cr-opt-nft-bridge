// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

/**
 * @notice This interface stores the pairs of the ERC721 smart contracts.
 */
interface IContractMap {
    event PairAdded(address indexed _local, address indexed _remote);

    function addPair(address _local, address _remote) external;

    function getRemote(address _local) external view returns (address);

    function getLocal(address _remote) external view returns (address);
}