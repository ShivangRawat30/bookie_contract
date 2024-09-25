// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Bookie } from "../src/Bookie.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { CreateSubscription, FundSubscription, AddCounsumer } from "../script/interactions.s.sol";

contract DeployBookie is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Bookie, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator, config.account);

            // Fund Subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        vm.startBroadcast(config.account);
        Bookie bookie = new Bookie(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.callbackGasLimit,
            config.subscriptionId,
            config.maxParticipants
        );

        vm.stopBroadcast();
        AddCounsumer addConsumer = new AddCounsumer();

        addConsumer.addConsumer(address(bookie), config.vrfCoordinator, config.subscriptionId, config.account);
        return (bookie, helperConfig);
    }
}
