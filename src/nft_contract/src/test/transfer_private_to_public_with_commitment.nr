use crate::NFT;
use crate::test::utils;
use aztec::protocol::address::AztecAddress;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_success() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Transfer NFT with commitment
    let returned_commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Verify ownership transfer
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);
    utils::check_commitment_completer(env, nft_contract_address, returned_commitment, owner);
}

#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_authorized_success() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // Create transfer call interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id, 1);

    // Add authorization witness from owner to proxy
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, transfer_call_interface);

    // Owner calls via proxy using forward_private_4_and_return to capture return value
    let returned_commitment: Field = env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4_and_return(
            transfer_call_interface.target_contract,
            transfer_call_interface.selector,
            transfer_call_interface.args,
        ),
    );

    // Verify ownership transfer
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, recipient, token_id);
    // The caller, not `from`, completes.
    utils::check_commitment_completer(env, nft_contract_address, returned_commitment, proxy);
}

/// A contract takes custody of the token publicly, then hands it back privately: it must return to `from`.
#[test]
unconstrained fn nft_transfer_private_to_public_with_commitment_returns_to_from() {
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _, custodian) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    let take = NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
        owner,
        custodian,
        token_id,
        0,
    );
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, custodian, take);
    let commitment: Field = env.call_private(
        owner,
        GenericProxy::at(custodian).forward_private_4_and_return(
            take.target_contract,
            take.selector,
            take.args,
        ),
    );
    utils::assert_owns_public_nft(env, nft_contract_address, custodian, token_id);
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);

    // The custodian is `msg_sender` of the take, hence the only completer.
    let give_back = NFT::at(nft_contract_address).transfer_public_to_commitment(
        custodian,
        token_id,
        commitment,
        0,
    );
    env.call_public(
        owner,
        GenericProxy::at(custodian).forward_public_4(
            give_back.target_contract,
            give_back.selector,
            give_back.args,
        ),
    );

    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
    utils::assert_nft_exists(env, nft_contract_address, token_id);
}

#[test(should_fail_with = "nft not found")]
unconstrained fn nft_transfer_private_to_public_with_commitment_non_existent_fail() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Attempt to transfer non-existent NFT
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            non_existent_token_id,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn nft_transfer_private_to_public_with_commitment_unauthorized_fail() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address)
        .transfer_private_to_public_with_commitment(owner, recipient, token_id, 1);

    // Owner calls via proxy but DON'T add authorization witness
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            transfer_call_interface.target_contract,
            transfer_call_interface.selector,
            transfer_call_interface.args,
        ),
    );
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn nft_transfer_private_to_public_with_commitment_and_finalize_invalid_commitment_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with commitment (ignore the returned commitment)
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Create invalid commitment
    let invalid_commitment = 0xdeadbeef;

    // Attempt to finalize with invalid commitment
    env.call_public(
        recipient,
        NFT::at(nft_contract_address).transfer_public_to_commitment(
            recipient,
            token_id,
            invalid_commitment,
            0,
        ),
    );
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn nft_transfer_private_to_public_with_commitment_and_finalize_zero_commitment_fail() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Transfer NFT with commitment (ignore the returned commitment)
    let _ = env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_public_with_commitment(
            owner,
            recipient,
            token_id,
            0,
        ),
    );

    // Create zero commitment
    let zero_commitment = 0;

    // Attempt to finalize with zero commitment
    env.call_public(
        recipient,
        NFT::at(nft_contract_address).transfer_public_to_commitment(
            recipient,
            token_id,
            zero_commitment,
            0,
        ),
    );
}
