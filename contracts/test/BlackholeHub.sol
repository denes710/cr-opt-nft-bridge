// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import {IHub} from "../interfaces/IHub.sol";
import {ISpokeBridge} from "../interfaces/ISpokeBridge.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BlackholeHub is IHub, Ownable {
    mapping(address => address) public bridgeToBrdige;

    event ProcessMessageData(bytes _data);

    function processMessage(bytes memory _data) public override {
        emit ProcessMessageData(_data);
        emit MessageSent(_msgSender(), address(0));
    }

    function addSpokeBridge(address _srcContract, address _dstContract) public override onlyOwner {
        require(bridgeToBrdige[_srcContract] == address(0), "Hub: src contract already has a pair!");
        require(bridgeToBrdige[_dstContract] == address(0), "Hub: dst contract already has a pair!");

        bridgeToBrdige[_srcContract] = _dstContract;
        bridgeToBrdige[_dstContract] = _srcContract;
    }
}