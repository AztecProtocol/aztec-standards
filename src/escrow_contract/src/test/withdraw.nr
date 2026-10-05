use crate::Escrow;
use crate::test::utils as escrow_utils;
use aztec::protocol::{abis::function_selector::FunctionSelector, traits::ToField};
use aztec::test::helpers::test_environment::CallPrivateOptions;
use token::{test::utils as token_utils, Token};

#[test]
unconstrained fn escrow_withdraw_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter, logic_contract_address) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    // Mint some tokens to escrow
    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(escrow_contract_address, amount),
    );

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        amount,
    );

    env.call_private_opts(
        logic_contract_address,
        CallPrivateOptions::new().with_additional_scopes([escrow_contract_address]),
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check recipient got tokens
    token_utils::check_private_balance(env, token_contract_address, recipient, amount);
}

#[test]
unconstrained fn escrow_withdraw_twice_success() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, recipient, minter, logic_contract_address) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    // Mint some tokens to escrow
    let total_amount: u128 = token_utils::mint_amount * 2;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(escrow_contract_address, total_amount),
    );

    // Check the escrow received and can read the tokens
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        total_amount,
    );

    let amount: u128 = token_utils::mint_amount;
    // Partial withdrawal
    env.call_private_opts(
        logic_contract_address,
        CallPrivateOptions::new().with_additional_scopes([escrow_contract_address]),
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check balances
    token_utils::check_private_balance(env, token_contract_address, recipient, amount);
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        amount,
    );

    // Complete withdrawal
    env.call_private_opts(
        logic_contract_address,
        CallPrivateOptions::new().with_additional_scopes([escrow_contract_address]),
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );

    // Check balances
    token_utils::check_private_balance(env, token_contract_address, recipient, total_amount);
    token_utils::check_private_balance(env, token_contract_address, escrow_contract_address, 0);
}

#[test(should_fail_with = "Not Authorized")]
unconstrained fn escrow_withdraw_unauthorized() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, owner, recipient, _, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        owner,
        Escrow::at(escrow_contract_address).withdraw(token_contract_address, amount, recipient),
    );
}

/// The secret is a read capability, not a spend one: Token's authwit check calls the escrow's
/// `verify_private_authwit(Field)` (selector 0xc7784917), which the escrow does not have, so a direct spend fails.
#[test(should_fail_with = "Function with selector 0xc7784917 not found in the registered artifact")]
unconstrained fn escrow_secret_holder_cannot_spend() {
    let escrow_secret: Field = 123456;
    let (mut env, escrow_contract_address, token_contract_address, _, _, attacker, minter, _) =
        escrow_utils::set_escrow_with_token_and_nft(false, escrow_secret);

    assert_eq(
        comptime { FunctionSelector::from_signature("verify_private_authwit(Field)") }.to_field(),
        0xc7784917,
    );

    let amount: u128 = token_utils::mint_amount;
    env.call_private(
        minter,
        Token::at(token_contract_address).mint_to_private(escrow_contract_address, amount),
    );

    // TXE registered the escrow's keys from its secret, so with the escrow in scope the attacker can read its notes.
    token_utils::check_private_balance(
        env,
        token_contract_address,
        escrow_contract_address,
        amount,
    );
    env.call_private_opts(
        attacker,
        CallPrivateOptions::new().with_additional_scopes([escrow_contract_address]),
        Token::at(token_contract_address).transfer_private_to_private(
            escrow_contract_address,
            attacker,
            amount,
            0,
        ),
    );
}
