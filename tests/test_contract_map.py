import pytest

from brownie import accounts, reverts, ContractMap, WrappedERC721

@pytest.fixture
def init_contracts():
    erc721 = accounts[0].deploy(WrappedERC721, "ValueNFT", "NFT")
    wrapped_erc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")    
    contract_map = accounts[0].deploy(ContractMap)
    return contract_map, erc721.address, wrapped_erc721.address

def test_add_pair(init_contracts):
    contract_map, localAddr, remoteAddr = init_contracts
    contract_map.addPair(localAddr, remoteAddr, {'from': accounts[0]})
    assert contract_map.getRemote(localAddr) == remoteAddr
    assert contract_map.getLocal(remoteAddr) == localAddr

def test_not_owner_add_pair(init_contracts):
    contract_map, localAddr, remoteAddr = init_contracts
    with reverts("Ownable: caller is not the owner"):
        contract_map.addPair(localAddr, remoteAddr, {'from': accounts[1]})

def test_add_exist_addr(init_contracts):
    contract_map, localAddr, remoteAddr = init_contracts
    contract_map.addPair(localAddr, remoteAddr, {'from': accounts[0]})

    with reverts("ContractMap: addr is already in the localToRemote!"):
        contract_map.addPair(localAddr, remoteAddr, {'from': accounts[0]})

    new_wrapped_erc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")    

    with reverts("ContractMap: addr is already in the remoteToLocal!"):
        contract_map.addPair(new_wrapped_erc721.address, remoteAddr, {'from': accounts[0]})