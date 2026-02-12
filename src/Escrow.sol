// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Escrow
 * @notice Individual escrow contract for a single deal between buyer and seller
 * @dev Handles funds, state transitions, and dispute resolution for one transaction
 */
contract Escrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State machine for escrow lifecycle
    enum State {
        CREATED, // Escrow created, waiting for seller acceptance
        ACCEPTED, // Seller accepted, work in progress
        COMPLETED, // Work completed, funds released to seller
        DISPUTED, // Dispute raised, awaiting arbitration
        RESOLVED, // Dispute resolved by arbitrator
        CANCELLED // Cancelled before acceptance
    }

    // Dispute resolution outcomes
    enum DisputeOutcome {
        NONE,
        BUYER_WINS, // Full refund to buyer
        SELLER_WINS, // Full payment to seller
        SPLIT // 50/50 split
    }

    // Core participants
    address public immutable buyer;
    address public immutable seller;
    address public immutable factory;
    address public arbitrator;

    // Payment details
    address public immutable token; // address(0) for ETH
    uint256 public immutable amount;
    uint256 public immutable disputeFee;

    // Timeline
    uint256 public immutable deadline;
    uint256 public immutable createdAt;

    // State variables
    State public state;
    DisputeOutcome public disputeOutcome;

    // Metadata
    string public description;
    string public disputeReason;

    // Events
    event EscrowCreated(address indexed buyer, address indexed seller, uint256 amount, uint256 deadline);
    event EscrowAccepted(address indexed seller, uint256 timestamp);
    event WorkCompleted(address indexed seller, uint256 timestamp);
    event PaymentReleased(address indexed seller, uint256 amount, uint256 timestamp);
    event DisputeRaised(address indexed raiser, string reason, uint256 timestamp);
    event DisputeResolved(DisputeOutcome outcome, address indexed arbitrator, uint256 timestamp);
    event EscrowCancelled(uint256 timestamp);
    event ArbitratorAssigned(address indexed arbitrator);

    // Errors
    error InvalidState();
    error Unauthorized();
    error DeadlineNotPassed();
    error DeadlinePassed();
    error InvalidAmount();
    error TransferFailed();
    error InvalidToken();

    /**
     * @notice Creates a new escrow contract
     * @param _buyer Address of the buyer (funds depositor)
     * @param _seller Address of the seller (service provider)
     * @param _token Token address (address(0) for ETH)
     * @param _amount Amount to be held in escrow
     * @param _deadline Unix timestamp for completion deadline
     * @param _description Description of the work/goods
     * @param _disputeFee Fee required to raise a dispute
     */
    constructor(
        address _buyer,
        address _seller,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        string memory _description,
        uint256 _disputeFee
    ) payable {
        if (_buyer == address(0) || _seller == address(0)) revert Unauthorized();
        if (_buyer == _seller) revert Unauthorized();
        if (_amount == 0) revert InvalidAmount();
        if (_deadline <= block.timestamp) revert DeadlinePassed();

        buyer = _buyer;
        seller = _seller;
        token = _token;
        amount = _amount;
        deadline = _deadline;
        description = _description;
        disputeFee = _disputeFee;
        factory = msg.sender;
        createdAt = block.timestamp;
        state = State.CREATED;

        // If ETH escrow, verify msg.value matches amount
        if (_token == address(0)) {
            if (msg.value != _amount) revert InvalidAmount();
        }

        emit EscrowCreated(_buyer, _seller, _amount, _deadline);
    }

    /**
     * @notice Seller accepts the escrow deal
     * @dev Can only be called by seller when in CREATED state
     */
    function acceptEscrow() external {
        if (msg.sender != seller) revert Unauthorized();
        if (state != State.CREATED) revert InvalidState();
        if (block.timestamp > deadline) revert DeadlinePassed();

        state = State.ACCEPTED;
        emit EscrowAccepted(seller, block.timestamp);
    }

    /**
     * @notice Seller marks work as completed
     * @dev Signals to buyer that work is ready for review
     */
    function markCompleted() external {
        if (msg.sender != seller) revert Unauthorized();
        if (state != State.ACCEPTED) revert InvalidState();

        // Note: We don't change state here, just emit event
        // Buyer must still explicitly release payment
        emit WorkCompleted(seller, block.timestamp);
    }

    /**
     * @notice Buyer releases payment to seller
     * @dev Can only be called by buyer when satisfied with work
     */
    function releasePayment() external nonReentrant {
        if (msg.sender != buyer) revert Unauthorized();
        if (state != State.ACCEPTED) revert InvalidState();

        state = State.COMPLETED;

        _transferFunds(seller, amount);

        emit PaymentReleased(seller, amount, block.timestamp);
    }

    /**
     * @notice Buyer or seller raises a dispute
     * @param _reason Description of the dispute
     * @dev Requires payment of dispute fee to prevent spam
     */
    function raiseDispute(string memory _reason) external payable {
        if (msg.sender != buyer && msg.sender != seller) revert Unauthorized();
        if (state != State.ACCEPTED) revert InvalidState();
        if (msg.value < disputeFee) revert InvalidAmount();

        state = State.DISPUTED;
        disputeReason = _reason;

        emit DisputeRaised(msg.sender, _reason, block.timestamp);
    }

    /**
     * @notice Assign an arbitrator to resolve dispute
     * @param _arbitrator Address of the arbitrator
     * @dev Called by factory contract
     */
    function assignArbitrator(address _arbitrator) external {
        if (msg.sender != factory) revert Unauthorized();
        if (state != State.DISPUTED) revert InvalidState();
        if (_arbitrator == address(0)) revert Unauthorized();

        arbitrator = _arbitrator;
        emit ArbitratorAssigned(_arbitrator);
    }

    /**
     * @notice Arbitrator resolves the dispute
     * @param outcome Resolution decision
     * @dev Only callable by assigned arbitrator
     */
    function resolveDispute(DisputeOutcome outcome) external nonReentrant {
        if (msg.sender != arbitrator) revert Unauthorized();
        if (state != State.DISPUTED) revert InvalidState();
        if (outcome == DisputeOutcome.NONE) revert InvalidState();

        state = State.RESOLVED;
        disputeOutcome = outcome;

        // Execute the resolution
        if (outcome == DisputeOutcome.BUYER_WINS) {
            _transferFunds(buyer, amount);
        } else if (outcome == DisputeOutcome.SELLER_WINS) {
            _transferFunds(seller, amount);
        } else if (outcome == DisputeOutcome.SPLIT) {
            uint256 halfAmount = amount / 2;
            _transferFunds(buyer, halfAmount);
            _transferFunds(seller, amount - halfAmount); // Handle odd amounts
        }

        emit DisputeResolved(outcome, arbitrator, block.timestamp);
    }

    /**
     * @notice Cancel escrow before seller accepts
     * @dev Only buyer can cancel, only in CREATED state
     */
    function cancelEscrow() external nonReentrant {
        if (msg.sender != buyer) revert Unauthorized();
        if (state != State.CREATED) revert InvalidState();

        state = State.CANCELLED;

        _transferFunds(buyer, amount);

        emit EscrowCancelled(block.timestamp);
    }

    /**
     * @notice Seller can claim funds after deadline plus grace period
     * @dev Prevents funds being locked forever due to buyer inactivity. Requires 7-day grace period after deadline.
     */
    function claimAfterDeadline() external nonReentrant {
        if (msg.sender != seller) revert Unauthorized();
        if (state != State.ACCEPTED) revert InvalidState();
        if (block.timestamp <= deadline + 7 days) revert DeadlineNotPassed();

        state = State.COMPLETED;

        _transferFunds(seller, amount);

        emit PaymentReleased(seller, amount, block.timestamp);
    }

    /**
     * @notice Internal function to transfer funds (ETH or ERC20)
     * @param to Recipient address
     * @param _amount Amount to transfer
     */
    function _transferFunds(address to, uint256 _amount) private {
        if (token == address(0)) {
            // Transfer ETH
            (bool success,) = to.call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Transfer ERC20
            IERC20(token).safeTransfer(to, _amount);
        }
    }

    /**
     * @notice View function to check if escrow is active
     * @return bool True if escrow is in ACCEPTED or DISPUTED state
     */
    function isActive() external view returns (bool) {
        return state == State.ACCEPTED || state == State.DISPUTED;
    }

    /**
     * @notice View function to check if deadline has passed
     * @return bool True if current timestamp is past the deadline
     */
    function isDeadlinePassed() external view returns (bool) {
        return block.timestamp > deadline;
    }

    /**
     * @notice View function to get time remaining until deadline
     * @return uint256 Seconds remaining until deadline, or 0 if deadline passed
     */
    function timeRemaining() external view returns (uint256) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    /**
     * @notice Get comprehensive escrow details
     * @return _buyer Address of the buyer
     * @return _seller Address of the seller
     * @return _token Token address (address(0) for ETH)
     * @return _amount Amount held in escrow
     * @return _deadline Completion deadline timestamp
     * @return _state Current state of the escrow
     * @return _description Work description
     */
    function getDetails()
        external
        view
        returns (
            address _buyer,
            address _seller,
            address _token,
            uint256 _amount,
            uint256 _deadline,
            State _state,
            string memory _description
        )
    {
        return (buyer, seller, token, amount, deadline, state, description);
    }

    // Allow contract to receive ETH for dispute fees
    receive() external payable {}
}
