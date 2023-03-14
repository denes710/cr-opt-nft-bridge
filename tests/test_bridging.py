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

# FIXME add balance checks for test cases
def test_one_token_briging_circle_without_challenge(init_contracts):
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

    srcSpokeBridge.unlocking(0, 0, user, {'from': relayer});

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

def test_false_challenge_on_source_during_locking(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    # before time window sending the proof of # id incoming message
    with reverts("SrcSpokeBridge: Time window is not expired!"):
        dstSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # relaying
    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    with reverts("DstSpokeBridge: too early to send proof!"):
        dstSpokeBridge.sendProof(False, 0, {'from': challenger})

    # it's 4 hours
    chain.sleep(14400000)
    # after time window sending the proof of # id incoming message
    with reverts("SrcSpokeBridge: False challenging!"):
        dstSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_false_challenge_on_source_during_locking_wrong_proof(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    # sending the proof of # id outgoing message
    with reverts("SrcSpokeBrdige: There is no corresponding local bid!"):
        dstSpokeBridge.sendProof(True, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # no relaying
    chain.sleep(14400000) # it's 4 hours

    # sending the proof of # id outoging message
    with reverts("SrcSpokeBrdige: There is no corresponding local bid!"):
        dstSpokeBridge.sendProof(True, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

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

    # it's 4 hours
    chain.sleep(14400000)

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})
    dstSpokeBridge.buyBid(0, {'from': relayer})

    # it's 4 hours
    chain.sleep(14400000)
    # sending the proof of # id incoming message
    srcSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4

def test_false_challenge_on_dest_during_burning(init_contracts):
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

    # it's 4 hours
    chain.sleep(14400000)

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})
    dstSpokeBridge.buyBid(0, {'from': relayer})

    # before time window sending the proof of # id incoming message
    with reverts("DstSpokeBridge: Time window is not expired!"):
        srcSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # relaying
    srcSpokeBridge.unlocking(0, 0, user, {'from': relayer});

    with reverts("SrcSpokeBridge: too early to send proof!"):
        srcSpokeBridge.sendProof(False, 0, {'from': challenger})

    # it's 4 hours
    chain.sleep(14400000)
    # after time window sending the proof of # id incoming message
    with reverts("DstSpokeBridge: False challenging!"):
        srcSpokeBridge.sendProof(False, 0, {'from': challenger})

    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_false_challenge_on_dest_during_burning_wrong_proof(init_contracts):
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

    # it's 4 hours
    chain.sleep(14400000)

    wrappedErc721.approve(dstSpokeBridge.address, 1, {'from': receiver})

    dstSpokeBridge.createBid(user, 1, wrappedErc721.address, 0, {'from': receiver, 'amount': Wei("0.01 ether")})
    dstSpokeBridge.buyBid(0, {'from': relayer})

    # sending the proof of # id incoming message
    with reverts("DstSpokeBridge: Time window is expired!"):
        srcSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # it's 4 hours
    chain.sleep(14400000)
    # sending the proof of # id incoming message
    with reverts("DstSpokeBridge: Time window is expired!"):
        srcSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

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
    srcSpokeBridge.unlocking(0, 0, relayer, {'from': relayer});

    # challenging
    srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    dstSpokeBridge.sendProof(True, 0, {'from': challenger})

    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 4

def test_false_challenge_on_source_during_unlocking(init_contracts):
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

    # false challenging before relaying
    with reverts("SpokeBridge: Corresponding incoming bid status is not relayed!"):
        srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("SrcSpokeBrdige: There is no corresponding local bid!"):
        dstSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # relaying
    srcSpokeBridge.unlocking(0, 0, user, {'from': relayer});

    chain.sleep(14400000) # it's 4 hours

    # challenging after time window
    with reverts("SpokeBridge: The dispute period is expired!"):
        srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("SrcSpokeBridge: Time window is expired!"):
        dstSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_false_challenge_on_source_during_unlocking_wrong_proof(init_contracts):
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

    # false challenging before relaying
    with reverts("SpokeBridge: Corresponding incoming bid status is not relayed!"):
        srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("SrcSpokeBridge: False challenging!"):
        dstSpokeBridge.sendProof(False, 0, {'from': challenger})
    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    # relaying
    srcSpokeBridge.unlocking(0, 0, user, {'from': relayer});

    chain.sleep(14400000) # it's 4 hours

    # challenging after time window
    with reverts("SpokeBridge: The dispute period is expired!"):
        srcSpokeBridge.challengeUnlocking(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("SrcSpokeBridge: False challenging!"):
        dstSpokeBridge.sendProof(False, 0, {'from': challenger})
    retRelayer = srcSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

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

def test_false_challenge_on_dest_during_minting(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    # challenging
    with reverts("SpokeBridge: Corresponding incoming bid status is not relayed!"):
        dstSpokeBridge.challengeMinting(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("DstSpokeBrdige: There is no corresponding local bid!"):
        srcSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    # challenge period
    chain.sleep(14400000) # it's 4 hours

    # challenging
    with reverts("SpokeBridge: The dispute period is expired!"):
        dstSpokeBridge.challengeMinting(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("DstSpokeBridge: Time window is expired!"):
        srcSpokeBridge.sendProof(True, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

def test_challenge_on_dest_during_minting_wrong_proof(init_contracts):
    srcSpokeBridge, dstSpokeBridge, contractMap, erc721, wrappedErc721 = init_contracts

    user = accounts[1]
    challenger = accounts[2]
    receiver = accounts[3]
    relayer = accounts[4]

    srcSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})
    dstSpokeBridge.deposite({'from': relayer, 'amount': Wei("20 ether")})

    srcSpokeBridge.createBid(receiver, 1, erc721.address, {'from': user, 'amount': Wei("0.01 ether")})
    srcSpokeBridge.buyBid(0, {'from': relayer})

    # challenging
    with reverts("SpokeBridge: Corresponding incoming bid status is not relayed!"):
        dstSpokeBridge.challengeMinting(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("DstSpokeBrdige: There is no corresponding local bid!"):
        srcSpokeBridge.sendProof(False, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1

    dstSpokeBridge.minting(0, receiver, 1, wrappedErc721.address, {'from': relayer})

    # challenge period
    chain.sleep(14400000) # it's 4 hours

    # challenging
    with reverts("SpokeBridge: The dispute period is expired!"):
        dstSpokeBridge.challengeMinting(0, {'from': challenger, 'amount': Wei("10 ether")});
    with reverts("DstSpokeBrdige: There is no corresponding local bid!"):
        srcSpokeBridge.sendProof(False, 0, {'from': challenger})
    retRelayer = dstSpokeBridge.relayers(relayer)
    assert retRelayer["status"] == 1