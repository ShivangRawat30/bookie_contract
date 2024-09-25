// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { DeployBookie } from "../../script/DeployBookie.s.sol";
import { Bookie } from "../../src/Bookie.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Vm } from "forge-std/Vm.sol";
import { VRFCoordinatorV2_5Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract BookieFuzzTest is Test {
    event TicketBought(uint256 indexed lotteryId, address buyer, uint256 amount);

    address public FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address admin = makeAddr("admin");
    uint256 public constant startingBalance = uint256(type(uint96).max);
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    Bookie public bookie;
    HelperConfig public helperConfig;

    function setUp() external {
        DeployBookie deployer = new DeployBookie();
        (bookie, helperConfig) = deployer.deployContract();
    }

    modifier createLottery() {
        vm.prank(admin);
        bookie.createLottery();
        _;
    }

    function testLotteryEnteredOnlyWithValidTicketAmount(
        address player,
        uint256 entryAmount,
        uint256 totalTickets
    )
        public
        createLottery
    {
        vm.deal(player, startingBalance);
        entryAmount = bound(entryAmount, 0.01 ether, uint256(MAX_DEPOSIT_SIZE));
        if (totalTickets == 0) {
            return;
        }
        uint256 check = entryAmount / totalTickets;
        if (check == 0.01 ether) {
            vm.expectEmit(true, false, false, false, address(bookie));
            emit TicketBought(totalTickets, address(player), entryAmount);
        } else {
            vm.prank(player);
            vm.expectRevert(Bookie.Bookie_InvalidTicketAmount.selector);
        }
        bookie.buyTicket{ value: entryAmount }(totalTickets);
    }

    function testLotteryDataCannotBeUpdated(address player) public {
        vm.deal(player, startingBalance);
        vm.expectRevert(Bookie.Bookie__NotAthorizedToUpdate.selector);
        bookie.updateLotteryDuration(3434);
    }
}
