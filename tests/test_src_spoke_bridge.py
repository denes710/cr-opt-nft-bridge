import pytest

from brownie import accounts, reverts, Wei, chain
from brownie import WrappedERC721, ContractMap, SimpleGatewaySrcSpokeBrdige, SimpleGatewayHub

@pytest.fixture
def init_contracts():
    erc721 = accounts[0].deploy(WrappedERC721, "ValueNFT", "NFT")
    wrappedErc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

    contractMap = accounts[0].deploy(ContractMap)
    contractMap.addPair(erc721.address, wrappedErc721.address)

    hub = accounts[0].deploy(SimpleGatewayHub)

    srcSpokeBridge = accounts[0].deploy(SimpleGatewaySrcSpokeBrdige, hub, contractMap)
    erc721.mint(accounts[1], 1, {'from': accounts[0]})
    erc721.approve(srcSpokeBridge.address, 1, {'from': accounts[1]})

    return srcSpokeBridge, contractMap, erc721, wrappedErc721

def test_relayer_depositing(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    relayer = accounts[2]

    prev_relayer_balance = relayer.balance()
    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    assert prev_relayer_balance == relayer.balance() + Wei("20 ether")

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_relayer_undepositing(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    relayer = accounts[2]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    with reverts("SpokeBridge: caller cannot be a relayer!"):
        srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    prev_relayer_balance = relayer.balance()

    srcSpokeBridge.undeposite({'from': relayer})
    with reverts("SpokeBridge: 2 days is not expired from the undepositing!"):
        srcSpokeBridge.claimDeposite({'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    srcSpokeBridge.claimDeposite({'from': relayer})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 0

    assert prev_relayer_balance + Wei("20 ether") == relayer.balance()

def test_user_creating_bid(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]

    with reverts("SrcSpokeBridge: there is no fee for relayers!"):
        srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user})
    with reverts("ERC721: transfer from incorrect owner"):
        srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': person, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})

    transaction = [1, user, receiver, erc721.address, wrappedErc721.address]
    transactionHash = srcSpokeBridge.getTransactionHash(transaction)

    retBid = srcSpokeBridge.outgoingBids(0)
    assert retBid["status"] == 1
    assert retBid["hashedTransaction"] == transactionHash

def test_relayer_buying_bid(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})

    with reverts("SpokeBridge: caller is not a relayer!"):
        srcSpokeBridge.buyBid(0, {'from': person})

    prev_relayer_balance = relayer.balance()
    srcSpokeBridge.buyBid(0, {'from': relayer})
    assert prev_relayer_balance + Wei("0.01 ether") == relayer.balance()

    with reverts("SpokeBridge: bid does not have Created state"):
        srcSpokeBridge.buyBid(0, {'from': relayer})

    retBid = srcSpokeBridge.outgoingBids(0)
    assert retBid["status"] == 2
    assert retBid["relayer"] == relayer

def test_relayer_relaying(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    transaction = [1, user, receiver, erc721.address, wrappedErc721.address]
    transactionHash = srcSpokeBridge.getTransactionHash(transaction)

    chain.sleep(14400000) # it's 4 hours

    with reverts("SpokeBridge: caller is not a relayer!"):
        srcSpokeBridge.addIncomingBid(0, transactionHash, transaction, {'from': person});

    srcSpokeBridge.addIncomingBid(0, transactionHash, transaction, {'from': relayer});

    with reverts("SrcSpokeBridge: there is an incoming bid with the same id!"):
        srcSpokeBridge.addIncomingBid(0, transactionHash, transaction, {'from': relayer});

    retBid = srcSpokeBridge.incomingBids(0)
    assert retBid["status"] == 1
    assert retBid["hashedTransaction"] == transactionHash
    assert retBid["relayer"] == relayer

def test_user_claiming_nft(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    transaction = [1, receiver, user, erc721.address, wrappedErc721.address]
    transactionHash = srcSpokeBridge.getTransactionHash(transaction)

    srcSpokeBridge.addIncomingBid(0, transactionHash, transaction, {'from': relayer});

    with reverts("SrcSpokeBride: incoming bid has no Relayed state!"):
        srcSpokeBridge.claimNFT(1, transaction, {'from': user})
    with reverts("SrcSpokeBridge: the challenging period is not expired yet!"):
        srcSpokeBridge.claimNFT(0, transaction, {'from': user})

    chain.sleep(14400000) # it's 4 hours

    with reverts("SrcSpokeBridge: claimer is not the owner!"):
        srcSpokeBridge.claimNFT(0, transaction, {'from': relayer})

    srcSpokeBridge.claimNFT(0, transaction, {'from': user})
    assert erc721.ownerOf(1) == user