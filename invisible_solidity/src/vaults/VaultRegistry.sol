// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../helpers/FlashLender.sol";
import "./AssetVault.sol";
import "./EthVault.sol";

// This should probably implement the falshloans
contract VaultRegistry is FlashLender {
    event VaultRegisteredEvent(address vaultAddress, address tokenAddress);

    address ethVaultAddress;

    mapping(address => address) vaults; // maps token address to vault address

    constructor() {
        ETHVault ethVault = new ETHVault(address(this));
        ethVaultAddress = address(ethVault);
    }

    // Todo: Should be internal (public only for testing)
    function addNewAssetVault(address tokenAddress) public {
        require(vaults[tokenAddress] == address(0), "Vault already registered");

        AssetVault newVault = new AssetVault(tokenAddress, address(this));

        vaults[tokenAddress] = address(newVault);
        emit VaultRegisteredEvent(address(newVault), tokenAddress);
    }

    // ---------------------------------------------------------

    function getAssetVaultAddress(address tokenAddress)
        public
        view
        returns (address)
    {
        address vaultAddress = vaults[tokenAddress];

        // TODO RETURN ETH VAULT IF TOKEN IS ETH => address == 0x0
        require(
            vaultAddress != address(0),
            "Vault not registered (check if you are calling the correct function for ETH interactions)"
        );

        return vaultAddress;
    }

    function getETHVaultAddress() public view returns (address) {
        return ethVaultAddress;
    }
}
