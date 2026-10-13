use crate::NFT;
use crate::test::utils;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

#[test]
unconstrained fn transfer_private_to_commitment() {
    // Setup and mint NFT to owner in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // The recipient creates the commitment, naming the sender as its completer.
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );

    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);

    // A note completed in private must be as spendable as any other.
    env.call_private(
        recipient,
        NFT::at(nft_contract_address).transfer_private_to_private(recipient, owner, token_id, 0),
    );
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);
    utils::assert_private_nft_nullified(env, nft_contract_address, recipient, token_id);
}

#[test(should_fail_with = "is reading an unknown nullifier")]
unconstrained fn transfer_private_to_commitment_failure_wrong_completer() {
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );
}

/// A validity nullifier is siloed under the contract that created the commitment, so another contract's commitment
/// cannot be completed here, although Token, MultiToken and NFT compute the same validity commitment for it.
#[test(should_fail_with = "is reading an unknown nullifier")]
unconstrained fn transfer_private_to_commitment_failure_foreign_commitment() {
    let token_id = 10000;
    let (mut env, nft_contract_address, owner, minter, recipient) =
        utils::setup_and_mint_to_private(false, token_id);
    let other_nft_contract_address = utils::deploy_nft_with_minter(&mut env, owner, minter);

    let commitment = env.call_private(
        recipient,
        NFT::at(other_nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );
}

#[test]
unconstrained fn transfer_private_to_commitment_authorized() {
    // Setup with account contracts and mint NFT to owner
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    // Verify initial ownership
    utils::assert_owns_private_nft(env, nft_contract_address, owner, token_id);

    // The proxy calls on the owner's behalf, so the commitment must designate the proxy, not the owner.
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        0,
    );

    // Add authorization witness from owner to proxy
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, transfer_call_interface);

    // Owner calls via proxy so msg_sender is proxy (triggering authwit) but owner's notes remain in scope
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            transfer_call_interface.target_contract,
            transfer_call_interface.selector,
            transfer_call_interface.args,
        ),
    );

    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
}

#[test(should_fail_with = "nft not found")]
unconstrained fn transfer_private_to_commitment_failure_non_existent() {
    // Setup but don't mint any NFT
    let (env, nft_contract_address, owner, _, recipient) = utils::setup_with_minter(false);
    let non_existent_token_id = 12345;

    // Prepare commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Attempt to transfer non-existent NFT
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(
            owner,
            non_existent_token_id,
            commitment,
            0,
        ),
    );
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_to_commitment_failure_unauthorized() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    // Prepare commitment as owner
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        1,
    );

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

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn transfer_private_to_commitment_failure_wrong_authwit() {
    // Setup with account contracts
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_private_with_proxy(token_id);

    // Prepare commitment as owner
    let commitment: Field = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    // Create transfer interface with non-zero nonce
    let transfer_call_interface = NFT::at(nft_contract_address).transfer_private_to_commitment(
        owner,
        token_id,
        commitment,
        1,
    );

    // Add authorization witness but to the wrong address (owner instead of proxy)
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        owner, // Wrong address - should be proxy
        transfer_call_interface,
    );

    // Owner calls via proxy
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_4(
            transfer_call_interface.target_contract,
            transfer_call_interface.selector,
            transfer_call_interface.args,
        ),
    );
}

#[test(should_fail_with = "nft not found")]
unconstrained fn transfer_private_to_commitment_failure_public_nft() {
    // Setup and mint NFT to owner in public state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_public(false, token_id);

    // Prepare commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    // Verify NFT is in public state
    utils::assert_owns_public_nft(env, nft_contract_address, owner, token_id);

    // Attempt to transfer from private state when NFT is actually in public state
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );
}
