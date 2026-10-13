use crate::{test::utils::{self, mint_amount}, Token};
use aztec::oracle::random::random;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

/// The documented flow: the recipient creates the commitment naming the payer, who completes it from its public
/// balance.
#[test]
unconstrained fn transfer_public_to_commitment_external_orchestration() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let commitment = env.call_private(
        recipient,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    // Finalize the transfer of the tokens (message sender owns the tokens in public)
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            owner,
            commitment,
            mint_amount,
            0,
        ),
    );

    // Recipient's private balance should be equal to the amount
    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);
}

#[test(should_fail_with = "Invalid partial note or completer")]
unconstrained fn transfer_public_to_commitment_failure_transfer_not_initialized() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, _) =
        utils::setup_and_mint_to_public_without_minter(false);

    // Transfer was not prepared, so we can use a random value for the commitment
    let commitment = random();

    // Try finalizing the transfer without preparing it first
    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            owner,
            commitment,
            mint_amount,
            0,
        ),
    );
}

#[test(should_fail_with = "attempt to subtract with overflow 'self.storage.public_balances.at(from).read() - amount'")]
unconstrained fn transfer_public_to_commitment_failure_not_an_owner() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (mut env, token_contract_address, owner, not_owner) =
        utils::setup_and_mint_to_public_without_minter(false);

    // (For this specific test we could set a random value for the commitment and not do the call to `prepare...`
    // as the token balance check is before we use the value but that would made the test less robust against changes
    // in the contract.)
    let commitment_result = env.call_private(
        owner,
        Token::at(token_contract_address).initialize_transfer_commitment(owner, owner),
    );
    let commitment = commitment_result;

    // Try transferring someone else's token balance
    env.call_public(
        not_owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            not_owner,
            commitment,
            mint_amount,
            0,
        ),
    );
}

/// Under an authwit the caller, not `from`, is the completer the commitment must designate.
#[test]
unconstrained fn transfer_public_to_commitment_on_behalf_of_other() {
    let (env, token_contract_address, owner, recipient, proxy) =
        utils::setup_and_mint_to_public_with_proxy();

    let commitment = env.call_private(
        recipient,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, proxy),
    );

    let action = Token::at(token_contract_address).transfer_public_to_commitment(
        owner,
        commitment,
        mint_amount,
        0,
    );
    authwit_cheatcodes::add_public_authwit_from_call(env, owner, proxy, action);
    env.call_public(
        owner,
        GenericProxy::at(proxy).forward_public_4(
            action.target_contract,
            action.selector,
            action.args,
        ),
    );

    utils::check_public_balance(env, token_contract_address, owner, 0 as u128);
    utils::check_private_balance(env, token_contract_address, recipient, mint_amount);
}

/// Completion is not single use: a second completion succeeds and debits the payer again, but the recipient's wallet
/// only discovers the first one. Pins the behaviour the README warns about.
#[test]
unconstrained fn transfer_public_to_commitment_twice_only_first_is_discovered() {
    let (env, token_contract_address, owner, recipient) =
        utils::setup_and_mint_to_public_without_minter(false);

    let commitment = env.call_private(
        recipient,
        Token::at(token_contract_address).initialize_transfer_commitment(recipient, owner),
    );

    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            owner,
            commitment,
            100 as u128,
            0,
        ),
    );
    utils::check_private_balance(env, token_contract_address, recipient, 100 as u128);

    env.call_public(
        owner,
        Token::at(token_contract_address).transfer_public_to_commitment(
            owner,
            commitment,
            50 as u128,
            0,
        ),
    );
    utils::check_public_balance(env, token_contract_address, owner, mint_amount - 150);
    utils::check_private_balance(env, token_contract_address, recipient, 100 as u128);
    utils::check_total_supply(env, token_contract_address, mint_amount);
}
