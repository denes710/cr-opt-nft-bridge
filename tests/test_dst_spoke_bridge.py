import pytest

from brownie import accounts, reverts, Wei, chain
from brownie import WrappedERC721, SimpleGatewayDstSpokeBrdige, SimpleGatewayHub

@pytest.fixture
def init_contracts():
    wrappedErc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

    hub = accounts[0].deploy(SimpleGatewayHub)

    dstSpokeBridge = accounts[0].deploy(SimpleGatewayDstSpokeBrdige, hub)

    wrappedErc721.transferOwnership(dstSpokeBridge.address)

    return dstSpokeBridge, wrappedErc721

# TODO add balance checks for every place where transfer happens
def test_relayer_depositing(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    relayer = accounts[2]

    prev_relayer_balance = relayer.balance()
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    assert prev_relayer_balance == relayer.balance() + Wei("20 ether")

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_relayer_undepositing(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    relayer = accounts[2]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    with reverts("SpokeBridge: caller cannot be a relayer!"):
        dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    prev_relayer_balance = relayer.balance()

    dstSpokeBridge.undeposite({'from': relayer})
    with reverts("SpokeBridge: 2 days is not expired from the undepositing!"):
        dstSpokeBridge.claimDeposite({'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    dstSpokeBridge.claimDeposite({'from': relayer})

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 0

    assert prev_relayer_balance + Wei("20 ether") == relayer.balance()

def test_relayer_relaying(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    retBid = dstSpokeBridge.incomingBids(0)
    assert retBid["status"] == 1
    assert retBid["tokenId"] == 1
    assert retBid["erc721Contract"] == wrappedErc721.address
    assert retBid["receiver"] == receiver
    assert retBid["remoteId"] == 0
    assert retBid["relayer"] == relayer

    assert wrappedErc721.ownerOf(1) == receiver

def test_user_creating_bid(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    with reverts("DstSpokeBridge: there is no fee for relayers!"):
        dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': user})
    with reverts("DstSpokeBridge: too early unwrapping!"):
        dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    chain.sleep(14400000) # it's 4 hours

    with reverts("ERC721: transfer from incorrect owner"):
        dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': user, 'amount': Wei("0.01 ether")})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    # FIXME add checks for members
    retBid = dstSpokeBridge.outgoingBids(0)
    assert retBid["status"] == 1
    assert retBid["receiver"] == user
    assert retBid["tokenId"] == 1

def test_relayer_buying_bid(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})
    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    with reverts("SpokeBridge: caller is not a relayer!"):
        dstSpokeBridge.buyBid(0, {'from': person});

    dstSpokeBridge.buyBid(0, {'from': relayer});

    with reverts("SpokeBridge: bid does not have Created state"):
        dstSpokeBridge.buyBid(0, {'from': relayer});

    retBid = dstSpokeBridge.outgoingBids(0)
    assert retBid["status"] == 2
    assert retBid["buyer"] == relayer