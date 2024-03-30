// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MoodNFT} from "../../src/MoodNFT.sol";
import {DeployMoodNFT} from "../../script/DeployMoodNFT.s.sol";

contract DeployMoodNFTTest is Test {
    DeployMoodNFT public deployer;

    function setUp() public {
        deployer = new DeployMoodNFT();
    }

    function testConvertSvgToURI() public view {
        string
            memory expectedURI = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1MDAiIGhlaWdodD0iNTAwIj4gPHRleHQgeD0iMCIgeT0iMTUiIGZpbGw9ImJsYWNrIj4gSGkhIFlvdXIgYnJvd3NlciBkZWNvZGVkIHRoaXMgPC90ZXh0PiA8L3N2Zz4=";
        string
            memory svg = '<svg xmlns="http://www.w3.org/2000/svg" width="500" height="500"> <text x="0" y="15" fill="black"> Hi! Your browser decoded this </text> </svg>';
        string memory actualURI = deployer.svgToImageURI(svg);
        assert(
            keccak256(abi.encodePacked(actualURI)) ==
                keccak256(abi.encodePacked(expectedURI))
        );
    }
}
