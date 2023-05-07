%lang starknet

@contract_interface
namespace IAccount {
    func getPublicKey() -> (publicKey: felt) {
    }

    func supportsInterface(interfaceId: felt) -> (success: felt) {
    }

    //
    // Setters
    //

    func setPublicKey(newPublicKey: felt) {
    }
}
