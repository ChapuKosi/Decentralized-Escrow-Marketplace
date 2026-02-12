// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Mint 1 million tokens to deployer
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /**
     * @notice Mint tokens to an address
     * @param to Address to receive minted tokens
     * @param amount Amount of tokens to mint
     * @dev Public function for testing purposes only. Not restricted.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     * @dev Public function for testing purposes only. Burns from msg.sender.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
