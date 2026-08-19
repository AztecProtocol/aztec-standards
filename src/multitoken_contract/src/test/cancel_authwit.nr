use crate::MultiToken;
use crate::test::utils;
use aztec::authwit::auth::compute_inner_authwit_hash;
use aztec::hash::hash_args;
use aztec::protocol::traits::ToField;
use aztec::test::helpers::authwit as authwit_cheatcodes;
use generic_proxy::GenericProxy;

// Proves that once `owner` cancels a private authwit, a caller holding it can no longer consume it:
// the cancellation pre-emits the authwit nullifier, so the later authwit-gated transfer fails when
// it tries to emit the same nullifier again.
#[test(should_fail_with = "duplicate nullifiers")]
unconstrained fn cancelled_authwit_cannot_be_consumed() {
    let id: Field = 1;
    let (mut env, multitoken_contract_address, owner, recipient, _minter, proxy) =
        utils::setup_and_mint_to_private_with_proxy(id);

    let transfer_amount = (1_000 as u128);
    let transfer_call = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );

    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, transfer_call);

    let inner_hash = compute_inner_authwit_hash([
        proxy.to_field(),
        transfer_call.selector.to_field(),
        hash_args(transfer_call.args),
    ]);
    env.call_private(owner, MultiToken::at(multitoken_contract_address).cancel_authwit(inner_hash));

    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            transfer_call.target_contract,
            transfer_call.selector,
            transfer_call.args,
        ),
    );
}

// Positive control: the same flow WITHOUT the cancel succeeds, attributing the failure above to the
// cancellation.
#[test]
unconstrained fn uncancelled_authwit_is_consumed() {
    let id: Field = 1;
    let (mut env, multitoken_contract_address, owner, recipient, _minter, proxy) =
        utils::setup_and_mint_to_private_with_proxy(id);

    let transfer_amount = (1_000 as u128);
    let transfer_call = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );

    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, transfer_call);

    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            transfer_call.target_contract,
            transfer_call.selector,
            transfer_call.args,
        ),
    );

    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}

// Caller isolation: a foreign account cancelling with the owner's exact inner hash does NOT revoke
// the owner's authwit — the nullifier is bound to `msg_sender`.
#[test]
unconstrained fn foreign_cancel_does_not_revoke_owner_authwit() {
    let id: Field = 1;
    let (mut env, multitoken_contract_address, owner, recipient, _minter, proxy) =
        utils::setup_and_mint_to_private_with_proxy(id);

    let transfer_amount = (1_000 as u128);
    let transfer_call = MultiToken::at(multitoken_contract_address).transfer_private_to_private(
        owner,
        recipient,
        id,
        transfer_amount,
        1,
    );
    authwit_cheatcodes::add_private_authwit_from_call(env, owner, proxy, transfer_call);

    let inner_hash = compute_inner_authwit_hash([
        proxy.to_field(),
        transfer_call.selector.to_field(),
        hash_args(transfer_call.args),
    ]);
    // `recipient` (not the granter) attempts to cancel the owner's authwit
    env.call_private(
        recipient,
        MultiToken::at(multitoken_contract_address).cancel_authwit(inner_hash),
    );

    env.call_private(
        owner,
        GenericProxy::at(proxy).forward_private_5(
            transfer_call.target_contract,
            transfer_call.selector,
            transfer_call.args,
        ),
    );
    utils::check_private_balance(
        env,
        multitoken_contract_address,
        recipient,
        id,
        transfer_amount,
    );
}
