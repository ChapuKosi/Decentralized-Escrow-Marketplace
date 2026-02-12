// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowFactory.sol";
import "../src/ArbitratorRegistry.sol";
import "../src/Escrow.sol";
import "../src/MockERC20.sol";

contract EscrowFactoryTest is Test {
    EscrowFactory public factory;
    ArbitratorRegistry public registry;
    MockERC20 public token;

    address public owner = address(this);
    address public feeRecipient = address(1);
    address public buyer = address(2);
    address public seller = address(3);
    address public arbitrator = address(4);

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public deadline;

    function setUp() public {
        registry = new ArbitratorRegistry();
        factory = new EscrowFactory(address(registry), feeRecipient);
        token = new MockERC20("Test Token", "TEST");

        deadline = block.timestamp + 7 days;

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        
        token.mint(buyer, 1000 ether);

        registry.registerArbitrator(arbitrator, 0.01 ether);
        factory.setSupportedToken(address(token), true);
    }

    function testCreateEscrow() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test escrow"
        );

        assertTrue(factory.isEscrow(escrowAddress));
        assertEq(factory.getTotalEscrows(), 1);
    }

    function testCreateMultipleEscrows() public {
        vm.startPrank(buyer);
        
        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 1"
        );

        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 2"
        );

        vm.stopPrank();

        assertEq(factory.getTotalEscrows(), 2);
    }

    function testGetUserEscrows() public {
        vm.prank(buyer);
        address escrow1 = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 1"
        );

        address[] memory buyerEscrows = factory.getUserEscrows(buyer);
        address[] memory sellerEscrows = factory.getUserEscrows(seller);

        assertEq(buyerEscrows.length, 1);
        assertEq(sellerEscrows.length, 1);
        assertEq(buyerEscrows[0], escrow1);
        assertEq(sellerEscrows[0], escrow1);
    }

    function testGetActiveEscrows() public {
        // Create multiple escrows
        vm.startPrank(buyer);
        address escrow1 = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 1"
        );

        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 2"
        );
        vm.stopPrank();

        // Accept one escrow
        vm.prank(seller);
        Escrow(payable(escrow1)).acceptEscrow();

        // Get active escrows
        address[] memory active = factory.getActiveEscrows();
        assertEq(active.length, 1);
        assertEq(active[0], escrow1);
    }

    function testCannotCreateWithUnsupportedToken() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP");
        unsupportedToken.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        unsupportedToken.approve(address(factory), ESCROW_AMOUNT);

        vm.expectRevert(EscrowFactory.TokenNotSupported.selector);
        factory.createEscrow(
            seller,
            address(unsupportedToken),
            ESCROW_AMOUNT,
            deadline,
            "Test"
        );
        vm.stopPrank();
    }

    function testSetSupportedToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW");

        factory.setSupportedToken(address(newToken), true);
        assertTrue(factory.supportedTokens(address(newToken)));

        factory.setSupportedToken(address(newToken), false);
        assertFalse(factory.supportedTokens(address(newToken)));
    }

    function testSetDefaultDisputeFee() public {
        uint256 newFee = 0.05 ether;
        factory.setDefaultDisputeFee(newFee);
        assertEq(factory.defaultDisputeFee(), newFee);
    }

    function testSetPlatformFee() public {
        uint256 newFee = 500; // 5%
        factory.setPlatformFee(newFee);
        assertEq(factory.platformFeePercent(), newFee);
    }

    function testCannotSetPlatformFeeTooHigh() public {
        uint256 tooHighFee = 1500; // 15%
        vm.expectRevert(EscrowFactory.InvalidFee.selector);
        factory.setPlatformFee(tooHighFee);
    }

    function testPauseAndUnpause() public {
        factory.pause();

        vm.prank(buyer);
        vm.expectRevert();
        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test"
        );

        factory.unpause();

        vm.prank(buyer);
        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test"
        );
    }

    function testAssignArbitratorToEscrow() public {
        // Create and accept escrow
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test"
        );

        vm.prank(seller);
        Escrow(payable(escrowAddress)).acceptEscrow();

        // Raise dispute
        vm.prank(buyer);
        Escrow(payable(escrowAddress)).raiseDispute{value: 0.01 ether}("Issue");

        // Assign arbitrator
        factory.assignArbitratorToEscrow(escrowAddress);

        assertEq(Escrow(payable(escrowAddress)).arbitrator(), arbitrator);
    }

    function testCalculateFee() public {
        uint256 amount = 1 ether;
        uint256 feePercent = 250; // 2.5%
        
        factory.setPlatformFee(feePercent);
        
        uint256 amountAfterFee = factory.calculateFee(amount);
        uint256 expectedFee = (amount * feePercent) / 10000;
        
        assertEq(amountAfterFee, amount - expectedFee);
    }

    function testWithdrawFees() public {
        // Create escrow to generate some fees
        vm.prank(buyer);
        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test"
        );

        // Send some ETH to factory as fees
        vm.deal(address(factory), 1 ether);

        uint256 feeRecipientBalanceBefore = feeRecipient.balance;

        factory.withdrawFees();

        assertTrue(feeRecipient.balance > feeRecipientBalanceBefore);
    }

    function testGetStatistics() public {
        // Create some escrows
        vm.startPrank(buyer);
        address escrow1 = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 1"
        );

        factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Escrow 2"
        );
        vm.stopPrank();

        // Accept one
        vm.prank(seller);
        Escrow(payable(escrow1)).acceptEscrow();

        (uint256 totalEscrows, uint256 totalValue, , uint256 activeEscrows) = factory.getStatistics();

        assertEq(totalEscrows, 2);
        assertEq(totalValue, ESCROW_AMOUNT * 2);
        assertEq(activeEscrows, 1);
    }

    function testCreateEscrowWithCustomFee() public {
        uint256 customFee = 0.02 ether;

        vm.prank(buyer);
        address escrowAddress = factory.createEscrowWithCustomFee{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Test",
            customFee
        );

        assertEq(Escrow(payable(escrowAddress)).disputeFee(), customFee);
    }

    function testERC20Escrow() public {
        vm.startPrank(buyer);
        token.approve(address(factory), ESCROW_AMOUNT);

        address escrowAddress = factory.createEscrow(
            seller,
            address(token),
            ESCROW_AMOUNT,
            deadline,
            "ERC20 Escrow"
        );
        vm.stopPrank();

        assertEq(token.balanceOf(escrowAddress), ESCROW_AMOUNT);
    }

    function testOnlyOwnerCanSetFeeRecipient() public {
        address newRecipient = address(5);

        vm.prank(buyer);
        vm.expectRevert();
        factory.setFeeRecipient(newRecipient);

        factory.setFeeRecipient(newRecipient);
        assertEq(factory.feeRecipient(), newRecipient);
    }
}
