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

    # 4 nft/transaction per block
    srcSpokeBridge = accounts[0].deploy(SimpleGatewaySrcSpokeBrdige, contractMap, hub, 4, Wei("0.01 ether"))
    dstSpokeBridge = accounts[0].deploy(SimpleGatewayDstSpokeBrdige, hub, 4, Wei("0.01 ether"))

    hub.addSpokeBridge(srcSpokeBridge.address, dstSpokeBridge.address, {'from': accounts[0]})

    # for adding to a block
    for i in range(1, 10):
        erc721.mint(accounts[1], i, {'from': accounts[0]})
        erc721.approve(srcSpokeBridge.address, i, {'from': accounts[1]})

    # for adding to a block, but it could conflict with the incoming ones
    for i in range(10, 20):
        wrappedErc721.mint(accounts[3], i, {'from': accounts[0]})
        wrappedErc721.approve(wrappedErc721.address, i, {'from': accounts[3]})

    wrappedErc721.transferOwnership(dstSpokeBridge.address)
    return srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721

def test_one_token_briging_circle_without_challenge(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    person = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    null_address = "0x0000000000000000000000000000000000000000"

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    # create a block
    for i in range(1, 5):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for relayer for dst
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()
    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [2, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    chain.sleep(14400000) # it's 4 hours

    wrappedErc721.approve(dstSpokeBridge.address, 2, {'from': receiver})
    dstSpokeBridge.addNewTransactionToBlock(user, 2, wrappedErc721.address, {'from': receiver})

    for i in range(10, 15):
        wrappedErc721.approve(dstSpokeBridge.address, i, {'from': receiver})
        dstSpokeBridge.addNewTransactionToBlock(user, i, wrappedErc721.address, {'from': receiver})

    dstSpokeBridge.calculateTransactionHashes(0)
    transaction_root = dstSpokeBridge.getRoot()
    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    chain.sleep(14400000) # it's 4 hours

    proof = [dstSpokeBridge.hashes(1), dstSpokeBridge.hashes(5)]
    srcSpokeBridge.claimNFT(0, [2, receiver, user, null_address, wrappedErc721.address], proof, 0, {'from': user, 'amount': Wei("0.01 ether")})

def test_challenge_on_dst_side_then_restore(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]
    new_relayer = accounts[5]

    null_address = "0x0000000000000000000000000000000000000000"

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    srcSpokeBridge.deposite({'from': new_relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': new_relayer, 'amount': Wei("20 ether")})

    # create block 0, 1 on src
    for i in range(1, 9):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for block 1 on src
    srcSpokeBridge.calculateTransactionHashes(1)
    transaction_root_block_one = srcSpokeBridge.getRoot()

    dstSpokeBridge.addIncomingBlock(transaction_root_block_one, {'from': relayer})

    # proof for id 5
    proof = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [5, user, receiver, erc721.address, wrappedErc721.address], proof, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    # it is challenge period
    dstSpokeBridge.challengeIncomingBlock(0, {'from': challenger, 'amount': Wei("10 ether")})

    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]
    with reverts("SpokeBridge: bridge is not active!"):
        dstSpokeBridge.claimNFT(0, [6, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': receiver, 'amount': Wei("0.01 ether")})

    assert dstSpokeBridge.incomingBlocks(0)["status"] == 2
    assert dstSpokeBridge.relayers(relayer)["againstChallenges"] == (1,)
    assert dstSpokeBridge.relayers(relayer)["status"] == 3
    assert dstSpokeBridge.firstMaliciousBlockHeight() == 0
    assert dstSpokeBridge.numberOfChallenges() == 1
    assert dstSpokeBridge.status() == 1

    srcSpokeBridge.sendProof(0)

    # check members
    assert dstSpokeBridge.incomingBlocks(0)["status"] == 3
    assert dstSpokeBridge.relayers(relayer)["againstChallenges"] == (0,)
    assert dstSpokeBridge.relayers(relayer)["status"] == 4
    assert dstSpokeBridge.firstMaliciousBlockHeight() == 0
    assert dstSpokeBridge.numberOfChallenges() == 0
    assert dstSpokeBridge.status() == 2

    # restore
    dstSpokeBridge.restore()
    assert dstSpokeBridge.status() == 0

    # relaying again
    # block 0
    # calculate a valid root for block 0 on src
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    with reverts("SpokeBridge: caller is not a relayer!"):
        dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': new_relayer})

    # proof for id 1
    proof = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    # block 1
    # calculate a valid root for block 1 on src
    srcSpokeBridge.calculateTransactionHashes(1)
    transaction_root = srcSpokeBridge.getRoot()

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': new_relayer})

    # proof for id 5
    proof = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(1, [5, user, receiver, erc721.address, wrappedErc721.address], proof, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    assert dstSpokeBridge.relayers(relayer)["status"] == 4

    # check reward claming
    prev_balance = challenger.balance()
    dstSpokeBridge.claimChallengeReward({'from': challenger})
    assert prev_balance + Wei("15 ether") == challenger.balance()

    with reverts("SpokeBridge: there is no reward!"):
        dstSpokeBridge.claimChallengeReward({'from': challenger})
    with reverts("SpokeBridge: there is no reward!"):
        dstSpokeBridge.claimChallengeReward({'from': user})

def test_challenge_on_src_side_then_restore(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]
    new_relayer = accounts[5]

    null_address = "0x0000000000000000000000000000000000000000"

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    srcSpokeBridge.deposite({'from': new_relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': new_relayer, 'amount': Wei("20 ether")})

    # create block 0, 1 on src
    for i in range(1, 9):
        srcSpokeBridge.addNewTransactionToBlock(receiver, i, erc721.address, {'from': user})

    # calculate a valid root for block 0 on src
    srcSpokeBridge.calculateTransactionHashes(0)
    transaction_root = srcSpokeBridge.getRoot()

    dstSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    # proof for id 1
    proof = [srcSpokeBridge.hashes(1), srcSpokeBridge.hashes(5)]
    dstSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 0, {'from': receiver, 'amount': Wei("0.01 ether")})

    # 0 block
    for i in range(10, 14):
        dstSpokeBridge.addNewTransactionToBlock(user, i, wrappedErc721.address, {'from': receiver})

    # 1 block
    wrappedErc721.approve(wrappedErc721.address, 1, {'from': receiver})

    chain.sleep(14400000) # it's 4 hours

    dstSpokeBridge.addNewTransactionToBlock(user, 1, wrappedErc721.address, {'from': receiver})
    for i in range(14, 19):
        dstSpokeBridge.addNewTransactionToBlock(user, i, wrappedErc721.address, {'from': receiver})

    # calculate a valid root for block 1 on dst
    dstSpokeBridge.calculateTransactionHashes(1)
    transaction_root = dstSpokeBridge.getRoot()

    # wrong relaying
    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})

    # it is challenge period
    srcSpokeBridge.challengeIncomingBlock(0, {'from': challenger, 'amount': Wei("10 ether")})

    assert srcSpokeBridge.incomingBlocks(0)["status"] == 2
    assert srcSpokeBridge.relayers(relayer)["againstChallenges"] == (1,)
    assert srcSpokeBridge.relayers(relayer)["status"] == 3
    assert srcSpokeBridge.firstMaliciousBlockHeight() == 0
    assert srcSpokeBridge.numberOfChallenges() == 1
    assert srcSpokeBridge.status() == 1

    proof = [srcSpokeBridge.hashes(0), srcSpokeBridge.hashes(5)]
    with reverts("SpokeBridge: bridge is not active!"):
        srcSpokeBridge.claimNFT(0, [1, user, receiver, erc721.address, wrappedErc721.address], proof, 1, {'from': user, 'amount': Wei("0.01 ether")})

    dstSpokeBridge.sendProof(0)

    # check members
    assert srcSpokeBridge.incomingBlocks(0)["status"] == 3
    assert srcSpokeBridge.relayers(relayer)["againstChallenges"] == (0,)
    assert srcSpokeBridge.relayers(relayer)["status"] == 4
    assert srcSpokeBridge.firstMaliciousBlockHeight() == 0
    assert srcSpokeBridge.numberOfChallenges() == 0
    assert srcSpokeBridge.status() == 2

    # restore
    srcSpokeBridge.restore()
    assert srcSpokeBridge.status() == 0

    # relaying again
    # block 0
    # calculate a valid root for block 0 on src
    dstSpokeBridge.calculateTransactionHashes(0)
    transaction_root = dstSpokeBridge.getRoot()

    with reverts("SpokeBridge: caller is not a relayer!"):
        srcSpokeBridge.addIncomingBlock(transaction_root, {'from': relayer})
    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': new_relayer})

    # block 1
    # calculate a valid root for block 1 on src
    dstSpokeBridge.calculateTransactionHashes(1)
    transaction_root = dstSpokeBridge.getRoot()

    srcSpokeBridge.addIncomingBlock(transaction_root, {'from': new_relayer})

    chain.sleep(14400000) # it's 4 hours

    # proof for id 1
    proof = [dstSpokeBridge.hashes(1), dstSpokeBridge.hashes(5)]
    srcSpokeBridge.claimNFT(1, [1, receiver, user, null_address, wrappedErc721.address], proof, 0, {'from': user, 'amount': Wei("0.01 ether")})

    assert srcSpokeBridge.relayers(relayer)["status"] == 4

    # check reward claming
    prev_balance = challenger.balance()
    srcSpokeBridge.claimChallengeReward({'from': challenger})
    assert prev_balance + Wei("15 ether") == challenger.balance()

    with reverts("SpokeBridge: there is no reward!"):
        srcSpokeBridge.claimChallengeReward({'from': challenger})
    with reverts("SpokeBridge: there is no reward!"):
        srcSpokeBridge.claimChallengeReward({'from': user})
