import pytest

from brownie import accounts, reverts, Wei, chain
from brownie import WrappedERC721, SimpleGatewayDstSpokeBrdige, SimpleGatewayHub

@pytest.fixture
def init_contracts():
    wrappedErc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

    hub = accounts[0].deploy(SimpleGatewayHub)

    dstSpokeBridge = accounts[0].deploy(SimpleGatewayDstSpokeBrdige, hub, 4, Wei("0.01 ether"))

    for i in range(1, 10):
        wrappedErc721.mint(accounts[1], i, {'from': accounts[0]})
        wrappedErc721.approve(dstSpokeBridge.address, i, {'from': accounts[1]})

    wrappedErc721.transferOwnership(dstSpokeBridge.address)

    return dstSpokeBridge, wrappedErc721

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

    for i in range(1, 5):
        dstSpokeBridge.addNewTransactionToBlock(receiver, i, wrappedErc721.address, {'from': user})

    # calculate a valid root
    dstSpokeBridge.calculateTransactionHashes(0)
    transaction_root = dstSpokeBridge.getRoot()

    with reverts("SpokeBridge: caller is not a relayer!"):
        dstSpokeBridge.addIncomingBlock(transaction_root, {'from': person})

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    incomingBlock = dstSpokeBridge.incomingBlocks(0)
    assert transaction_root == incomingBlock["transactionRoot"]
    assert 1 == incomingBlock["status"]
    assert relayer == incomingBlock["relayer"]

def test_user_claiming_nft(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    null_address = "0x0000000000000000000000000000000000000000"

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    for i in range(1, 5):
        dstSpokeBridge.addNewTransactionToBlock(receiver, i, wrappedErc721.address, {'from': user})

    # calculate a valid root
    dstSpokeBridge.calculateTransactionHashes(0)
    transaction_root = dstSpokeBridge.getRoot()
    proof = [dstSpokeBridge.hashes(0), dstSpokeBridge.hashes(5)]

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    with reverts("DstSpokeBridge: there is no enough fee for relayers!"):
        dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver})

    with reverts("DstSpokeBridge: proof is not correct during claming!"):
        dstSpokeBridge.claimNFT(0, [1, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    with reverts("DstSpokeBridge: receiver is not the message sender!"):
        dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': user, 'amount': Wei("0.01 ether")})

    prev_balance = relayer.balance()
    dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})
    assert prev_balance + Wei("0.01 ether") == relayer.balance()

#   if we want to fast access
#    with reverts("DstSpokeBridge: token is already claimed!"):
#        dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    assert wrappedErc721.ownerOf(2) == receiver

def test_user_adding_transaction(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    null_address = "0x0000000000000000000000000000000000000000"

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    with reverts("DstSpokeBridge: owner is not the caller!"):
        dstSpokeBridge.addNewTransactionToBlock(user, 1, wrappedErc721.address, {'from': person})

    for i in range(1, 5):
        dstSpokeBridge.addNewTransactionToBlock(receiver, i, wrappedErc721.address, {'from': user})

    dstSpokeBridge.calculateTransactionHashes(0)
    transaction_root = dstSpokeBridge.getRoot()
    proof = [dstSpokeBridge.hashes(0), dstSpokeBridge.hashes(5)]

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    with reverts("DesSpokeBridge: challenging time window is not expired yet!"):
        dstSpokeBridge.addNewTransactionToBlock(user, 2, wrappedErc721.address, {'from': receiver})

    chain.sleep(14400000) # it's 4 hours

    dstSpokeBridge.addNewTransactionToBlock(user, 2, wrappedErc721.address, {'from': receiver})

    # burned
    with reverts("ERC721: invalid token ID"):
        wrappedErc721.ownerOf(2)

    retBid = dstSpokeBridge.getLocalTransaction(0, 0)
    assert retBid["maker"] == user
    assert retBid["receiver"] == receiver
    assert retBid["remoteErc721Contract"] == wrappedErc721.address

def test_new_block(init_contracts):
    dstSpokeBridge, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    for i in range(1, 5):
        dstSpokeBridge.addNewTransactionToBlock(receiver, i, wrappedErc721.address, {'from': user})

    assert dstSpokeBridge.localBlockId() == 1

    # it will be on the new block
    dstSpokeBridge.addNewTransactionToBlock(receiver, 5, wrappedErc721.address, {'from': user})
