// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {OurToken} from "../src/OurToken.sol";
import {DeployOurToken} from "../script/DeployOurToken.s.sol";

contract OurTokenTest is Test {
    OurToken public ourToken;
    DeployOurToken public deployer;

    address Bob = makeAddr("Bob");
    address Alice = makeAddr("Alice");

    uint256 public constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployOurToken();
        ourToken = deployer.run();

        vm.prank(msg.sender);
        ourToken.transfer(Bob, STARTING_BALANCE);
    }

    function testBobBalance() public {
        assertEq(STARTING_BALANCE, ourToken.balanceOf(Bob));
    }

    function testAllowancesWorks() public {
        // (!) transferFrom

        uint256 initialAllowance = 1000;

        // Bob approves Alice to spend tokens on her behalf

        vm.prank(Bob);
        // check approve-Fn @ ERC20.sol
        ourToken.approve(Alice, initialAllowance);

        uint256 transferAmount = 500;

        vm.prank(Alice);
        ourToken.transferFrom(Bob, Alice, transferAmount);

        //        ourToken.transfer(Alice, transferAmount);
        // who calls transfer, gets automatically set as the _from address

        assertEq(ourToken.balanceOf(Alice), transferAmount);
        assertEq(ourToken.balanceOf(Bob), STARTING_BALANCE - transferAmount);
    }
}
