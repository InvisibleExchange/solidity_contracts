from copyreg import constructor
import math
from secrets import token_urlsafe
from sre_parse import State
import pytest
import asyncio
import json



from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.services.api.contract_class import ContractClass
from starkware.crypto.signature.signature import (
    pedersen_hash, private_to_stark_key, sign, get_random_private_key)

P = 2**251 + 17*2**192 + 1

from nile.signer import Signer
from nile.utils import  to_uint, add_uint, str_to_felt, MAX_UINT256

owner = Signer(8932749863246329746327463249328632)

# acc_path = "contracts/openzeppelin/account/presets/Account.cairo"
# ============   ============   ============   ==============
file_path = "tests/program_output.json"
f = open(file_path, 'r')
program_output = json.load(f)
program_output = [P + int(x) if x.startswith("-") else int(x) for x in program_output]
f.close()

# ============   ============   ============   ==============


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def contract_factory():
    starknet = await Starknet.empty()

    parse_contract = await starknet.deploy(
        "./contracts/helpers/parse_program_output.cairo",
    )
    
    # owner_acc = await starknet.deploy(
    #     acc_path,
    #     constructor_calldata=[owner.public_key]
    # )
    

    return starknet, parse_contract



@pytest.mark.asyncio
async def test_main_logic(contract_factory):
    starknet, parse_contract = contract_factory
    
    res = await parse_contract.parse_program_output(program_output).call()
   
    for dep in res.result.deposits:
        dep_res = await parse_contract.uncompress_deposit_output(dep).call()
   
        print(dep_res.result)
    
    for wit in res.result.withdrawals:
        wit_res = await parse_contract.uncompress_withdrawal_output(wit).call()
        
        print(wit_res.result)
   



@pytest.mark.asyncio
async def test_withdrawals(contract_factory):
    starknet, parse_contract = contract_factory
    
    withdraw_contract = await starknet.deploy(
        "contracts/interactions/withdrawal.cairo",
    )

    res = await parse_contract.parse_program_output(program_output).call()
   
    print(res.result.withdrawals)
   
    await withdraw_contract.register_token_proxy(12345, 6).execute()
    
    res = await withdraw_contract.store_new_batch_withdrawal_outputs(res.result.withdrawals).execute()
    
        
    stark_key = 2325812664550263468000998649484612106203340046325053037275531176882642416349
    res = await withdraw_contract.get_withdrawable_amount(stark_key, 12345).call()
    
    print("withdrawable_amount: ", res.result)
    
    await withdraw_contract.make_withdrawal(12345).execute() 
    

    res2 = await withdraw_contract.get_withdrawable_amount(stark_key, 12345).call()
    
    print("withdrawable_amount after: ", res2.result)



@pytest.mark.asyncio
async def test_deposits(contract_factory):
    starknet, parse_contract = contract_factory

    res = await parse_contract.parse_program_output(program_output).call()
    
    deposit_contract = await starknet.deploy(
        "./contracts/interactions/deposits.cairo",
    )
   
    await deposit_contract.register_token_proxy(12345, 6).execute()

    token_addr = await deposit_contract.get_token_address_proxy(1).call()
    assert token_addr.result.res == 12345
    token_decimals = await deposit_contract.get_token_decimals_proxy(1).call()
    assert token_decimals.result.res == 6

    await deposit_contract.make_deposit(12345, 1_000_000 * 10**6 * 10**6).execute()
        
    stark_key = 2325812664550263468000998649484612106203340046325053037275531176882642416349
    
    amount = await deposit_contract.get_pending_deposit_amount(stark_key, 12345).call()
    assert amount.result.deposit_amount == 1_000_000_000_000_000_000
    
    await deposit_contract.update_pending_deposits([res.result.deposits[0]]).execute()
    
    amount = await deposit_contract.get_pending_deposit_amount(stark_key, 12345).call()
    assert amount.result.deposit_amount == 0
    
    print("All good")


@pytest.mark.asyncio
async def test_full_cycle(contract_factory):
    starknet, parse_contract = contract_factory

    res = await parse_contract.parse_program_output(program_output).call()
    
    interactions_contract = await starknet.deploy(
        "./contracts/interactions/interactions.cairo",
    )
    
    # & The flow: 
    # 1: Register tokens
    # 2: Make deposits
    # 3: everything else happens offchain
    # 4: Settle a batch of transacations and update the onchain State
    # -Remove the pending deposits and add withdrawals to the pending withdrawal
    # 5: Make withdrawals
    
    await parse_contract.register_token_proxy(12345, 6).call()
    await parse_contract.register_token_proxy(54321, 6).call()
    
    
    




@pytest.mark.asyncio
async def test_ERC20(contract_factory):
    starknet, parse_contract = contract_factory

    owner = 2325812664550263468000998649484612106203340046325053037275531176882642416349
    erc20 = await starknet.deploy(
        "contracts/openzeppelin/token/erc20/presets/ERC20Mintable.cairo",
        constructor_calldata=[
            str_to_felt("Wrapped Ether"),
            str_to_felt("WETH"),
            18,
            *to_uint(10**6),
            owner,
            owner
        ]
    )
    
    
    supply = await erc20.totalSupply().call()
    decimals = await erc20.decimals().call()
    name = await erc20.name().call()
    
    print("supply: ", supply.result)
    print("decimals: ", decimals.result)
    print("name: ", name.result)

        
    bal = await erc20.balanceOf(owner).call()
    print("balance before: ", bal.result)
    
    bal = await erc20.mint(owner, to_uint(10**6)).execute()
    
    bal = await erc20.balanceOf(owner).call()
    print("balance after: ", bal.result)
    
    
    
    

    
    
    
    
    
    
    
    
    
    



