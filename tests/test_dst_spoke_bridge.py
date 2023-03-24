import pytest

from brownie import accounts, reverts, Wei, chain
from brownie import ContractMap, WrappedERC721, SimpleGatewaySrcSpokeBrdige, SimpleGatewayDstSpokeBrdige, SimpleGatewayHub

@pytest.fixture
def init_contracts():
    erc721 = accounts[0].deploy(WrappedERC721, "ValueNFT", "NFT")
    wrappedErc721 = accounts[0].deploy(WrappedERC721, "Wrapped", "WRP")

    contractMap = accounts[0].deploy(ContractMap)
    contractMap.addPair(erc721.address, wrappedErc721.address)

    hub = accounts[0].deploy(SimpleGatewayHub)

    srcSpokeBridge = accounts[0].deploy(SimpleGatewaySrcSpokeBrdige, contractMap, hub, 4, Wei("0.01 ether"))
    dstSpokeBridge = accounts[0].deploy(SimpleGatewayDstSpokeBrdige, hub, 4, Wei("0.01 ether"))

    # for adding to a block
    for i in range(1, 10):
        erc721.mint(accounts[1], i, {'from': accounts[0]})
        erc721.approve(srcSpokeBridge.address, i, {'from': accounts[1]})

    wrappedErc721.transferOwnership(dstSpokeBridge.address)

    return dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721

def test_relayer_depositing(init_contracts):
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

    relayer = accounts[2]

    prev_relayer_balance = relayer.balance()
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    assert prev_relayer_balance == relayer.balance() + Wei("20 ether")

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_relayer_undepositing(init_contracts):
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

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
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    # creating valid incoming root for dst from src
    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for relayer for dst
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    with reverts("SpokeBridge: caller is not a relayer!"):
        dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    incomingBlock = dstSpokeBridge.incomingBlocks(0)
    assert transaction_root == incomingBlock["transactionRoot"]
    assert 1 == incomingBlock["status"]
    assert relayer == incomingBlock["relayer"]

def test_user_claiming_nft(init_contracts):
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # creating valid incoming root for dst from src
    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for relayer for dst
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]

    with reverts("DstSpokeBridge: there is no enough fee for relayers!"):
        dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver})

    with reverts("DstSpokeBridge: incoming block has no Relayed state!"):
        dstSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    with reverts("DstSpokeBridge: proof is not correct during claming!"):
        dstSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    with reverts("DstSpokeBridge: receiver is not the message sender!"):
        dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': user, 'amount': Wei("0.01 ether")})

    prev_balance = relayer.balance()
    dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})
    assert prev_balance + Wei("0.01 ether") == relayer.balance()

#   if we want to fast access
#    with reverts("DstSpokeBridge: token is already claimed!"):
#        dstSpokeBridge.claimNFT(0, [2, user, receiver, null_address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    assert wrappedErc721.ownerOf(2) == receiver

def test_user_adding_transaction(init_contracts):
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # creating valid incoming root for dst from src
    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for relayer for dst
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    wrong_proof = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]

    with reverts("DstSpokeBridge: proof is not correct unwrapping!"):
        dstSpokeBridge.addNewTransactionToBlock(user, 0, [2, user, receiver, erc721.address, wrappedErc721.address], wrong_proof, 1, {'from': person})

    with reverts("DstSpokeBridge: owner is not the caller!"):
        dstSpokeBridge.addNewTransactionToBlock(user, 0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': person})

    with reverts("DesSpokeBridge: challenging time window is not expired yet!"):
        dstSpokeBridge.addNewTransactionToBlock(user, 0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver})

    chain.sleep(14400000) # it's 4 hours

    dstSpokeBridge.addNewTransactionToBlock(user, 0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver})

    # burned
    with reverts("ERC721: invalid token ID"):
        wrappedErc721.ownerOf(2)

# FIXME hashing the result is necessary
#    retBid = dstSpokeBridge.getLocalTransaction(0, 0)
#    assert retBid["maker"] == receiver
#    assert retBid["receiver"] == user
#    assert retBid["remoteErc721Contract"] == wrappedErc721.address

def test_new_block(init_contracts):
    dstSpokeBridge, wrappedErc721, srcSpokeBridge, erc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # creating valid incoming root for dst from src
    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for relayer for dst
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    proof_1 = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof_1, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    proof_2 = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof_2, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    proof_3 = [srcSpokeBridge.hashes(3), srcSpokeBridge.hashes(4)]
    dstSpokeBridge.claimNFT(0, [3, user, receiver, erc721.address, wrappedErc721.address], proof_3, 2, {'from': receiver, 'amount': Wei("0.01 ether")})

    proof_4 = [srcSpokeBridge.hashes(2), srcSpokeBridge.hashes(4)]
    dstSpokeBridge.claimNFT(0, [4, user, receiver, erc721.address, wrappedErc721.address], proof_4, 3, {'from': receiver, 'amount': Wei("0.01 ether")})

    chain.sleep(14400000) # it's 4 hours

    dstSpokeBridge.addNewTransactionToBlock(user, 0, [1, user, receiver, erc721.address, wrappedErc721.address], proof_1, 0, {'from': receiver})
    dstSpokeBridge.addNewTransactionToBlock(user, 0, [2, user, receiver, erc721.address, wrappedErc721.address], proof_2, 1, {'from': receiver})
    dstSpokeBridge.addNewTransactionToBlock(user, 0, [3, user, receiver, erc721.address, wrappedErc721.address], proof_3, 2, {'from': receiver})
    dstSpokeBridge.addNewTransactionToBlock(user, 0, [4, user, receiver, erc721.address, wrappedErc721.address], proof_4, 3, {'from': receiver})

    assert dstSpokeBridge.localBlockId() == 1