// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/EscrowFactory.sol";
import "../src/ArbitratorRegistry.sol";
import "../src/MockERC20.sol";

contract EscrowTest is Test {
    Escrow public escrow;
    EscrowFactory public factory;
    ArbitratorRegistry public registry;
    MockERC20 public token;

    address public buyer = address(1);
    address public seller = address(2);
    address public arbitrator = address(3);
    address public feeRecipient = address(4);

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant DISPUTE_FEE = 0.01 ether;
    uint256 public deadline;

    event EscrowCreated(address indexed buyer, address indexed seller, uint256 amount, uint256 deadline);
    event EscrowAccepted(address indexed seller, uint256 timestamp);
    event WorkCompleted(address indexed seller, uint256 timestamp);
    event PaymentReleased(address indexed seller, uint256 amount, uint256 timestamp);
    event DisputeRaised(address indexed raiser, string reason, uint256 timestamp);
    event DisputeResolved(Escrow.DisputeOutcome outcome, address indexed arbitrator, uint256 timestamp);

    function setUp() public {
        // Deploy contracts
        registry = new ArbitratorRegistry();
        factory = new EscrowFactory(address(registry), feeRecipient);
        token = new MockERC20("Test Token", "TEST");

        // Setup deadline (7 days from now)
        deadline = block.timestamp + 7 days;

        // Fund accounts
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        vm.deal(arbitrator, 1 ether);

        // Mint tokens to buyer
        token.mint(buyer, 1000 ether);

        // Register arbitrator
        registry.registerArbitrator(arbitrator, 0.01 ether);

        // Add token support
        factory.setSupportedToken(address(token), true);
    }

    function testCreateETHEscrow() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0), // ETH
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        Escrow createdEscrow = Escrow(payable(escrowAddress));

        assertEq(createdEscrow.buyer(), buyer);
        assertEq(createdEscrow.seller(), seller);
        assertEq(createdEscrow.amount(), ESCROW_AMOUNT);
        assertEq(address(createdEscrow).balance, ESCROW_AMOUNT);
        assertEq(uint(createdEscrow.state()), uint(Escrow.State.CREATED));
    }

    function testCreateERC20Escrow() public {
        vm.startPrank(buyer);
        token.approve(address(factory), ESCROW_AMOUNT);
        
        address escrowAddress = factory.createEscrow(
            seller,
            address(token),
            ESCROW_AMOUNT,
            deadline,
            "Design a logo"
        );
        vm.stopPrank();

        Escrow createdEscrow = Escrow(payable(escrowAddress));

        assertEq(createdEscrow.token(), address(token));
        assertEq(token.balanceOf(escrowAddress), ESCROW_AMOUNT);
    }

    function testAcceptEscrow() public {
        // Create escrow
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        // Seller accepts
        vm.prank(seller);
        escrow.acceptEscrow();

        assertEq(uint(escrow.state()), uint(Escrow.State.ACCEPTED));
    }

    function testCannotAcceptTwice() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Try to accept again
        vm.prank(seller);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.acceptEscrow();
    }

    function testOnlySellerCanAccept() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        // Buyer tries to accept
        vm.prank(buyer);
        vm.expectRevert(Escrow.Unauthorized.selector);
        escrow.acceptEscrow();
    }

    function testReleasePayment() public {
        // Create and accept escrow
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Check seller balance before
        uint256 sellerBalanceBefore = seller.balance;

        // Buyer releases payment
        vm.prank(buyer);
        escrow.releasePayment();

        // Check state and balance
        assertEq(uint(escrow.state()), uint(Escrow.State.COMPLETED));
        assertEq(seller.balance, sellerBalanceBefore + ESCROW_AMOUNT);
    }

    function testMarkCompleted() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Seller marks as completed
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit WorkCompleted(seller, block.timestamp);
        escrow.markCompleted();

        // State should still be ACCEPTED
        assertEq(uint(escrow.state()), uint(Escrow.State.ACCEPTED));
    }

    function testRaiseDispute() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Buyer raises dispute
        vm.prank(buyer);
        escrow.raiseDispute{value: DISPUTE_FEE}("Work not as described");

        assertEq(uint(escrow.state()), uint(Escrow.State.DISPUTED));
    }

    function testResolveDisputeBuyerWins() public {
        // Create, accept, and dispute
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        vm.prank(buyer);
        escrow.raiseDispute{value: DISPUTE_FEE}("Work not as described");

        // Assign arbitrator
        factory.assignArbitratorToEscrow(escrowAddress);

        // Check buyer balance before
        uint256 buyerBalanceBefore = buyer.balance;

        // Arbitrator resolves in favor of buyer
        vm.prank(arbitrator);
        escrow.resolveDispute(Escrow.DisputeOutcome.BUYER_WINS);

        assertEq(uint(escrow.state()), uint(Escrow.State.RESOLVED));
        assertEq(buyer.balance, buyerBalanceBefore + ESCROW_AMOUNT);
    }

    function testResolveDisputeSellerWins() public {
        // Create, accept, and dispute
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        vm.prank(seller);
        escrow.raiseDispute{value: DISPUTE_FEE}("Buyer being unreasonable");

        factory.assignArbitratorToEscrow(escrowAddress);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(arbitrator);
        escrow.resolveDispute(Escrow.DisputeOutcome.SELLER_WINS);

        assertEq(uint(escrow.state()), uint(Escrow.State.RESOLVED));
        assertEq(seller.balance, sellerBalanceBefore + ESCROW_AMOUNT);
    }

    function testResolveDisputeSplit() public {
        // Create, accept, and dispute
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        vm.prank(buyer);
        escrow.raiseDispute{value: DISPUTE_FEE}("Partial work done");

        factory.assignArbitratorToEscrow(escrowAddress);

        uint256 buyerBalanceBefore = buyer.balance;
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(arbitrator);
        escrow.resolveDispute(Escrow.DisputeOutcome.SPLIT);

        assertEq(uint(escrow.state()), uint(Escrow.State.RESOLVED));
        assertEq(buyer.balance, buyerBalanceBefore + ESCROW_AMOUNT / 2);
        assertEq(seller.balance, sellerBalanceBefore + ESCROW_AMOUNT / 2);
    }

    function testCancelEscrow() public {
        // Create escrow
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        uint256 buyerBalanceBefore = buyer.balance;

        // Buyer cancels
        vm.prank(buyer);
        escrow.cancelEscrow();

        assertEq(uint(escrow.state()), uint(Escrow.State.CANCELLED));
        assertEq(buyer.balance, buyerBalanceBefore + ESCROW_AMOUNT);
    }

    function testCannotCancelAfterAcceptance() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Try to cancel
        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.cancelEscrow();
    }

    function testClaimAfterDeadline() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Fast forward past deadline + grace period
        vm.warp(deadline + 7 days + 1);

        uint256 sellerBalanceBefore = seller.balance;

        // Seller claims
        vm.prank(seller);
        escrow.claimAfterDeadline();

        assertEq(uint(escrow.state()), uint(Escrow.State.COMPLETED));
        assertEq(seller.balance, sellerBalanceBefore + ESCROW_AMOUNT);
    }

    function testCannotClaimBeforeGracePeriod() public {
        // Create and accept
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        vm.prank(seller);
        escrow.acceptEscrow();

        // Fast forward past deadline but not grace period
        vm.warp(deadline + 1);

        // Try to claim
        vm.prank(seller);
        vm.expectRevert(Escrow.DeadlineNotPassed.selector);
        escrow.claimAfterDeadline();
    }

    function testGetDetails() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        (
            address _buyer,
            address _seller,
            address _token,
            uint256 _amount,
            uint256 _deadline,
            Escrow.State _state,
            string memory _description
        ) = escrow.getDetails();

        assertEq(_buyer, buyer);
        assertEq(_seller, seller);
        assertEq(_token, address(0));
        assertEq(_amount, ESCROW_AMOUNT);
        assertEq(_deadline, deadline);
        assertEq(uint(_state), uint(Escrow.State.CREATED));
        assertEq(_description, "Build a website");
    }

    function testTimeRemaining() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        uint256 remaining = escrow.timeRemaining();
        assertEq(remaining, 7 days);

        // Fast forward 3 days
        vm.warp(block.timestamp + 3 days);
        remaining = escrow.timeRemaining();
        assertEq(remaining, 4 days);
    }

    function testIsActive() public {
        vm.prank(buyer);
        address escrowAddress = factory.createEscrow{value: ESCROW_AMOUNT}(
            seller,
            address(0),
            ESCROW_AMOUNT,
            deadline,
            "Build a website"
        );

        escrow = Escrow(payable(escrowAddress));

        assertFalse(escrow.isActive());

        vm.prank(seller);
        escrow.acceptEscrow();

        assertTrue(escrow.isActive());
    }
}
