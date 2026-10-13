use crate::NFT;
use crate::test::utils;

#[test]
unconstrained fn initialize_transfer_commitment() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    utils::check_commitment_completer(env, nft_contract_address, commitment, owner);

    // The commitment belongs to `to`, not to whoever created it, as when a contract creates it for `to`.
    env.call_private(
        owner,
        NFT::at(nft_contract_address).transfer_private_to_commitment(owner, token_id, commitment, 0),
    );
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
    utils::assert_private_nft_nullified(env, nft_contract_address, owner, token_id);
}

#[test]
unconstrained fn initialize_transfer_commitment_by_recipient() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, _, _, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment as recipient
    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, recipient),
    );

    utils::check_commitment_completer(env, nft_contract_address, commitment, recipient);
}

#[test]
unconstrained fn initialize_transfer_commitment_self() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, _) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment to self
    let commitment = env.call_private(
        owner,
        NFT::at(nft_contract_address).initialize_transfer_commitment(owner, owner),
    );

    utils::check_commitment_completer(env, nft_contract_address, commitment, owner);
}

#[test]
unconstrained fn initialize_transfer_commitment_by_third_party() {
    // Setup with NFT in private state
    let token_id = 10000;
    let (env, nft_contract_address, _, minter, recipient) =
        utils::setup_and_mint_to_private(false, token_id);

    // Initialize transfer commitment as minter (third party)
    let commitment = env.call_private(
        minter,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, minter),
    );

    utils::check_commitment_completer(env, nft_contract_address, commitment, minter);
}
