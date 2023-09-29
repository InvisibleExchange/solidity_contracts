// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IVaults.sol";
import "forge-std/console.sol";

import "../helpers/tokenInfo.sol";
import "../helpers/parseProgramOutput.sol";
import "../vaults/VaultRegistry.sol";

contract Withdrawal is TokenInfo, ProgramOutputParser, VaultRegistry {
    event WithdrawalEvent(
        address withdrawer,
        address tokenAddress,
        uint256 withdrawalAmount,
        uint256 timestamp
    );
    event StoredNewWithdrawalsEvent(uint256 timestamp, uint64 txBatchId);

    function storeNewBatchWithdrawalOutputs(
        WithdrawalTransactionOutput[] memory withdrawalOutputs,
        uint64 txBatchId
    ) internal {
        for (uint256 i = 0; i < withdrawalOutputs.length; i++) {
            WithdrawalTransactionOutput
                memory withdrawalOutput = withdrawalOutputs[i];

            (
                uint32 chainId,
                uint32 tokenId,
                uint64 amount,
                address recipient
            ) = uncompressWithdrawalOutput(withdrawalOutput);

            // TODO: Check chain id

            if (amount == 0) continue;

            uint256 amountScaled = scaleUp(amount, tokenId);

            if (tokenId == TokenInfo.ETH_ID) {
                address vaultAddress = getETHVaultAddress();
                IETHVault vault = IETHVault(vaultAddress);

                vault.increaseWithdrawableAmount(recipient, amountScaled);
            } else {
                address tokenAddress = getTokenAddress(tokenId);

                address vaultAddress = getAssetVaultAddress(tokenAddress);
                IAssetVault vault = IAssetVault(vaultAddress);

                vault.increaseWithdrawableAmount(
                    recipient,
                    tokenAddress,
                    amountScaled
                );
            }
        }

        emit StoredNewWithdrawalsEvent(block.timestamp, txBatchId);
    }

    //

    function _makeWithdrawal(
        address _tokenAddress,
        address _recipient,
        address _approvedProxy,
        uint256 _proxyFee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        //

        // TODO: Make sure that either msg.sender is the receipient
        // TODO  or that the receipient signed a message allowing you to withdraw for a fee
        // TODO: The fee is at most 10% of the withdrawal amount

        if (msg.sender != _recipient) {
            bytes32 messageHash = keccak256(
                abi.encodePacked(_tokenAddress, _approvedProxy, _proxyFee)
            );

            bytes memory prefix = "\x19Ethereum Signed Message:\n32";
            bytes32 prefixedHashMessage = keccak256(
                abi.encodePacked(prefix, messageHash)
            );
            address signer = ecrecover(prefixedHashMessage, v, r, s);

            // ? assert that the signer really  aproved the proxy to withdraw
            require(signer == _recipient, "invalid signature");
            // ? assert that the signer is the intended proxy
            require(
                _approvedProxy == msg.sender,
                "invalid proxy caller address"
            );
        } else {
            _approvedProxy = address(0);
            _proxyFee = 0;
        }

        if (_tokenAddress == address(0)) {
            return withdrawETH(_recipient, _approvedProxy, _proxyFee);
        } else {
            return
                withdrawERC20(
                    _tokenAddress,
                    _recipient,
                    _approvedProxy,
                    _proxyFee
                );
        }

        // TODO: This probably isnt needed event is emited in the vault contract
        // emit WithdrawalEvent(
        //     msg.sender,
        //     tokenAddress,
        //     withdrawableAmount,
        //     block.timestamp
        // );
    }

    function withdrawERC20(
        address tokenAddress,
        address _recipient,
        address _approvedProxy,
        uint256 _proxyFee
    ) private {
        address vaultAddress = getAssetVaultAddress(tokenAddress);
        IAssetVault vault = IAssetVault(vaultAddress);

        uint256 withdrawableAmount = vault.getWithdrawableAmount(_recipient);
        if (msg.sender != _recipient) {
            // ? The fee is at most 10% of the withdrawal amount
            require(
                withdrawableAmount >= _proxyFee * 10,
                "proxy fee is too high"
            );
        }

        vault.makeErc20VaultWithdrawal(
            tokenAddress,
            _recipient,
            _approvedProxy,
            _proxyFee
        );
    }

    function withdrawETH(
        address _recipient,
        address _approvedProxy,
        uint256 _proxyFee
    ) private {
        address vaultAddress = getETHVaultAddress();
        IETHVault vault = IETHVault(vaultAddress);

        uint256 withdrawableAmount = vault.getWithdrawableAmount(_recipient);
        if (msg.sender != _recipient) {
            // ? The fee is at most 10% of the withdrawal amount
            require(
                withdrawableAmount >= _proxyFee * 10,
                "proxy fee is too high"
            );
        }

        vault.makeETHVaultWithdrawal(
            payable(_recipient),
            payable(_approvedProxy),
            _proxyFee
        );

        emit WithdrawalEvent(
            msg.sender,
            address(0),
            withdrawableAmount,
            block.timestamp
        );
    }
}

function splitSignature(
    bytes memory sig
) view returns (bytes32 r, bytes32 s, uint8 v) {
    // require(sig.length == 65, "invalid signature length");

    assembly {
        /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

        // first 32 bytes, after the length prefix
        r := mload(add(sig, 32))
        // second 32 bytes
        s := mload(add(sig, 64))
        // final byte (first byte of the next 32 bytes)
        v := byte(0, mload(add(sig, 96)))
    }

    // implicitly return (r, s, v)
}
