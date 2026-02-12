// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ArbitratorRegistry.sol";
import "../src/EscrowFactory.sol";
import "../src/Escrow.sol";
import "../src/MockERC20.sol";

/**
 * @title InteractionScript
 * @notice Script for interacting with deployed contracts
 * @dev Use this to create escrows, accept deals, resolve disputes, etc.
 */
contract InteractionScript is Script {
    EscrowFactory factory;
    ArbitratorRegistry registry;
    MockERC20 token;

    function setUp() public {
        // Load deployed contract addresses from environment
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        factory = EscrowFactory(payable(factoryAddress));
        registry = ArbitratorRegistry(registryAddress);
        token = MockERC20(tokenAddress);
    }

    /**
     * @notice Create a new ETH escrow
     */
    function createETHEscrow() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address seller = vm.envAddress("SELLER_ADDRESS");

        vm.startBroadcast(privateKey);

        uint256 amount = 0.1 ether;
        uint256 deadline = block.timestamp + 7 days;

        address escrow = factory.createEscrow{value: amount}(
            seller,
            address(0), // ETH
            amount,
            deadline,
            "Build a website"
        );

        console.log("Escrow created at:", escrow);

        vm.stopBroadcast();
    }

    /**
     * @notice Create a new ERC20 escrow
     */
    function createTokenEscrow() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address seller = vm.envAddress("SELLER_ADDRESS");

        vm.startBroadcast(privateKey);

        uint256 amount = 100 * 10**18; // 100 tokens
        uint256 deadline = block.timestamp + 7 days;

        // Approve factory to spend tokens
        token.approve(address(factory), amount);

        address escrow = factory.createEscrow(
            seller,
            address(token),
            amount,
            deadline,
            "Design a logo"
        );

        console.log("Token escrow created at:", escrow);

        vm.stopBroadcast();
    }

    /**
     * @notice Accept an escrow as seller
     */
    function acceptEscrow() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(privateKey);

        Escrow escrow = Escrow(payable(escrowAddress));
        escrow.acceptEscrow();

        console.log("Escrow accepted");

        vm.stopBroadcast();
    }

    /**
     * @notice Mark work as completed
     */
    function markCompleted() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(privateKey);

        Escrow escrow = Escrow(payable(escrowAddress));
        escrow.markCompleted();

        console.log("Work marked as completed");

        vm.stopBroadcast();
    }

    /**
     * @notice Release payment as buyer
     */
    function releasePayment() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(privateKey);

        Escrow escrow = Escrow(payable(escrowAddress));
        escrow.releasePayment();

        console.log("Payment released to seller");

        vm.stopBroadcast();
    }

    /**
     * @notice Raise a dispute
     */
    function raiseDispute() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(privateKey);

        Escrow escrow = Escrow(payable(escrowAddress));
        escrow.raiseDispute{value: 0.01 ether}("Work not as described");

        console.log("Dispute raised");

        vm.stopBroadcast();
    }

    /**
     * @notice Assign arbitrator to disputed escrow
     */
    function assignArbitrator() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast(privateKey);

        factory.assignArbitratorToEscrow(escrowAddress);

        console.log("Arbitrator assigned");

        vm.stopBroadcast();
    }

    /**
     * @notice Resolve dispute as arbitrator
     */
    function resolveDispute() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        uint8 outcome = uint8(vm.envUint("OUTCOME")); // 1=BUYER_WINS, 2=SELLER_WINS, 3=SPLIT

        vm.startBroadcast(privateKey);

        Escrow escrow = Escrow(payable(escrowAddress));
        escrow.resolveDispute(Escrow.DisputeOutcome(outcome));

        console.log("Dispute resolved");

        vm.stopBroadcast();
    }

    /**
     * @notice View escrow details
     */
    function viewEscrowDetails() public view {
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        Escrow escrow = Escrow(payable(escrowAddress));

        (
            address buyer,
            address seller,
            address tokenAddr,
            uint256 amount,
            uint256 deadline,
            Escrow.State state,
            string memory description
        ) = escrow.getDetails();

        console.log("=== Escrow Details ===");
        console.log("Buyer:", buyer);
        console.log("Seller:", seller);
        console.log("Token:", tokenAddr);
        console.log("Amount:", amount);
        console.log("Deadline:", deadline);
        console.log("State:", uint(state));
        console.log("Description:", description);
    }

    /**
     * @notice Get all escrows
     */
    function getAllEscrows() public view {
        address[] memory escrows = factory.getAllEscrows();
        console.log("Total escrows:", escrows.length);
        for (uint i = 0; i < escrows.length; i++) {
            console.log("Escrow", i, ":", escrows[i]);
        }
    }
}
