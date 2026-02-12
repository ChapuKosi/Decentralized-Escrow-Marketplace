// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Escrow.sol";
import "./ArbitratorRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EscrowFactory
 * @notice Factory contract for creating and managing escrow deals
 * @dev Central hub for the marketplace, tracks all escrows and integrates with arbitrator registry
 */
contract EscrowFactory is Ownable, Pausable {
    using SafeERC20 for IERC20;

    // Reference to the arbitrator registry
    ArbitratorRegistry public immutable arbitratorRegistry;

    // Default dispute fee (can be overridden per escrow)
    uint256 public defaultDisputeFee;

    // Platform fee (percentage, e.g., 250 = 2.5%)
    uint256 public platformFeePercent;
    uint256 public constant FEE_DENOMINATOR = 10000;

    // Platform fee recipient
    address public feeRecipient;

    // Escrow tracking
    address[] public allEscrows;
    mapping(address => address[]) public userEscrows; // User => their escrows (as buyer or seller)
    mapping(address => bool) public isEscrow;

    // Supported tokens for escrow (address(0) = ETH)
    mapping(address => bool) public supportedTokens;

    // Statistics
    uint256 public totalEscrowsCreated;
    uint256 public totalValueLocked;
    uint256 public totalFeesCollected;

    // Events
    event EscrowCreated(
        address indexed escrow,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 amount,
        uint256 deadline
    );
    event DisputeFeeUpdated(uint256 newFee);
    event PlatformFeeUpdated(uint256 newFeePercent);
    event FeeRecipientUpdated(address indexed newRecipient);
    event TokenSupportUpdated(address indexed token, bool supported);
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    // Errors
    error TokenNotSupported();
    error InvalidFee();
    error InvalidAddress();
    error NotAnEscrow();

    /**
     * @notice Initialize the factory
     * @param _arbitratorRegistry Address of the arbitrator registry
     * @param _feeRecipient Address to receive platform fees
     */
    constructor(address _arbitratorRegistry, address _feeRecipient) Ownable(msg.sender) {
        if (_arbitratorRegistry == address(0) || _feeRecipient == address(0)) {
            revert InvalidAddress();
        }

        arbitratorRegistry = ArbitratorRegistry(_arbitratorRegistry);
        feeRecipient = _feeRecipient;
        defaultDisputeFee = 0.01 ether;
        platformFeePercent = 250; // 2.5%

        // ETH is always supported
        supportedTokens[address(0)] = true;
    }

    /**
     * @notice Create a new escrow deal
     * @param _seller Address of the seller
     * @param _token Token address (address(0) for ETH)
     * @param _amount Amount to escrow
     * @param _deadline Completion deadline
     * @param _description Work description
     * @return escrowAddress Address of the created escrow contract
     */
    function createEscrow(
        address _seller,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        string memory _description
    ) external payable whenNotPaused returns (address) {
        return _createEscrow(_seller, _token, _amount, _deadline, _description, defaultDisputeFee);
    }

    /**
     * @notice Create escrow with custom dispute fee
     * @param _seller Address of the seller
     * @param _token Token address (address(0) for ETH)
     * @param _amount Amount to escrow
     * @param _deadline Completion deadline
     * @param _description Work description
     * @param _disputeFee Custom dispute fee
     * @return escrowAddress Address of the created escrow contract
     */
    function createEscrowWithCustomFee(
        address _seller,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        string memory _description,
        uint256 _disputeFee
    ) external payable whenNotPaused returns (address) {
        return _createEscrow(_seller, _token, _amount, _deadline, _description, _disputeFee);
    }

    /**
     * @notice Internal function to create escrow
     */
    function _createEscrow(
        address _seller,
        address _token,
        uint256 _amount,
        uint256 _deadline,
        string memory _description,
        uint256 _disputeFee
    ) private returns (address) {
        if (!supportedTokens[_token]) revert TokenNotSupported();

        address buyer = msg.sender;
        uint256 valueToSend = 0;

        // Handle ETH escrows
        if (_token == address(0)) {
            if (msg.value != _amount) revert InvalidFee();
            valueToSend = _amount;
        } else {
            // Handle ERC20 escrows - transfer tokens from buyer to this contract first
            IERC20(_token).safeTransferFrom(buyer, address(this), _amount);
            // Approve escrow contract to pull tokens
        }

        // Deploy new escrow contract
        Escrow escrow =
            new Escrow{value: valueToSend}(buyer, _seller, _token, _amount, _deadline, _description, _disputeFee);

        address escrowAddress = address(escrow);

        // If ERC20, transfer tokens to escrow
        if (_token != address(0)) {
            IERC20(_token).safeTransfer(escrowAddress, _amount);
        }

        // Track escrow
        allEscrows.push(escrowAddress);
        userEscrows[buyer].push(escrowAddress);
        userEscrows[_seller].push(escrowAddress);
        isEscrow[escrowAddress] = true;

        // Update statistics
        totalEscrowsCreated++;
        totalValueLocked += _amount;

        emit EscrowCreated(escrowAddress, buyer, _seller, _token, _amount, _deadline);

        return escrowAddress;
    }

    /**
     * @notice Assign arbitrator to a disputed escrow
     * @param _escrow Address of the escrow contract
     * @dev Automatically selects the best arbitrator from the registry and records the case assignment
     */
    function assignArbitratorToEscrow(address _escrow) external {
        if (!isEscrow[_escrow]) revert NotAnEscrow();

        // Get best arbitrator from registry
        address arbitrator = arbitratorRegistry.getBestArbitrator();

        // Assign to escrow
        Escrow(payable(_escrow)).assignArbitrator(arbitrator);

        // Record in registry
        arbitratorRegistry.assignCase(arbitrator);
    }

    /**
     * @notice Calculate and collect platform fee
     * @param _amount Transaction amount
     * @return amountAfterFee Amount remaining after deducting platform fee
     */
    function calculateFee(uint256 _amount) public view returns (uint256 amountAfterFee) {
        uint256 fee = (_amount * platformFeePercent) / FEE_DENOMINATOR;
        return _amount - fee;
    }

    /**
     * @notice Add or remove token support
     * @param _token Token address to update
     * @param _supported Whether token should be supported for escrows
     * @dev Only owner can modify token whitelist. ETH (address(0)) is always supported.
     */
    function setSupportedToken(address _token, bool _supported) external onlyOwner {
        supportedTokens[_token] = _supported;
        emit TokenSupportUpdated(_token, _supported);
    }

    /**
     * @notice Update default dispute fee
     * @param _newFee New fee amount in wei
     * @dev Only owner can update. Applies to new escrows created with createEscrow().
     */
    function setDefaultDisputeFee(uint256 _newFee) external onlyOwner {
        defaultDisputeFee = _newFee;
        emit DisputeFeeUpdated(_newFee);
    }

    /**
     * @notice Update platform fee percentage
     * @param _newFeePercent New fee percentage in basis points (e.g., 250 = 2.5%)
     * @dev Only owner can update. Maximum allowed is 1000 (10%).
     */
    function setPlatformFee(uint256 _newFeePercent) external onlyOwner {
        if (_newFeePercent > 1000) revert InvalidFee(); // Max 10%
        platformFeePercent = _newFeePercent;
        emit PlatformFeeUpdated(_newFeePercent);
    }

    /**
     * @notice Update fee recipient
     * @param _newRecipient New recipient address
     */
    function setFeeRecipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) revert InvalidAddress();
        feeRecipient = _newRecipient;
        emit FeeRecipientUpdated(_newRecipient);
    }

    /**
     * @notice Emergency pause new escrow creation
     * @dev Only owner can pause. Existing escrows remain fully functional.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume escrow creation after pause
     * @dev Only owner can unpause.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraw accumulated fees
     * @dev Only owner can withdraw to fee recipient
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = feeRecipient.call{value: balance}("");
            require(success, "Transfer failed");
            emit FeesWithdrawn(feeRecipient, balance);
        }
    }

    /**
     * @notice Withdraw ERC20 fees
     * @param _token Token address
     */
    function withdrawTokenFees(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(feeRecipient, balance);
            emit FeesWithdrawn(feeRecipient, balance);
        }
    }

    /**
     * @notice Get all escrows
     */
    function getAllEscrows() external view returns (address[] memory) {
        return allEscrows;
    }

    /**
     * @notice Get escrows for a specific user
     * @param _user User address
     */
    function getUserEscrows(address _user) external view returns (address[] memory) {
        return userEscrows[_user];
    }

    /**
     * @notice Get active escrows (ACCEPTED or DISPUTED state)
     */
    function getActiveEscrows() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Count active escrows
        for (uint256 i = 0; i < allEscrows.length; i++) {
            if (Escrow(payable(allEscrows[i])).isActive()) {
                activeCount++;
            }
        }

        // Build array of active escrows
        address[] memory active = new address[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < allEscrows.length; i++) {
            if (Escrow(payable(allEscrows[i])).isActive()) {
                active[currentIndex] = allEscrows[i];
                currentIndex++;
            }
        }

        return active;
    }

    /**
     * @notice Get total number of escrows
     */
    function getTotalEscrows() external view returns (uint256) {
        return allEscrows.length;
    }

    /**
     * @notice Get marketplace statistics
     * @return totalEscrows Total number of escrows created
     * @return totalValue Total value locked across all escrows
     * @return totalFees Total platform fees collected
     * @return activeEscrows Number of currently active escrows
     */
    function getStatistics()
        external
        view
        returns (uint256 totalEscrows, uint256 totalValue, uint256 totalFees, uint256 activeEscrows)
    {
        uint256 active = 0;
        for (uint256 i = 0; i < allEscrows.length; i++) {
            if (Escrow(payable(allEscrows[i])).isActive()) {
                active++;
            }
        }

        return (totalEscrowsCreated, totalValueLocked, totalFeesCollected, active);
    }

    // Receive ETH for fees
    receive() external payable {}
}
