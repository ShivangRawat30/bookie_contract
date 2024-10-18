// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { DeployBookie } from "../../script/DeployBookie.s.sol";
import { Bookie } from "../../src/Bookie.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Vm } from "forge-std/Vm.sol";
import { VRFCoordinatorV2_5Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract BookieTest is Test {
    event LotteryCreated(
        LotteryStatus status,
        uint256 indexed id,
        uint256 prize,
        uint256 ticketPrice,
        uint256 participants,
        address winner,
        uint256 expiresAt
    );
    event TicketBought(uint256 indexed lotteryId, address buyer, uint256 amount);
    event LotteryCancelled(
        LotteryStatus status,
        uint256 indexed id,
        uint256 prize,
        uint256 ticketPrice,
        uint256 participants,
        address winner,
        uint256 expiresAt
    );
    event RequestSent(uint256 indexed requestId);
    event WinnerPicked(uint256 indexed lotteryId, address winner);
    event PrizePaid(uint256 indexed lotteryId, address winner, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        uint256 maxParticipants;
    }

    enum LotteryStatus {
        None,
        Open,
        Drawing,
        Drawn,
        Cancelled,
        Ended
    }

    struct BookieStruct {
        uint256 ticketPrice;
        uint256 maxParticipants;
        uint256 duration;
        uint256 totalAmount;
        address owner;
    }

    struct LotteryStruct {
        LotteryStatus status;
        uint256 id;
        uint256 prize;
        uint256 ticketPrice;
        uint256 participants;
        uint256 totalTickets;
        address winner;
        address owner;
        uint256 expiresAt;
    }

    Bookie public bookie;
    HelperConfig public helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;
    uint256 maxParticipants;
    uint256 currentTime;

    address public player1 = makeAddr("player1");
    uint256 public constant startingBalance = 1 ether;
    address public FOUNDRY_DEFAULT_SENDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    address public admin = makeAddr("admin");
    address public player2 = makeAddr("player2");

    function setUp() external {
        DeployBookie deployer = new DeployBookie();
        (bookie, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        maxParticipants = config.maxParticipants;

        vm.deal(player1, startingBalance);
        vm.deal(player2, startingBalance);
        vm.deal(admin, startingBalance);
    }

    /////////////////////
    // Constructor Tests
    /////////////////////

    function testIfTheCunstructorDataIsCorrect() public view {
        assertEq(gasLane, bookie.getKeyHash());
        assertEq(callbackGasLimit, bookie.getCallBackGasLimit());
        assertEq(
            102_565_803_394_344_916_850_023_035_371_831_273_892_454_389_762_849_833_489_697_271_545_370_145_535_982,
            bookie.getSubscriptionId()
        );
    }

    function testBookieOwnerIsCorrect() public view {
        assertEq(bookie.getBookieOwner(), FOUNDRY_DEFAULT_SENDER);
    }

    function testOwnerEarningIsReturned() public view {
        assertEq(bookie.getOwnerEarning(), 0);
    }

    function testServicePercentageIsFive() public view {
        assertEq(bookie.getServicePercentage(), 5);
    }

    function testConfirmationRequest() public view {
        assertEq(bookie.getRequestConfirmation(), 3);
    }

    function testNumberOfWords() public view {
        assertEq(bookie.getNumberOfWords(), 1);
    }

    function testBookieInfo() public {
        assertEq(entranceFee, bookie.getBookieData().ticketPrice);
        assertEq(maxParticipants, bookie.getBookieData().maxParticipants);
        assertEq(interval, bookie.getBookieData().duration);
        assertEq(0, bookie.getBookieData().totalAmount);
        assertEq(address(FOUNDRY_DEFAULT_SENDER), bookie.getBookieData().owner);
    }

    ////////////////////////////
    // Lottery Creation Tests
    ////////////////////////////

    modifier createLottery() {
        currentTime = bookie.currentTime();
        vm.prank(admin);
        bookie.createLottery();
        _;
    }

    function testLotteryCreation() public createLottery {
        uint256 expectedLotteries = 1;
        uint256 totalLotteries = bookie.getTotalLotteries();

        assertEq(expectedLotteries, totalLotteries);
    }

    function testTheLotteryStatusIsOpen() public createLottery {
        //    LotteryStruct memory expectedLottery = LotteryStruct({
        //     status: LotteryStatus.Open,
        //     id: 1,
        //     prize: 0,
        //     ticketPrice: entranceFee,
        //     participants: 0,
        //     totalTickets: 0,
        //     winner: address(0),
        //     owner: address(admin),
        //     expiresAt: block.timestamp + interval
        //    });
        // LotteryStatus memory status = ;
        assertEq(abi.encodePacked(LotteryStatus.Open), abi.encodePacked(bookie.getLotteryStatus()));
        assertEq(1, bookie.getTotalLotteries());
        assertEq(0, bookie.getLotteryPrize());
        assertEq(entranceFee, bookie.getLotteryTicketPrice());
        assertEq(0, bookie.getLotteryParticipants());
        assertEq(0, bookie.getLotteryTickets());
        assertEq(address(0), bookie.getLotteryWinner());
        assertEq(address(admin), bookie.getLotteryOwner());
        assertEq(currentTime + interval, bookie.getLotteryExpiringTime());
        assertEq(0, bookie.getLottery().participants);
    }

    function testRevertCreateLotteryIfLotteryNotEnded() public createLottery {
        vm.prank(player1);
        vm.expectRevert(Bookie.Bookie_LotteryNotEnded.selector);
        bookie.createLottery();
    }

    function testLotteryCreatedEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit LotteryCreated(LotteryStatus.Open, 1, 0, entranceFee, 0, address(0), currentTime + interval);
        bookie.createLottery();
    }

    /////////////////////
    // Buy Ticket Tests
    /////////////////////

    function testLotteryRevertWhenBettingPriceIsLessThanTicketPrice() public createLottery {
        vm.prank(player1);
        vm.expectRevert(Bookie.Bookie_InsufficientEther.selector);
        bookie.buyTicket{ value: 0.001 ether }(1);
    }

    function testLotteryRevertWhenCurrentTimeExceedsExipyTime() public createLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.prank(player1);
        vm.expectRevert(Bookie.Bookie_LotteryEnded.selector);
        bookie.buyTicket{ value: 0.01 ether }(1);
    }

    function testLotteryRevertsWhenMaxParticipantsExceeds() public {
        NetworkConfig memory localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 90,
            vrfCoordinator: address(1),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500_000,
            subscriptionId: 97_767_009_708_314_305_665_643_641_779_529_925_837_712_974_602_641_641_141_825_456_487_478_243_071_475,
            maxParticipants: 1
        });
        vm.startBroadcast(admin);
        Bookie testbookie = new Bookie(
            localNetworkConfig.entranceFee,
            localNetworkConfig.interval,
            localNetworkConfig.vrfCoordinator,
            localNetworkConfig.gasLane,
            localNetworkConfig.callbackGasLimit,
            localNetworkConfig.subscriptionId,
            localNetworkConfig.maxParticipants
        );
        vm.stopBroadcast();

        vm.prank(admin);
        testbookie.createLottery();

        vm.prank(player1);
        testbookie.buyTicket{ value: 0.01 ether }(1);

        vm.prank(player2);
        vm.expectRevert(Bookie.Bookie_ParticipationLimitReached.selector);
        testbookie.buyTicket{ value: 0.01 ether }(1);
    }

    function testLotteryRevertWhenTheTicketAmountIsInvalid() public createLottery {
        vm.prank(player1);
        vm.expectRevert(Bookie.Bookie_InvalidTicketAmount.selector);
        bookie.buyTicket{ value: 0.1 ether }(1);
    }

    function testBuyTicketWorkingProperly() public createLottery {
        vm.prank(player1);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit TicketBought(1, address(player1), 0.01 ether);
        bookie.buyTicket{ value: 0.01 ether }(1);
    }

    ////////////////////////////////
    // Lottery Cancelaltion Tests
    ///////////////////////////////

    function testRevertPickWinnerWhenLotteryNotEnded() public createLottery {
        vm.prank(player1);
        vm.expectRevert(Bookie.Bookie_LotteryNotEnded.selector);
        bookie.pickWinner();
    }

    function testLotteryStatusCancelledWhenLessThanTwoPlayerInLottery() public createLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.prank(player1);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit LotteryCancelled(LotteryStatus.Cancelled, 1, 0, entranceFee, 0, address(0), currentTime + interval);
        bookie.pickWinner();
    }

    function testThePlayerIsPayedAfterLotteryCancellation() public createLottery {
        vm.prank(player1);
        uint256 expectedBalance = player1.balance;
        bookie.buyTicket{ value: 0.01 ether }(1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        bookie.pickWinner();
        uint256 finalBalance = player1.balance;
        assertEq(finalBalance, expectedBalance);
    }

    ////////////////////////////////
    // Pick Winner Tests
    ///////////////////////////////

    modifier createAndEnterLottery() {
        vm.prank(admin);
        bookie.createLottery();
        vm.prank(player1);
        bookie.buyTicket{ value: 0.01 ether }(1);
        vm.prank(player2);
        bookie.buyTicket{ value: 0.01 ether }(1);
        _;
    }

    function testLotteryTotalAmountIsUpdatedWhenPlayerEnter() public createAndEnterLottery {
        uint256 expectedAmount = 0.02 ether;
        assertEq(bookie.getBookieTotalAmount(), expectedAmount);
    }

    function testTotalTicketsAreUpdatedWhenPlayersEnter() public createAndEnterLottery {
        uint256 expectedAmount = 2;
        assertEq(bookie.getTotalTickets().length, expectedAmount);
    }

    // function testRandomNumberIsGenerated() public createAndEnterLottery {
    //     vm.warp(block.timestamp + interval + 1);
    //     vm.roll(block.number + 1);
    //     vm.prank(admin);
    //     bookie.pickWinner();
    //     vm.warp(block.timestamp + 50000);
    //     vm.roll(block.number + 1);
    //     uint256 randNumber = bookie.getRandomNumber();
    //     assertNotEq(0, randNumber);
    // }

    function testWinnerPickedEventIsEmitted() public createAndEnterLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit WinnerPicked(1, address(player1));
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));
    }

    // function testLotteryIsPayedToTheWinner() publi›c {
    //     uint256 balance = admin.balance;
    //     vm.prank(admin);
    //     bookie.createLottery();
    //     vm.prank(player1);
    //     bookie.buyTicket{value: 0.1 ether}(10);
    //     vm.prank(player2);
    //     bookie.buyTicket{value: 0.1 ether}(10);
    //     vm.warp(block.timestamp + interval + 1);
    //     vm.roll(block.number + 1);
    //     vm.prank(admin);
    //     bookie.pickWinner();

    //     uint256 totalRemainingAmount = admin.balance - balance;
    //     assertEq(totalRemainingAmount, 0.01 ether);
    // }

    function testWinnerIsPayedTheWinningAmount() public {
        vm.prank(admin);
        bookie.createLottery();
        uint256 amount = player2.balance;
        vm.prank(player1);
        bookie.buyTicket{ value: 0.01 ether }(1);
        vm.prank(player2);
        bookie.buyTicket{ value: 0.01 ether }(1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));

        uint256 finalAmount = player2.balance - amount;
        assertEq(finalAmount, 0.009 ether);
    }

    function testCheckUpKeepWhenLotteryHasEnded() public createAndEnterLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.prank(admin);
        bool upkeepNeeded = true;
        bytes memory performData = "";
        (bool result1, bytes memory result2) = bookie.checkUpkeep("");
        assertEq(upkeepNeeded, result1);
        assertEq(performData, result2);
    }

    function testCheckUpKeepWhenLotteryHasNotExpired() public createAndEnterLottery {
        vm.prank(admin);
        bool upkeepNeeded = false;
        bytes memory performData = "";
        (bool result1, bytes memory result2) = bookie.checkUpkeep("");
        assertEq(upkeepNeeded, result1);
        assertEq(performData, result2);
    }

    function testFulfillRandomWordsWhenLotteryStautsIsOpen() public createAndEnterLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        bookie.performUpkeep("");
        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit WinnerPicked(1, address(player1));
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));
    }

    function testPerformUpkeepCreatesLotteryWhenLotteryStatusIsEnded() public createAndEnterLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        bookie.performUpkeep("");
        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));

        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit LotteryCreated(LotteryStatus.Open, 2, 0, entranceFee, 0, address(0), currentTime + interval);
        bookie.performUpkeep("");
    }

    function testPerformUpkeepCreatesLotteryWhenLotteryStatusIsCancelled() public {
        vm.prank(admin);
        bookie.createLottery();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit LotteryCancelled(LotteryStatus.Cancelled, 1, 0, entranceFee, 0, address(0), currentTime + interval);
        bookie.performUpkeep("");
        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit LotteryCreated(LotteryStatus.Open, 2, 0, entranceFee, 0, address(0), currentTime + interval);
        bookie.performUpkeep("");
    }

    function testOnlyOwnerCanUpdateDuration() public {
        uint256 currentDuration = 90;
        uint256 duration = bookie.getBookieDuration();
        assertEq(currentDuration, duration);
        uint256 newDuration = 80;
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        bookie.updateLotteryDuration(newDuration);
        uint256 newLotteryDuration = bookie.getBookieDuration();
        assertEq(newDuration, newLotteryDuration);
    }

    function testRevertWhenDurationUpdatorIsNotOwner() public {
        vm.prank(admin);
        vm.expectRevert(Bookie.Bookie__NotAthorizedToUpdate.selector);
        bookie.updateLotteryDuration(80);
    }

    function testOnlyOwnerCanUpdateMaxParticipants() public {
        uint256 currentMaxParticipants = 50;
        uint256 maxParticipants = bookie.getBookieMaxParticipants();
        assertEq(currentMaxParticipants, maxParticipants);
        uint256 newMaxParticipants = 60;
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        bookie.updateLotteryMaxParticipants(newMaxParticipants);
        uint256 newSetMaxParticipants = bookie.getBookieMaxParticipants();
        assertEq(newMaxParticipants, newSetMaxParticipants);
    }

    function testRevertWhenMaxParticipantUpdatorIsNotOwner() public {
        vm.prank(admin);
        vm.expectRevert(Bookie.Bookie__NotAthorizedToUpdate.selector);
        bookie.updateLotteryMaxParticipants(77);
    }

    function testOnlyOwnerCanUpdateTicketPrice() public {
        uint256 ticketPrice = bookie.getBookieTicketPrice();
        assertEq(entranceFee, ticketPrice);
        uint256 newTicketPrice = 0.1 ether;
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        bookie.updateLotteryTicketPrice(newTicketPrice);
        uint256 newSetTicketPrice = bookie.getBookieTicketPrice();
        assertEq(newSetTicketPrice, newTicketPrice);
    }

    function testRevertWhenTicketPriceUpdatorIsNotOwner() public {
        vm.prank(admin);
        vm.expectRevert(Bookie.Bookie__NotAthorizedToUpdate.selector);
        bookie.updateLotteryTicketPrice(77);
    }

    function testCurrentTimeReturnsBlockTimestamp() public {
        assertEq(block.timestamp, bookie.currentTime());
    }

    function testLotteryWinnerIsUpdatedAfterTheLotteryIsFinished() public createAndEnterLottery {
        vm.prank(admin);
    }

    modifier skipFork() {
        if (block.chainid != 31_337) {
            return;
        }
        _;
    }

    function testPerformUpkeepEmitsRequestId() public createAndEnterLottery {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        assert(uint256(requestId) == 1);
    }

    function testFulfillRandomWordsGeneratesARandomNumber() public createAndEnterLottery skipFork {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));

        assertNotEq(uint256(0), bookie.getRandomNumber());
    }

    function testRequestRandomWordsEmitRequesSentEvent() public {
        vm.expectEmit(true, false, false, false, address(bookie));
        emit RequestSent(1);
        bookie.requestRandomWords();
    }

    function testPauseFunction() public {
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit Paused(address(FOUNDRY_DEFAULT_SENDER));
        bookie.pause();
    }

    function testUnpauseFunction() public {
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        bookie.pause();
        vm.prank(FOUNDRY_DEFAULT_SENDER);
        vm.expectEmit(true, false, false, false, address(bookie));
        emit Unpaused(address(FOUNDRY_DEFAULT_SENDER));
        bookie.unpause();
    }

    function testOwnerEarningIsIncreasedAfterEveryRound() public createAndEnterLottery {

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.recordLogs();
        bookie.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        vm.prank(admin);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(bookie));
        uint256 expectedAmount = (5 * 0.02 ether) / 100;
        uint256 actualAmount = bookie.getOwnerEarning();
        assertEq(expectedAmount, actualAmount);
    }
}
