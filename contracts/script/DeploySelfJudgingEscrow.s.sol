// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {SelfJudgingEscrow} from "../examples/SelfJudgingEscrow.sol";

contract DeploySelfJudgingEscrow is Script {
    function run() external {
        address verifier = 0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1;

        vm.startBroadcast();
        SelfJudgingEscrow escrow = new SelfJudgingEscrow(verifier);
        vm.stopBroadcast();

        console.log("SelfJudgingEscrow deployed at:", address(escrow));
    }
}
