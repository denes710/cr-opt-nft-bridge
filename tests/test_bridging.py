import pytest

from brownie import accounts, reverts, Wei, chain
from brownie import WrappedERC721, ContractMap
from brownie import SimpleGatewaySrcSpokeBrdige, SimpleGatewayHub, SimpleGatewayDstSpokeBrdige

@pytest.fixture
def init_contracts():
    erc721 = accounts[0].deploy(WrappedERC721, "ValueNFT", "NFT")
    wrappedErc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

    contractMap = accounts[0].deploy(ContractMap)
    contractMap.addPair(erc721.address, wrappedErc721.address)

    hub = accounts[0].deploy(SimpleGatewayHub)

    srcSpokeBridge = accounts[0].deploy(SimpleGatewaySrcSpokeBrdige, hub, contractMap)
    dstSpokeBridge = accounts[0].deploy(SimpleGatewayDstSpokeBrdige, hub)

    hub.addSpokeBridge(srcSpokeBridge.address, dstSpokeBridge.address, {'from': accounts[0]})

    erc721.mint(accounts[1], 1, {'from': accounts[0]})
    erc721.approve(srcSpokeBridge.address, 1, {'from': accounts[1]})

    wrappedErc721.transferOwnership(dstSpokeBridge.address)

    return srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721

def test_one_token_briging_circle(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})
    dstSpokeBridge.buyBid(0, {'from': relayer})

    srcSpokeBridge.unlocking(0, 0, user, 1, wrappedErc721.address, {'from': relayer});

def test_challenge_on_source_during_locking(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    # no relaying
    chain.sleep(14400000) # it's 4 hours

    # sending the proof of # id incoming message
    dstSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4

def test_challenge_on_dest_during_burning(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})
    dstSpokeBridge.buyBid(0, {'from': relayer})

    # FIXME maybe it is neeeded chain.sleep(14400000) # it's 4 hours

    # sending the proof of # id incoming message
    srcSpokeBridge.sendProof(False, 0, {'from': challenger})

    # FIXME more check - relayer - challenger money
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4

def test_challenge_on_source_during_unlocking(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # locked NFT
    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    # wrong relaying
    srcSpokeBridge.unlocking(0, 0, relayer, 1, wrappedErc721.address, {'from': relayer});

    # challenging
    srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    # FIXME it is problematic, because it is working with "False as well"
    dstSpokeBridge.sendProof(True, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4

def test_challenge_on_dest_during_minting(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # wrong relaying
    dstSpokeBridge.minting(0, relayer, 1, wrappedErc721.address, {'from': relayer})

    # challenging
    dstSpokeBridge.challengeMinting(0, {'from': challenger, 'amount': Wei("10 ether")});
    srcSpokeBridge.sendProof(True, 0, {'from': challenger})

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4