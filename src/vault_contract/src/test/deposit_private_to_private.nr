use crate::test::utils::{self, mint_amount};
use crate::Vault;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;
use token_contract::Token;

#[test(should_fail_with = "Failed calling external resolver")]
unconstrained fn deposit_private_to_private_without_shares() {
    let (env, vault_address, owner, recipient, _asset_address) =
        utils::setup_vault_without_shares();

    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            mint_amount,
            mint_amount,
            0,
        ),
    );
}

#[test]
unconstrained fn deposit_private_to_private_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Deposit
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, shares_address, recipient, shares);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_private_after_yield() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to the vault contract
    let yield_amount: u128 = 1;
    env.call_public(owner, Token::at(asset_address).mint_to_public(vault_address, yield_amount));

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Deposit
    let expected_shares: u128 = deposit_amount / 2; // The initial rate, when shares' supply is still 0, is given by the amount of assets held by the vault + 1. Since yield = 1, the rate is 1:2.
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            expected_shares,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, shares_address, recipient, expected_shares);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == expected_shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(
        env,
        asset_address,
        vault_address,
        deposit_amount + yield_amount,
    );
}

#[test]
unconstrained fn deposit_private_to_private_request_fewer_shares() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Deposit
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount - 1; // Request fewer shares than possible
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, shares_address, recipient, shares);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}

#[test(should_fail_with = "Too many shares requested")]
unconstrained fn deposit_private_to_private_request_too_many_shares() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, _shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Deposit
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount + 1;
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares,
            0,
        ),
    );
}

// Unknown auth witness for message hash
#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_without_asset_approval() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, _shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares,
            0,
        ),
    );
}

// Unknown auth witness for message hash
#[test(should_fail_with = "Unknown auth witness for message hash ")]
unconstrained fn deposit_private_to_private_on_behalf_of_wrong_caller() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, _shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Deposit
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
    let call_interface = Vault::at(vault_address).deposit_private_to_private(
        owner,
        recipient,
        deposit_amount,
        shares,
        0,
    );
    // No authwit added from owner to proxy
    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            call_interface.target_contract,
            call_interface.selector,
            call_interface.args,
        ),
    );
}

#[test]
unconstrained fn deposit_private_to_private_on_behalf_of_other_success() {
    // Setup with asset token
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

    // Mint some asset tokens to owner
    let deposit_amount: u128 = mint_amount;
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));

    // Deposit assets to get shares
    // Authorize the vault to use the caller's assets
    utils::authorize_transfer_private_to_public(
        env,
        asset_address,
        vault_address,
        owner,
        deposit_amount,
    );

    // Authorize the recipient to call deposit_private_to_private
    // At the first deposit 1 share = 1 asset
    let shares = deposit_amount;
    let deposit_private_to_private_call_interface = Vault::at(vault_address)
        .deposit_private_to_private(owner, recipient, deposit_amount, shares, 0);
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        owner,
        recipient,
        deposit_private_to_private_call_interface,
    );

    // Deposit
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares,
            0,
        ),
    );

    // Check recipient got shares
    utils::check_private_balance(env, shares_address, recipient, shares);
    utils::check_public_balance(env, shares_address, recipient, 0);

    // Check the total supply got updated
    let total_supply = env.view_public(Token::at(shares_address).total_supply());
    assert(total_supply == shares, "Incorrect shares total supply");

    // Check vault has assets
    utils::check_public_balance(env, asset_address, vault_address, deposit_amount);
}

#[test]
unconstrained fn deposit_private_to_private_repeated_identical_self_deposits_distinct_nonces() {
    // Regression guard for the vault's dual-use `nonce`: it is forwarded as the inner asset
    // transfer's authwit nonce, so a SELF-caller must be able to pass a nonzero nonce — distinct
    // nonces are what let two otherwise-identical private asset authwits both be consumed.
    // This is why the vault does not use #[authorize_once("from", "nonce")], which asserts
    // nonce == 0 whenever from == msg_sender and would revert both deposits below.
    let (mut env, vault_address, owner, recipient, asset_address, shares_address) =
        utils::setup_with_vault(true);

    let deposit_amount: u128 = mint_amount;

    // First self-deposit: identical asset authwit shape, nonce 1
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));
    let transfer_1 = Token::at(asset_address).transfer_private_to_public(
        owner,
        vault_address,
        deposit_amount,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, vault_address, transfer_1);
    let shares_1 = deposit_amount;
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares_1,
            1,
        ),
    );

    // Second self-deposit: same from/to/amount (identical authwit preimage except the nonce)
    env.call_private(owner, Token::at(asset_address).mint_to_private(owner, deposit_amount));
    let transfer_2 = Token::at(asset_address).transfer_private_to_public(
        owner,
        vault_address,
        deposit_amount,
        2,
    );
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, vault_address, transfer_2);
    // Request slightly fewer shares than the 1:1 first deposit: the +1/offset conversion rounds down
    let shares_2 = deposit_amount / 2;
    env.call_private(
        owner,
        Vault::at(vault_address).deposit_private_to_private(
            owner,
            recipient,
            deposit_amount,
            shares_2,
            2,
        ),
    );

    // Both deposits landed: recipient holds both share issuances, vault holds both asset amounts
    utils::check_private_balance(env, shares_address, recipient, shares_1 + shares_2);
    utils::check_public_balance(
        env,
        asset_address,
        vault_address,
        deposit_amount + deposit_amount,
    );
}
