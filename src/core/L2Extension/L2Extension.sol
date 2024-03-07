// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.22;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import "../../interfaces/IStargateRouter.sol";

// // * DEPOSIT FLOW:
// // * 1. User makes a deposit on the L2 Extension
// // * 2. The Deposit and funds are sent to a main L2(Arbitrum?)
// // * 3. The main L2 handlews the deposit as any other deposit

// struct DepositMessage {
//     address tokenAddress;
//     uint256 amount;
//     uint256 starkKey;
// }

// contract L2InvisibleExtension {

//     uint32 immutable s_destId; 
//     address immutable s_stargateRouterETH;
//     address immutable s_stargateRouter;
//     address immutable s_peer;
//     address immutable s_ethAddress;

//     constructor(
//         address _stargateRouterETH,
//         address _stargateRouter,
//         uint32 _destId,
//         address _peer,
//         address _ethAddress
//     )  {
//         s_stargateRouterETH = _stargateRouterETH;
//         s_stargateRouter = _stargateRouter;
//         s_destId = _destId;
//         s_peer = _peer;
//         s_ethAddress = _ethAddress;
//     }

//     /* @dev Used to send the deposit message and funds to the main L2
//      */
//     function makeDeposit(
//         address tokenAddress,
//         uint256 amount,
//         uint256 starkKey
//     )
//         external
//         payable
//     {

//         // TODO: Only allow registered tokens to be deposited

//         DepositMessage memory deposit = DepositMessage(
//             tokenAddress,
//             amount,
//             starkKey
//         );

//         bytes memory _payload = abi.encode(deposit);

//         uint256 minAmountOut = (amount * 999) / 1000; // 0.1% slippage
//         if (tokenAddress == s_ethAddress) {
//                 IStargateRouterETH(s_stargateRouterETH).swapETHAndCall{value:msg.value}(
//                     uint16(s_destId),                                       
//                     payable(msg.sender),         
//                     abi.encodePacked(s_peer),                 
//                     IStargateRouterETH.SwapAmount(amount, minAmountOut),                         
//                     IStargateRouterETH.lzTxObj(0, 0, "0x"),  
//                     _payload                         
//                 );

//         } else {
//             IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);

//             IStargateRouter(s_stargateRouter).swap{value:msg.value}(
//                 uint16(s_destId),           
//                 1,                   
//                 1,                                 
//                 payable(msg.sender),        
//                 amount,                     
//                 minAmountOut,                    
//                 IStargateRouter.lzTxObj(0, 0, "0x"),  
//                 abi.encodePacked(s_peer),       
//                 _payload                         
//             );
//         }
//     }
// }
