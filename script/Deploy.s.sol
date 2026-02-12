// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ArbitratorRegistry.sol";
import "../src/EscrowFactory.sol";
import "../src/MockERC20.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ArbitratorRegistry
        ArbitratorRegistry registry = new ArbitratorRegistry();
        console.log("ArbitratorRegistry deployed at:", address(registry));

        // 2. Deploy EscrowFactory
        address feeRecipient = deployer; // Can be changed to another address
        EscrowFactory factory = new EscrowFactory(address(registry), feeRecipient);
        console.log("EscrowFactory deployed at:", address(factory));

        // 3. Deploy test tokens (optional, for testing)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        console.log("MockUSDC deployed at:", address(usdc));

        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI");
        console.log("MockDAI deployed at:", address(dai));

        // 4. Add token support to factory
        factory.setSupportedToken(address(usdc), true);
        factory.setSupportedToken(address(dai), true);
        console.log("Tokens added to factory");

        // 5. Register a default arbitrator (deployer for testing)
        registry.registerArbitrator(deployer, 0.01 ether);
        console.log("Default arbitrator registered:", deployer);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("ArbitratorRegistry:", address(registry));
        console.log("EscrowFactory:", address(factory));
        console.log("MockUSDC:", address(usdc));
        console.log("MockDAI:", address(dai));
        console.log("Fee Recipient:", feeRecipient);
    }
}
