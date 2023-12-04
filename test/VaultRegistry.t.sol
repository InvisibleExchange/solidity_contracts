// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.21;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "forge-std/Vm.sol";

// import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
// import "src/vaults/VaultRegistry.sol";
// import "src/interfaces/IVaults.sol";

// import "./utils/FlashBorower.sol";

// // import "src/interactions/Deposit.sol";

// contract VaultRegistryTest is Test {
//     VaultRegistry vaultRegistry;

//     ERC20PresetMinterPauser testToken;

//     function setUp() public {
//         vm.startPrank(address(8953626958234137847422389523978938749873));

//         vaultRegistry = new VaultRegistry();
//         testToken = new ERC20PresetMinterPauser("TestToken", "TT");

//         testToken.mint(
//             address(8953626958234137847422389523978938749873),
//             1_000_000 * 10**18
//         );

//         vm.deal(address(8953626958234137847422389523978938749873), 5 * 10**18);
//     }

//     function testFlashLoan() public {
//         vaultRegistry.addNewAssetVault(address(testToken));

//         address vaultAddress = vaultRegistry.getAssetVaultAddress(
//             address(testToken)
//         );

//         testToken.transfer(vaultAddress, 1_000_000 * 10**18);

//         IAssetVault assetVault = IAssetVault(vaultAddress);

//         // uint256 withdrawableAmount1 = assetVault.getWithdrawableAmount(
//         //     address(8953626958234137847422389523978938749873)
//         // );

//         // assetVault.increaseWithdrawableAmount(
//         //     address(8953626958234137847422389523978938749873),
//         //     address(testToken),
//         //     100 * 10**18
//         // );

//         // uint256 withdrawableAmount2 = assetVault.getWithdrawableAmount(
//         //     address(8953626958234137847422389523978938749873)
//         // );

//         // assert(withdrawableAmount1 == 0);
//         // assert(withdrawableAmount2 == 100 * 10**18);

//         FlashBorrower borower = new FlashBorrower(vaultAddress);

//         borower.flashBorrow(address(testToken), 1_000_000 * 10**18);
//     }
// }
