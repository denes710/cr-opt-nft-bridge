import pytest

from brownie import accounts, reverts, WrappedERC721

@pytest.fixture
def wrapped_contract():
    return accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

def test_minting(wrapped_contract):
    wrapped_contract.mint(accounts[1], 1, {'from': accounts[0]})
    assert wrapped_contract.ownerOf(1) == accounts[1]

def test_burning(wrapped_contract):
    wrapped_contract.mint(accounts[1], 1, {'from': accounts[0]})
    wrapped_contract.burn(1, {'from': accounts[0]})

    with reverts("ERC721: invalid token ID"):
        wrapped_contract.ownerOf(1)

def test_minting_not_only(wrapped_contract):
    with reverts("Ownable: caller is not the owner"):
        wrapped_contract.mint(accounts[1], 1, {'from': accounts[1]})

def test_burning_not_only(wrapped_contract):
    with reverts("Ownable: caller is not the owner"):
        wrapped_contract.burn(1, {'from': accounts[1]})