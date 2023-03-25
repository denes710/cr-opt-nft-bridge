// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IHub} from "../interfaces/IHub.sol";

import {SrcSpokeBridge} from "../SrcSpokeBridge.sol";

contract BlackHoleSrcSpokeBrdige is SrcSpokeBridge {
    constructor(
        address _contractMap,
        address _hub,
        uint256 _transferPerBlock,
        uint256 _transFee
    ) SrcSpokeBridge(_contractMap, _hub, _transferPerBlock, _transFee) {
    }

    function _sendMessage(bytes memory _data) internal override {
        IHub(HUB).processMessage(_data);
    }

    function _getCrossMessageSender() internal override returns (address) {
        return  HUB;
    }
}