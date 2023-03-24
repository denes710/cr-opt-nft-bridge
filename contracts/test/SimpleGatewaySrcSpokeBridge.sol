// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IHub} from "../interfaces/IHub.sol";

import {MerkleProofHelper} from "./MerkleProofHelper.sol";

import {SrcSpokeBridge} from "../SrcSpokeBridge.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {LibLocalTransaction} from "./../libraries/LibLocalTransaction.sol";

contract SimpleGatewaySrcSpokeBrdige is SrcSpokeBridge, MerkleProofHelper {
    using LibLocalTransaction for LibLocalTransaction.LocalBlock;
    using Counters for Counters.Counter;

    constructor(
        address _contractMap,
        address _hub,
        uint256 _transferPerBlock,
        uint256 _transFee
    ) SrcSpokeBridge(_contractMap, _hub, _transferPerBlock, _transFee) {
    }

    function calculateTransactionHashes(uint256 blockId) public {
        bytes32[] memory input = new bytes32[](localBlocks[blockId].length.current());
        for (uint i = 0; i < localBlocks[blockId].length.current(); i++) {
            input[i] = localBlocks[blockId].transactions[i];
        }

        super.calculateHashes(input);    }

    function _sendMessage(bytes memory _data) internal override {
        IHub(HUB).processMessage(_data);
    }

    function _getCrossMessageSender() internal override returns (address) {
        return _msgSender();
    }
}