// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import {TimelockController} from "@openzeppelin@v4.8.3/contracts/governance/TimelockController.sol";

contract TimeLock is TimelockController {
    //minDelay is how long to wait before executing
    //proposers list of addresses who can propose
    //executors ""                        execute
    //admin
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors)
        TimelockController(minDelay, proposers, executors, msg.sender)
    {}
}
