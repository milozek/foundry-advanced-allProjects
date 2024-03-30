# Proveably Random Raffle Contracts

## About

This code is to create a proveably random smart contract lottery

## What do we want it to do?

1. Users can enter by paying for a ticket
   1. The ticket fees are going to go to the winner during the draw
2. After X period of time, the lottery will automatically draw a winner
   1. And this will be done programatically
3. Using Chainlink VRF & Automation
   1. VRF -->> True Proveably Random Number
   2. Automation -->> Time based trigger

## Tests

1. Write some deploy scripts
2. Write our tests
   1. Work on a local chain
   2. Forked Testnet
   3. Forked Mainnet
