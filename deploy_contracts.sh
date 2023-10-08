

forge create --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   invisible_solidity/src/TestToken.sol:TestToken --constructor-args "Test Usdc" "USDC"
forge create --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   invisible_solidity/src/TestToken.sol:TestToken --constructor-args "Test Wrapped BTC" "WBTC"

forge create --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 invisible_solidity/src/InvisibleL1.sol:InvisibleL1 --constructor-args 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266


cast send --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://127.0.0.1:8545/ 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "registerToken(address,uint32,uint8)" 0x5FbDB2315678afecb367f032d93F642f64180aa3 55555 6
cast send --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://127.0.0.1:8545/ 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "registerToken(address,uint32,uint8)" 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 12345 8

