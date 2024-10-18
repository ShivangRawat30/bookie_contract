// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

import {LinkToken} from "../test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    uint96 public MOCK_BASE_FEE = 0.25 ether;
    uint96 public MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public MOCK_WEI_PER_UINT_LINK = 4e15;

    address public FOUNDRY_DEFAULT_SENDER =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31_337;
    uint256 public constant POLYGON_AMOY_CHAIN_ID = 80002;
    uint256 public constant ETH_MAINNET_SUB_ID = 123;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID=84532;
    address public constant ETH_MAINNET_OWNER_ADDRESS =
        0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        uint256 maxParticipants;
        address link;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public NetworkConfigs;

    constructor() {
        NetworkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (NetworkConfigs[chainId].vrfCoordinator != address(0)) {
            return NetworkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else if (chainId == ETH_MAINNET_CHAIN_ID) {
            return getMainnetEthConfig();
        } else if (chainId == 421614) {
            return getArbitrumSepoliaEthConfig();
        } else if (chainId == POLYGON_AMOY_CHAIN_ID) {
            return polygonAmoyEthConfig();
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID) {
            return baseEthSepoliaConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.0001 ether,
                interval: 90,
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                callbackGasLimit: 500_000,
                subscriptionId: 50403786783274423409479727342572505524335105714553623620124116320640762388221,
                maxParticipants: 50,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD
            });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 90,
                vrfCoordinator: 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a,
                gasLane: 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9,
                callbackGasLimit: 500_000,
                subscriptionId: ETH_MAINNET_SUB_ID,
                maxParticipants: 50,
                link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
                account: ETH_MAINNET_OWNER_ADDRESS
            });
    }

    function getArbitrumSepoliaEthConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                entranceFee: 0.0001 ether,
                interval: 90,
                vrfCoordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
                gasLane: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
                callbackGasLimit: 500_000,
                subscriptionId: 97065945864523932416872234574061829422692607522339856463816641732357797262562,
                maxParticipants: 50,
                link: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
                account: 0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD
            });
    }

    function getBaseEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 90,
                vrfCoordinator: 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634,
                gasLane: 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70,
                callbackGasLimit: 500_000,
                subscriptionId: 97065945864523932416872234574061829422692607522339856463816641732357797262562,
                maxParticipants: 50,
                link: 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196,
                account: 0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD
            });
    }
    function baseEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.0001 ether,
                interval: 90,
                vrfCoordinator: 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE,
                gasLane: 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71,
                callbackGasLimit: 500_000,
                subscriptionId: 113866341413133120501472414556975558037792139443655784040944270740488363671397,
                maxParticipants: 50,
                link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
                account: 0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD
            });
    }

    function polygonAmoyEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.0001 ether,
                interval: 90,
                vrfCoordinator: 0x343300b5d84D444B2ADc9116FEF1bED02BE49Cf2,
                gasLane: 0x816bedba8a50b294e5cbd47842baf240c2385f2eaf719edbd4f250a137a8c899,
                callbackGasLimit: 500_000,
                subscriptionId: 30073239641045514329915089901240090403256806217956307207494724294794091331010,
                maxParticipants: 50,
                link: 0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904,
                account: 0x13a1C8eC74cb67AD1b828AAcC326a0031b5147cD
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        // Deploy mocks and such
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE_LINK,
            MOCK_WEI_PER_UINT_LINK
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 90,
            vrfCoordinator: address(vrfCoordinatorMock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500_000,
            subscriptionId: 0,
            maxParticipants: 50,
            link: address(linkToken),
            account: FOUNDRY_DEFAULT_SENDER
        });
        return localNetworkConfig;
    }
}
