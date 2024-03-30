// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PlayerContract {
    mapping(uint256 => address) public players;

    uint256 private playersCounter = 0;

    function addPlayer(address _player) public {
        players[playersCounter + 1] = address(_player);
        playersCounter++;
    }

    function pickWinner() internal returns (address) /** onlyOwner */ {
        // pick random winner using Chainlink VRF:
        // pick a random number from 1 to playersCounter value.
        // when getting the number, look for it in the 'players' Mapping
        // and retrieve that address as the winner.
    }

    // mapping(address => uint8) players;

    // function addPlayer(address _player) public {
    //     players[_player] = uint8(playersCounter + 1);
    //     playersCounter++;
    // }
}
