// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IPedersenHash.sol";

import "./core/VaultManager.sol";
import "./core/L2/L2Interactions.sol";
import "./core/L2/L2MessageRelay.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract InvisibleL2 is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    VaultManager,
    L2Interactions
{
    function initialize(
        address initialOwner,
        uint32 _chainId
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        __VaultManager_init(payable(initialOwner), _chainId);
    }

    function setMessageRelay(address _relay) external onlyOwner {
        s_messageRelay = _relay;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
