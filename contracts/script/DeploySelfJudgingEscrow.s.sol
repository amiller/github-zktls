// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {SelfJudgingEscrow} from "../examples/SelfJudgingEscrow.sol";

contract DeploySelfJudgingEscrow is Script {
    function run() external {
        address verifier = 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725;

        vm.startBroadcast();
        SelfJudgingEscrow escrow = new SelfJudgingEscrow(verifier);
        vm.stopBroadcast();

        console.log("SelfJudgingEscrow deployed at:", address(escrow));
    }
}
