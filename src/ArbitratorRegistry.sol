// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ArbitratorRegistry
 * @notice Manages the pool of trusted arbitrators and their reputation
 * @dev Whitelist-based system with reputation tracking
 */
contract ArbitratorRegistry is Ownable {
    
    struct ArbitratorInfo {
        bool isActive;
        uint256 totalCases;
        uint256 resolvedCases;
        uint256 reputation; // Score out of 100
        uint256 feePerCase; // Fee charged per dispute resolution
        uint256 registeredAt;
    }

    // Mapping from arbitrator address to their info
    mapping(address => ArbitratorInfo) public arbitrators;
    
    // Array of all arbitrator addresses for iteration
    address[] public arbitratorList;

    // Minimum reputation score to remain active
    uint256 public constant MIN_REPUTATION = 50;

    // Events
    event ArbitratorRegistered(address indexed arbitrator, uint256 feePerCase);
    event ArbitratorDeactivated(address indexed arbitrator);
    event ArbitratorReactivated(address indexed arbitrator);
    event CaseAssigned(address indexed arbitrator, address indexed escrow);
    event CaseResolved(address indexed arbitrator, address indexed escrow, bool satisfactory);
    event ReputationUpdated(address indexed arbitrator, uint256 newReputation);
    event FeeUpdated(address indexed arbitrator, uint256 newFee);

    // Errors
    error ArbitratorNotActive();
    error ArbitratorAlreadyExists();
    error ArbitratorNotFound();
    error InvalidFee();
    error InvalidReputation();

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new arbitrator
     * @param _arbitrator Address of the arbitrator to register
     * @param _feePerCase Fee the arbitrator charges per case in wei
     * @dev Only owner can register. New arbitrators start with perfect reputation score of 100.
     */
    function registerArbitrator(address _arbitrator, uint256 _feePerCase) external onlyOwner {
        if (arbitrators[_arbitrator].registeredAt != 0) revert ArbitratorAlreadyExists();
        if (_arbitrator == address(0)) revert ArbitratorNotFound();

        arbitrators[_arbitrator] = ArbitratorInfo({
            isActive: true,
            totalCases: 0,
            resolvedCases: 0,
            reputation: 100, // Start with perfect score
            feePerCase: _feePerCase,
            registeredAt: block.timestamp
        });

        arbitratorList.push(_arbitrator);

        emit ArbitratorRegistered(_arbitrator, _feePerCase);
    }

    /**
     * @notice Deactivate an arbitrator
     * @param _arbitrator Address to deactivate
     * @dev Only owner can manually deactivate. Arbitrators may also be auto-deactivated if reputation falls below 50.
     */
    function deactivateArbitrator(address _arbitrator) external onlyOwner {
        if (arbitrators[_arbitrator].registeredAt == 0) revert ArbitratorNotFound();
        if (!arbitrators[_arbitrator].isActive) revert ArbitratorNotActive();

        arbitrators[_arbitrator].isActive = false;

        emit ArbitratorDeactivated(_arbitrator);
    }

    /**
     * @notice Reactivate a previously deactivated arbitrator
     * @param _arbitrator Address to reactivate
     * @dev Only owner can reactivate. Requires reputation >= 50.
     */
    function reactivateArbitrator(address _arbitrator) external onlyOwner {
        if (arbitrators[_arbitrator].registeredAt == 0) revert ArbitratorNotFound();
        if (arbitrators[_arbitrator].isActive) revert ArbitratorAlreadyExists();
        if (arbitrators[_arbitrator].reputation < MIN_REPUTATION) revert InvalidReputation();

        arbitrators[_arbitrator].isActive = true;

        emit ArbitratorReactivated(_arbitrator);
    }

    /**
     * @notice Update arbitrator's fee per case
     * @param _feePerCase New fee amount in wei
     * @dev Only the arbitrator themselves can update their fee.
     */
    function updateFee(uint256 _feePerCase) external {
        if (arbitrators[msg.sender].registeredAt == 0) revert ArbitratorNotFound();

        arbitrators[msg.sender].feePerCase = _feePerCase;

        emit FeeUpdated(msg.sender, _feePerCase);
    }

    /**
     * @notice Record that a case was assigned to an arbitrator
     * @param _arbitrator Address of arbitrator receiving the case
     * @dev Called by EscrowFactory when a dispute is raised. Increments totalCases counter.
     */
    function assignCase(address _arbitrator) external {
        if (!arbitrators[_arbitrator].isActive) revert ArbitratorNotActive();

        arbitrators[_arbitrator].totalCases++;

        emit CaseAssigned(_arbitrator, msg.sender);
    }

    /**
     * @notice Record case resolution and update arbitrator reputation
     * @param _arbitrator Address of arbitrator who resolved the case
     * @param _satisfactory Whether the resolution was satisfactory
     * @dev Satisfactory: +1 reputation (max 100). Unsatisfactory: -5 reputation. Auto-deactivates if reputation < 50.
     */
    function recordResolution(address _arbitrator, bool _satisfactory) external {
        if (arbitrators[_arbitrator].registeredAt == 0) revert ArbitratorNotFound();

        ArbitratorInfo storage info = arbitrators[_arbitrator];
        info.resolvedCases++;

        // Update reputation based on satisfaction
        if (_satisfactory) {
            // Increase reputation, max 100
            if (info.reputation < 100) {
                info.reputation = info.reputation + 1 > 100 ? 100 : info.reputation + 1;
            }
        } else {
            // Decrease reputation
            if (info.reputation > 5) {
                info.reputation -= 5;
            } else {
                info.reputation = 0;
            }

            // Auto-deactivate if reputation drops too low
            if (info.reputation < MIN_REPUTATION) {
                info.isActive = false;
                emit ArbitratorDeactivated(_arbitrator);
            }
        }

        emit CaseResolved(_arbitrator, msg.sender, _satisfactory);
        emit ReputationUpdated(_arbitrator, info.reputation);
    }

    /**
     * @notice Get a random active arbitrator for case assignment
     * @return address Address of randomly selected active arbitrator
     * @dev Uses pseudo-random selection based on block data. For production, consider Chainlink VRF.
     */
    function getRandomArbitrator() external view returns (address) {
        uint256 activeCount = 0;
        
        // Count active arbitrators
        for (uint256 i = 0; i < arbitratorList.length; i++) {
            if (arbitrators[arbitratorList[i]].isActive) {
                activeCount++;
            }
        }

        if (activeCount == 0) revert ArbitratorNotActive();

        // Simple pseudo-random selection
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % activeCount;
        
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < arbitratorList.length; i++) {
            if (arbitrators[arbitratorList[i]].isActive) {
                if (currentIndex == randomIndex) {
                    return arbitratorList[i];
                }
                currentIndex++;
            }
        }

        revert ArbitratorNotActive();
    }

    /**
     * @notice Get arbitrator with highest reputation score
     * @return address Address of the arbitrator with best reputation
     * @dev Returns the active arbitrator with the highest reputation score.
     */
    function getBestArbitrator() external view returns (address) {
        address best = address(0);
        uint256 bestReputation = 0;

        for (uint256 i = 0; i < arbitratorList.length; i++) {
            address arb = arbitratorList[i];
            if (arbitrators[arb].isActive && arbitrators[arb].reputation > bestReputation) {
                best = arb;
                bestReputation = arbitrators[arb].reputation;
            }
        }

        if (best == address(0)) revert ArbitratorNotActive();
        return best;
    }

    /**
     * @notice Get all active arbitrators
     * @return address[] Array of addresses of all active arbitrators
     */
    function getActiveArbitrators() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < arbitratorList.length; i++) {
            if (arbitrators[arbitratorList[i]].isActive) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < arbitratorList.length; i++) {
            if (arbitrators[arbitratorList[i]].isActive) {
                active[currentIndex] = arbitratorList[i];
                currentIndex++;
            }
        }

        return active;
    }

    /**
     * @notice Check if an address is an active arbitrator
     * @param _arbitrator Address to check
     * @return bool True if the address is registered and active
     */
    function isActiveArbitrator(address _arbitrator) external view returns (bool) {
        return arbitrators[_arbitrator].isActive;
    }

    /**
     * @notice Get comprehensive arbitrator information
     * @param _arbitrator Address of the arbitrator to query
     * @return isActive Whether the arbitrator is currently active
     * @return totalCases Total number of cases assigned to arbitrator
     * @return resolvedCases Number of cases successfully resolved
     * @return reputation Current reputation score (0-100)
     * @return feePerCase Fee charged per dispute resolution in wei
     */
    function getArbitratorInfo(address _arbitrator) external view returns (
        bool isActive,
        uint256 totalCases,
        uint256 resolvedCases,
        uint256 reputation,
        uint256 feePerCase
    ) {
        ArbitratorInfo memory info = arbitrators[_arbitrator];
        return (
            info.isActive,
            info.totalCases,
            info.resolvedCases,
            info.reputation,
            info.feePerCase
        );
    }

    /**
     * @notice Get total number of registered arbitrators
     * @return uint256 Total count of registered arbitrators (both active and inactive)
     */
    function getTotalArbitrators() external view returns (uint256) {
        return arbitratorList.length;
    }
}
