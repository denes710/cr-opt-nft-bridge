// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {LibLocalTransaction} from "../libraries/LibLocalTransaction.sol";

contract MerkleProofHelper  {
    bytes32[] public hashes;

    function calculateHashes(LibLocalTransaction.LocalTransaction[] memory _transactions) public {
        delete hashes;
        for (uint i = 0; i < _transactions.length; i++) {
            hashes.push(keccak256(abi.encode(
                _transactions[i].tokenId,
                _transactions[i].maker,
                _transactions[i].receiver,
                _transactions[i].localErc721Contract,
                _transactions[i].remoteErc721Contract
            )));
        }

        uint n = _transactions.length;
        uint offset = 0;

        while (n > 0) {
            for (uint i = 0; i < n - 1; i += 2) {
                hashes.push(keccak256(abi.encodePacked(hashes[offset + i], hashes[offset + i + 1])));
            }
            offset += n;
            n = n / 2;
        }
    }

    function getRoot() public view returns (bytes32) {
        return hashes[hashes.length - 1];
    }
}