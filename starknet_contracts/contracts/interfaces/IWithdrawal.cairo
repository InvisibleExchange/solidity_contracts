%lang starknet

@contract_interface
namespace IDataSource {
    func register_address(stark_key: felt) {
    }
    func deposit_ERC20(deposit_id: felt, token: felt, deposit_amount: felt) {
    }
    func deposit_ETH() -> (depositId: felt) {
    }
    func cancel_deposit() -> (deposit_id: felt) {
    }
}
