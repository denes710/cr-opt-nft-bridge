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

    # 4 nft/transaction per block
    srcSpokeBridge = accounts[0].deploy(SimpleGatewaySrcSpokeBrdige, contractMap, hub, 4, Wei("0.01 ether"))

    for i in range(1, 10):
        erc721.mint(accounts[1], i, {'from': accounts[0]})
        erc721.approve(srcSpokeBridge.address, i, {'from': accounts[1]})

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

def test_user_adding_transaction(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]

    with reverts("ERC721: transfer from incorrect owner"):
        srcSpokeBridge.addNewTransactionToBlock(receiver, 1, erc721.address, {'from': person})

    srcSpokeBridge.addNewTransactionToBlock(receiver, 1, erc721.address, {'from': user})

    assert erc721.ownerOf(1) == srcSpokeBridge.address
# FIXME hashing the result is necessary
#    retBid = srcSpokeBridge.getLocalTransaction(0, 0)
#    assert retBid["maker"] == user
#    assert retBid["receiver"] == receiver
#    assert retBid["localErc721Contract"] == erc721.address

def test_new_block(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    assert srcSpokeBridge.localBlockId() == 1

    # it will be on the new block
    srcSpokeBridge.addNewTransactionToBlock(receiver, 5, erc721.address, {'from': user})

def test_relayer_relaying(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    with reverts("SpokeBridge: caller is not a relayer!"):
        srcSpokeBridge.addIncomingBlock(transaction_root, {'from': person})

    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    incomingBlock = srcSpokeBridge.incomingBlocks(0)
    assert transaction_root == incomingBlock["transactionRoot"]
    assert 1 == incomingBlock["status"]
    assert relayer == incomingBlock["relayer"]

def test_user_claiming_nft(init_contracts):
    srcSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()
    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]

    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    with reverts("SrcSpokeBridge: there is no enough fee for relayers!"):
        srcSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver})

    with reverts("SrcSpokeBridge: the challenging period is not expired yet!"):
        srcSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    chain.sleep(14400000) # it's 4 hours

    with reverts("SrcSpokeBridge: proof is not correct during claming!"):
        srcSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    with reverts("SrcSpokeBridge: receiver is not the message sender!"):
        srcSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': user, 'amount': Wei("0.01 ether")})

    prev_balance = relayer.balance()
    srcSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})
    assert prev_balance + Wei("0.01 ether") == relayer.balance()

    with reverts("SrcSpokeBridge: token is already claimed!"):
        srcSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    assert erc721.ownerOf(2) == receiver