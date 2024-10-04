//SPDX-License-Identifier:UNLICENSED
pragma solidity ^0.8.19;

import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { AutomationCompatibleInterface } from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Bookie Lottery Contract
 * @author Shivang Rawat
 * @notice This contract manages lottery rounds on the Bookie platform. Users can join rounds by purchasing up to 10
 * tickets each. The more tickets purchased, the higher the chances of winning.
 * @notice This contract uses `ChainlinkVRF` to generate randomness and the winner is chosen by the randomly generated
 * number
 * @notice This Whole contract will be handeled by Chainlink Automation to keep the process automated
 * @dev Implements the Chainlink VRF Version 2 for random number generation.
 */
contract Bookie is VRFConsumerBaseV2Plus, Pausable, AutomationCompatibleInterface, ReentrancyGuard {
    /////////////////////
    // Errors
    /////////////////////
    error Chainlink__RequestNotFound();
    error Bookie_ParticipationLimitReached();
    error Bookie_InsufficientEther();
    error Bookie_LotteryEnded();
    error Bookie_LotteryNotEnded();
    error Bookie_InvalidTicketAmount();
    error Bookie__NotAthorizedToUpdate();

    /////////////////////
    // TYPES
    /////////////////////
    // Bookie Type Declarations
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

    struct TicketStruct {
        uint256 id;
        address account;
    }

    /////////////////////
    // state variables
    /////////////////////

    // bookie variables
    uint256 private s_totalLotteries;
    uint256 private s_totalTickets;
    uint256 private s_randNumber;
    LotteryStruct private s_currentLottery;
    BookieStruct private s_bookieInfo;
    // Service percentage that goes to the owner
    uint256 private constant SERVICE_PCT = 5;
    mapping(uint256 => TicketStruct[]) lotteryTickets;

    // chainlink VRF variables
    // Your subscription ID.
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_keyhash;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;

    /////////////////////
    // Events
    /////////////////////

    // Bookie Events
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
    event WinnerPicked(uint256 indexed lotteryId, address winner);
    event PrizePaid(uint256 indexed lotteryId, address winner, uint256 amount);
    event LotteryEnded(
        LotteryStatus status,
        uint256 indexed id,
        uint256 prize,
        uint256 ticketPrice,
        uint256 participants,
        address winner,
        uint256 expiresAt
    );
    event LotteryCancelled(
        LotteryStatus status,
        uint256 indexed id,
        uint256 prize,
        uint256 ticketPrice,
        uint256 participants,
        address winner,
        uint256 expiresAt
    );

    // Chainlink VRF events
    // Random number
    event RequestSent(uint256 indexed requestId);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    /////////////////////
    // Modifiers
    /////////////////////
    modifier onlyowner() {
        if (msg.sender != s_bookieInfo.owner) {
            revert Bookie__NotAthorizedToUpdate();
        }
        _;
    }

    /////////////////////
    // functions
    /////////////////////

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinatorV2,
        bytes32 keyhash,
        uint32 callbackGasLimit,
        uint256 subscriptionId,
        uint256 maxParticipants
    )
        VRFConsumerBaseV2Plus(vrfCoordinatorV2)
    {
        i_keyhash = keyhash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_bookieInfo = BookieStruct({
            ticketPrice: entranceFee,
            maxParticipants: maxParticipants,
            duration: interval,
            totalAmount: 0,
            owner: msg.sender
        });
        s_totalLotteries=0;
    }

    /////////////////////
    // External Functions
    /////////////////////

    /*
    * @dev This Function Creates a new Lottery
    * @dev Checks If the current lottery has ended and reverts if not ended
    * calls Internal _createLottery() Function for lottery Creation
    */
    function createLottery() public {
        if (s_currentLottery.status == LotteryStatus.Open) {
            revert Bookie_LotteryNotEnded();
        }
        _createLottery();
        emit LotteryCreated(
            s_currentLottery.status,
            s_currentLottery.id,
            s_currentLottery.prize,
            s_currentLottery.ticketPrice,
            s_currentLottery.participants,
            s_currentLottery.winner,
            s_currentLottery.expiresAt
        );
    }

    /*
    * @dev User can buy ticket using this function 
    * @params total: total amount of tickets user want's to buy
    * if the betamount is less than ticketPrice then the function will revert
    * if the lottery has ended then you cannot enter
    * if the maxParticipant has reached then you cannot enter, calls the internal _buyTicket Function and emits
    ticketBought event
    */
    function buyTicket(uint256 total) external payable nonReentrant {
        if (msg.value < s_currentLottery.ticketPrice) {
            revert Bookie_InsufficientEther();
        }
        if (currentTime() > s_currentLottery.expiresAt) {
            revert Bookie_LotteryEnded();
        }
        if (s_currentLottery.participants >= s_bookieInfo.maxParticipants) {
            revert Bookie_ParticipationLimitReached();
        }
        if (msg.value / s_currentLottery.ticketPrice != total) {
            revert Bookie_InvalidTicketAmount();
        }
        _buyTicket(total);
        emit TicketBought(s_currentLottery.id, msg.sender, msg.value);
    }

    /*
    * @dev This is a public function, it can be called from outside the contract and from the performUpkeep function 
    * if the current time is greater than LotteryExpire time then the function will revert with
    Bookie__LotteryNotEnded() error
    * if the lottery participants are 0 or 1 then the lottery get cancelled by calling the _cancelLottery function
    * the function calls the requestRandomWords function that calls the chainlinkVRF for random number generation.
    */
    function pickWinner() public {
        if (s_currentLottery.expiresAt >= currentTime()) {
            revert Bookie_LotteryNotEnded();
        }
        if (s_currentLottery.participants <= 1) {
            _cancelLottery();
            return;
        }
        requestRandomWords();
    }

    /*
    * @dev This is an external function that is called by the chainlinkVRF to check if performUpkeep should be called or
    not
    * if the lottery is open, cancelled or ended then the performUpkeep is called
    * returns upkeepNeeded(bool) and performData(bytes)  
    * @param takes calldata for low level function calling which will be empty for this protocol.
    */
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = currentTime() > s_currentLottery.expiresAt
            && (
                s_currentLottery.status == LotteryStatus.Open || s_currentLottery.status == LotteryStatus.Cancelled
                    || s_currentLottery.status == LotteryStatus.Ended
            );

        return (upkeepNeeded, "");
    }

    /*
    * @dev This is an external function that is called by the chainlinkVRF if the checkUpkeep returns (true, '').
    * if the lottery status is open then pickWinner() function is called
    * if lottery status is closed or cancelled then new lottery is created by calling createLottery()
    * @param takes calldata for low level function calling which will be empty for this protocol.
    */
    function performUpkeep(bytes calldata) external override {
        if (currentTime() > s_currentLottery.expiresAt) {
            if (s_currentLottery.status == LotteryStatus.Open) {
                pickWinner();
            } else if (
                s_currentLottery.status == LotteryStatus.Cancelled || s_currentLottery.status == LotteryStatus.Ended
            ) {
                createLottery();
            }
        }
    }

    /*
    * @dev This is a public function which is called by the pickWinner function for requesting randomNumber from the
    chainlinkVRF.
    * emits requestSent() event for randomNumber generation
    */
    function requestRandomWords() public {
        // Will revert if subscription is not set and funded.
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyhash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATION,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false }))
            })
        );
        emit RequestSent(requestId);
    }

    ///////////////////////////////////////
    // Private Functions
    //////////////////////////////////////

    /*
    * @dev this function is an internal function 
    * creates a new lottery
     */
    function _createLottery() internal {
        s_totalLotteries++;
        s_currentLottery = LotteryStruct({
            status: LotteryStatus.Open,
            id: s_totalLotteries,
            prize: 0,
            ticketPrice: s_bookieInfo.ticketPrice,
            participants: 0,
            totalTickets: 0,
            winner: address(0),
            owner: msg.sender,
            expiresAt: block.timestamp + s_bookieInfo.duration
        });

        s_totalTickets = 0;
    }

    /*
    * @dev this function is an internal function 
    * @params total -> number of tickets user want to purchase
    * buys total tickets for the user
     */
    function _buyTicket(uint256 total) internal {
        s_currentLottery.participants += 1;
        s_currentLottery.prize += msg.value;

        for (uint256 i = 0; i < total; i++) {
            lotteryTickets[s_currentLottery.id].push(TicketStruct(s_totalTickets, msg.sender));
            s_totalTickets++;
        }
        s_currentLottery.totalTickets += total;
        s_bookieInfo.totalAmount += msg.value;
    }

    /*
    * @dev this function is an internal function 
    * picks winner by getting the randomNumber from the chainlinkVRF and mods it by total number of tickets in the
    lottery, the result of the calculation is the winner and _payLotteryWinner() function is called
     */
    function _pickWinner() internal {
        s_currentLottery.status = LotteryStatus.Drawing;
        uint256 value = s_currentLottery.totalTickets;
        uint256 winnerTicketId = s_randNumber % value;
        address winner = lotteryTickets[s_currentLottery.id][winnerTicketId].account;
        s_currentLottery.winner = winner;

        s_currentLottery.status = LotteryStatus.Drawn;
        emit WinnerPicked(s_currentLottery.id, winner);
        _payLotteryWinner();
    }

    /*
    * @dev this function is an internal function 
    * Cancel the existing open lottery, if the number of tickets in the lottery is less than 1 then lotteryCancelled
    event is emitted and if the number of tickets are greater than or equal to 1 then the total Lottery Amount is given
    to the only present player.
    * to pay the participants _payCancelledLottery internal function is called
     */
    function _cancelLottery() internal {
        s_currentLottery.status = LotteryStatus.Cancelled;
        if (s_currentLottery.totalTickets > 0) {
            s_currentLottery.winner = lotteryTickets[s_currentLottery.id][0].account;
            _payCancelledLottery();
        }
        emit LotteryCancelled(
            s_currentLottery.status,
            s_currentLottery.id,
            s_currentLottery.prize,
            s_currentLottery.ticketPrice,
            s_currentLottery.participants,
            s_currentLottery.winner,
            s_currentLottery.expiresAt
        );
    }

    /*
    * @dev this function is an internal function 
    * calls the internal _payTo function for transferring funds from the protocol to the winner
     */
    function _payCancelledLottery() internal {
        uint256 prize = s_currentLottery.prize;
        address winner = s_currentLottery.winner;
        _payTo(winner, prize);
    }

    /*
    * @dev this function is an internal function 
    * this function transferes the winning amount - 5% of total amount to the winner and the remaining 5% is transfered
    to the owner of the lottery
     */
    function _payLotteryWinner() internal {
        address winner = s_currentLottery.winner;
        address owner = s_bookieInfo.owner;

        uint256 totalShares = s_currentLottery.prize;
        uint256 platformShare = (totalShares * SERVICE_PCT) / 100;
        uint256 netShare = totalShares - platformShare;

        _payTo(winner, netShare);
        _payTo(owner, platformShare);

        s_currentLottery.status = LotteryStatus.Ended;
        emit PrizePaid(s_currentLottery.id, winner, netShare);
        emit LotteryEnded(
            s_currentLottery.status,
            s_currentLottery.id,
            s_currentLottery.prize,
            s_currentLottery.ticketPrice,
            s_currentLottery.participants,
            s_currentLottery.winner,
            s_currentLottery.expiresAt
        );
    }

    /*
    * @dev this function is an internal function 
    * pays the Winner their winning amount from the protocol
     */
    function _payTo(address to, uint256 amount) internal {
        (bool success,) = payable(to).call{ value: amount }("");
        require(success);
    }

    /*
    * @dev this function is an internal function 
    * This function is called by the chainlinkVRF to return the random words generated by the VRF.
    * calls the internal _pickWinner function where winner is picked on the basis of randomly generated number
     */

    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        s_randNumber = _randomWords[0];
        emit RequestFulfilled(_requestId, _randomWords);
        _pickWinner();
    }

    ///////////////////////////////////////
    // External View Functions
    //////////////////////////////////////

    /*
    * @dev returns total number of lotteries
     */

    function getTotalLotteries() external view returns (uint256) {
        return s_totalLotteries;
    }
    /*
    * @dev returns total number of tickets in a lottery
     */

    function getTotalTickets() external view returns (TicketStruct[] memory) {
        return lotteryTickets[s_totalLotteries];
    }
    /*
    * @dev returns the current status of the lottery
     */

    function getLotteryStatus() external view returns (LotteryStatus) {
        return s_currentLottery.status;
    }

    /*
    * @dev returns the winner of the lottery
     */
    function getLotteryWinner() external view returns (address) {
        return s_currentLottery.winner;
    }

    /*
    * @dev returns the current lottery's prize
     */
    function getLotteryPrize() external view returns (uint256) {
        return s_currentLottery.prize;
    }

    /*
    * @dev returns the minimum ticket price to enter lottery
     */
    function getLotteryTicketPrice() external view returns (uint256) {
        return s_currentLottery.ticketPrice;
    }
    /*
    * @dev returns the owner of the protocol
     */

    function getLotteryOwner() external view returns (address) {
        return s_currentLottery.owner;
    }
    /*
    * @dev returns the expiry time of the current lottery
     */

    function getLotteryExpiringTime() external view returns (uint256) {
        return s_currentLottery.expiresAt;
    }
    /*
    * @dev returns total number of participants in the current lottery
     */

    function getLotteryParticipants() external view returns (uint256) {
        return s_currentLottery.participants;
    }
    /*
    * @dev returns total number of tickets in the current lottery
     */

    function getLotteryTickets() external view returns (uint256) {
        return s_currentLottery.totalTickets;
    }

    /*
    * @dev returns the keyhash for the protocol
     */
    function getKeyHash() external view returns (bytes32) {
        return i_keyhash;
    }
    /*
    * @dev returns the chainlink subId of the protocol
     */

    function getSubscriptionId() external view returns (uint256) {
        return i_subscriptionId;
    }

    /*
    * @dev returns the callBackGasLimit for chainlinkVRF
     */
    function getCallBackGasLimit() external view returns (uint32) {
        return i_callbackGasLimit;
    }
    /*
    * @dev returns the randomNumber
     */

    function getRandomNumber() external view returns (uint256) {
        return s_randNumber;
    }
    /*
    * @dev returns the duration of the lottery round
     */

    function getBookieDuration() external view returns (uint256) {
        return s_bookieInfo.duration;
    }
    /*
    * @dev returns the max participants allowed in a lottery
     */

    function getBookieMaxParticipants() external view returns (uint256) {
        return s_bookieInfo.maxParticipants;
    }
    /*
    * @dev returns the ticket price of the protocol
     */

    function getBookieTicketPrice() external view returns (uint256) {
        return s_bookieInfo.ticketPrice;
    }
    /*
    * @dev returns the owner of the protocol
     */

    function getBookieOwner() external view returns (address) {
        return s_bookieInfo.owner;
    }
    /*
    * @dev returns the total volume of the protocol
     */

    function getBookieTotalAmount() external view returns (uint256) {
        return s_bookieInfo.totalAmount;
    }
    /*
    * @dev returns the service percentage of the protocol
     */

    function getServicePercentage() external pure returns (uint256) {
        return SERVICE_PCT;
    }
    /*
    * @dev returns the number of request confirmation
     */

    function getRequestConfirmation() external pure returns (uint16) {
        return REQUEST_CONFIRMATION;
    }
    /*
    * @dev returns the number of words returned by the chainlinkVRF
     */

    function getNumberOfWords() external pure returns (uint32) {
        return NUM_WORDS;
    }
    /*
    * @dev returns the lottery data
     */

    function getLottery() external view returns (LotteryStruct memory lotteryData) {
        lotteryData = s_currentLottery;
    }
    /*
    * @dev returns the bookie data
     */

    function getBookieData() external view returns (BookieStruct memory bookieData) {
        bookieData = s_bookieInfo;
    }
    /*
    * @dev returns the current time of the block
     */

    function currentTime() public view returns (uint256) {
        return block.timestamp;
    }

    ///////////////////////////////////////
    // Update Functions Functions
    //////////////////////////////////////

    /*
    * @dev updates the round duration of the lottery, only the protocol owner can change update.
     */
    function updateLotteryDuration(uint256 newDuration) external onlyowner {
        s_bookieInfo.duration = newDuration;
    }
    /*
    * @dev updates the max participants in the lottery, only the protocol owner can change update.
     */

    function updateLotteryMaxParticipants(uint256 newMaxParticipants) external onlyowner {
        s_bookieInfo.maxParticipants = newMaxParticipants;
    }
    /*
    * @dev updates the ticket price of the lottery, only the protocol owner can change update.
     */

    function updateLotteryTicketPrice(uint256 newLotteryPrice) external onlyowner {
        s_bookieInfo.ticketPrice = newLotteryPrice;
    }

    /*
    * @dev pauses the chainlink automation, only protocol owner can call
     */
    function pause() external onlyowner {
        _pause();
    }
    /*
    * @dev unpauses the chainlink automation, only protocol owner can call
     */

    function unpause() external onlyowner {
        _unpause();
    }
}
