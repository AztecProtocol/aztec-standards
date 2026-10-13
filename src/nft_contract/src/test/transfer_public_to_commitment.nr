use crate::NFT;
use crate::test::utils;
use aztec::protocol::address::AztecAddress;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

/// Under an authwit the caller, not `from`, is the completer the commitment must designate.
#[test]
unconstrained fn nft_transfer_public_to_commitment_authorized_success() {
    let token_id = 10000;
    let (env, nft_contract_address, owner, _, recipient, proxy) =
        utils::setup_and_mint_to_public_with_proxy(token_id);

    let commitment = env.call_private(
        recipient,
        NFT::at(nft_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    let action =
        NFT::at(nft_contract_address).transfer_public_to_commitment(owner, token_id, commitment, 0);
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, proxy, action);
    env.call_public(
        owner,
        GenericProxy::at(proxy).forward_public_4(
            action.target_contract,
            action.selector,
            action.args,
        ),
    );

    utils::assert_owns_public_nft(env, nft_contract_address, AztecAddress::zero(), token_id);
    utils::assert_owns_private_nft(env, nft_contract_address, recipient, token_id);
}

/// Public completion checks the validity nullifier under this contract's address too.
#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn nft_transfer_public_to_commitment_foreign_commitment_fail() {
    let token_id = 10000;
    let (mut env, nft_contract_address, owner, minter, recipient) =
        utils::setup_and_mint_to_public(false, token_id);
    let other_nft_contract_address = utils::deploy_nft_with_minter(&mut env, owner, minter);

    let commitment = env.call_private(
        recipient,
        NFT::at(other_nft_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    env.call_public(
        owner,
        NFT::at(nft_contract_address).transfer_public_to_commitment(owner, token_id, commitment, 0),
    );
}
