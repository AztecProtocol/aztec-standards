# MultiToken Contract

The `MultiToken` contract implements an ERC-1155-like multi-token with Aztec-specific privacy extensions. A single contract holds many fungible token ids, each with its own independent balance, and every balance can live in either a private or a public domain with seamless moves between the two.

Compared to the single-asset [`Token`](../token_contract/README.md), every balance-changing function takes an extra `id: Field` selecting the token, there is no `decimals` and no `total_supply`, and the on-chain event is `TransferSingle` (ERC-1155 naming) instead of `Transfer`.

> [!WARNING]
> Like everything in this repository, `MultiToken` is **experimental, unaudited software** (see the repo-level [Security Status](../../README.md#️-security-status-unaudited)). One behaviour in particular is easy to misuse: a transfer commitment does **not** bind the token id or amount — the completer chooses both. This is intentional, but it means a commitment is **not a payment guarantee**. Read the [Commitment trust model](#commitment-trust-model) before using one in an escrow or marketplace flow.

## ARC-403: Authorization Hook

Like `Token`, this contract implements the optional ARC-403 authorization hook: when an `auth_contract` is configured, every transfer and burn calls it before mutating balances, and the operation reverts if the hook reverts. If `auth_contract` is the zero address, the hook is disabled and the token behaves as a plain multi-token. The interface is **id-bearing** — the hook receives the token id so policies can differ per id:

- `authorize_private(from, id, amount, selector)` — called by private-context functions.
- `authorize_public(from, id, amount, selector)` — called by public-context functions.

| Function | Hook called |
|----------|-------------|
| `transfer_private_to_private` | `authorize_private` |
| `transfer_private_to_public` | `authorize_private` |
| `transfer_private_to_commitment` | `authorize_private` |
| `transfer_public_to_private` | `authorize_private` |
| `transfer_public_to_public` | `authorize_public` |
| `transfer_public_to_commitment` | `authorize_public` |
| `burn_private` | `authorize_private` |
| `burn_public` | `authorize_public` |

Mints (`mint_to_private`, `mint_to_public`, `mint_to_commitment`) are **not** hooked — minting is already gated by the `minter` address set at construction. As with [`Token`](../token_contract/README.md#considerations), this means an authorization contract is **not a universal kill switch**: pausing it halts transfers and burns while the `minter` can still issue new supply of any id.

## Commitment trust model

`initialize_transfer_commitment(to, completer)` binds the recipient, the note randomness, and the address permitted to complete the commitment. It deliberately does **not** bind `token_id` or `amount` — both are supplied by the completer at completion time. This is what makes the mechanism useful when the id or value cannot be known in private (for example when they depend on public state), and it is the documented intent.

The consequence is that **a commitment is not a payment guarantee**. Whoever you nominate as `completer` chooses both which token id and how much to deposit, so a commitment is only as trustworthy as that party. Concretely:

- **Safe**: you are the completer, or the completer is a party you already trust for the amount (e.g. the token's own minter, or a contract whose logic fixes the value in public execution).
- **Unsafe**: escrow, marketplace, or handoff patterns where a counterparty completes your commitment in exchange for something you release first. A malicious completer can satisfy the commitment with a negligible amount of an arbitrary id — including one they created — and the completion will succeed.

Note this is a wider surface than the single-asset [`Token`](../token_contract/README.md), where the token is implicit and only the amount is completer-chosen. If you need a commitment whose contents are guaranteed, the value must be enforced outside this primitive.

The rest of the commitment contract, shared with `Token`:

- **Create.** `initialize_transfer_commitment(to, completer)` returns a commitment owned by `to`. `to` learns about it through an unconstrained message, so `to`, or a contract acting for it, should be the caller.
- **Complete.** Only `completer` can, as `msg_sender` of `transfer_private_to_commitment`, `transfer_public_to_commitment` or `mint_to_commitment`. Under an authwit that is the caller, not `from`, so the commitment must name the caller.
- **What is public.** Completing publishes the storage slot, the id and the amount in a log tagged by the commitment, including from `transfer_private_to_commitment`, which emits it unencrypted through the private-log channel. Completion does not publish the owner, which is privacy from chain observers, not from the completer. Public completion exposes the commitment and the completer, who is the owner if the owner completes it, and anyone can then recompute the validity nullifier and find the transaction that created the commitment; whatever that transaction reveals, such as its fee payer (by default the account that sent it, which in the documented flows is the owner), is linked to the payment. Private completion exposes neither.
- **Timing.** `transfer_private_to_commitment` proves the validity nullifier against the block its transaction is anchored to, so the commitment must come from an earlier block. Public completion also works in the transaction that created it.
- **Complete at most once.** Nothing stops a second completion, and it is paid for again, but the owner's wallet processes only the first completion log it finds, so reuse can leave the other payments undiscovered, not necessarily the later ones, and the funds out of reach of normal wallet discovery. "Safe" above does not make reuse safe.
- **Zero.** Public completion rejects `amount == 0`. `transfer_private_to_commitment` accepts it and completes the commitment with an empty note. That empty note is a completion like any other, so the owner's wallet may take it and leave a non-zero payment into the same commitment undiscovered.
- **Refunds.** There is no `transfer_private_to_public_with_commitment`. A contract returning change privately calls `initialize_transfer_commitment(user, self)` alongside `transfer_private_to_public`, then completes the commitment publicly with the change, skipping that call when there is none, since public completion rejects a zero amount.

## Supply bound

There is no total supply. The minter must keep each id's total at or below `u128::MAX`: private balances are summed in `u128`, so for an owner holding more, `balance_of_private` overflows and a private transfer whose note selection sums past `u128::MAX` fails in simulation, so nothing reaches the chain.

## TransferSingle Events

A public `TransferSingle { from, to, id, amount }` event is emitted only on operations whose token id is already revealed on-chain (any public-balance write or public commitment completion). The fully private operations (`transfer_private_to_private`, `mint_to_private`, `burn_private`) emit nothing, since an id-bearing event would leak the token id; private entrypoints that cross into public emit through their public part. `transfer_private_to_commitment` emits no event either, but still publishes the id and amount (see [Commitment trust model](#commitment-trust-model)).

| Operation | Event Pattern |
|-----------|---------------|
| Mint to public | `TransferSingle(0x0, recipient, id, amount)` |
| Mint to commitment | `TransferSingle(0x0, PRIVATE_ADDRESS, id, amount)` |
| Burn from public | `TransferSingle(from, 0x0, id, amount)` |
| Public-to-public | `TransferSingle(from, to, id, amount)` |
| Public-to-commitment | `TransferSingle(from, PRIVATE_ADDRESS, id, amount)` |
| Public-to-private | `TransferSingle(from, PRIVATE_ADDRESS, id, amount)` |
| Private-to-public | `TransferSingle(PRIVATE_ADDRESS, to, id, amount)` |
| Mint to private / Burn from private | _(no public events)_ |
| Private-to-private | _(no public events)_ |
| Private-to-commitment | _(no public events; the id and amount are still published, see [Commitment trust model](#commitment-trust-model))_ |

**Sentinel values:** `0x0` denotes mint origin (`from`) or burn destination (`to`), following ERC-1155. `PRIVATE_ADDRESS` (sha224 of `"PRIVATE_ADDRESS"`) denotes the private side of a balance change when the counterpart cannot be revealed.

## Storage Fields

- `name: FieldCompressedString`: Token collection name (compressed).
- `symbol: FieldCompressedString`: Token collection symbol (compressed).
- `private_balances: Owned<MultiBalanceSet>`: A single private note set. Each `MultiTokenNote` self-describes its token id; per-owner scoping is `private_balances.at(owner)`, and per-id operations select notes where `token_id == id`.
- `public_balances: Map<Field, Map<AztecAddress, u128>>`: Public balances keyed by token id, then owner.
- `minter: AztecAddress`: Account permitted to mint any token id.
- `auth_contract: AztecAddress`: ARC-403 authorization contract address (zero address disables the hook).

## Function Reference

All addresses are `AztecAddress`; `id` is a `Field`, `amount` is a `u128`, and `nonce` (used for authwit) is a `Field`.

### Initializer

- `constructor_with_minter(name: FieldCompressedString, symbol: FieldCompressedString, minter, auth_contract)` — Initializes the multi-token with a minter and an optional ARC-403 auth contract.

### Private Functions

- `transfer_private_to_private(from, to, id, amount, nonce)` — Moves `amount` of `id` between private balances. Fully private (no event, no public effect).
- `transfer_private_to_public(from, to, id, amount, nonce)` — Spends private notes and enqueues a public credit to `to`.
- `transfer_private_to_commitment(from, id, commitment, amount, nonce)` — Spends private notes and completes, in private, a commitment from an earlier block with `(id, amount)`, which are published. The caller must be the commitment's completer.
- `transfer_public_to_private(from, to, id, amount, nonce)` — Enqueues a public debit of `from` and emits a private note to `to`.
- `initialize_transfer_commitment(to, completer) -> Field` — Creates a commitment owned by `to` that only `completer` can complete. Id-agnostic: the completer binds `id` and `amount`. Nothing enforces single-use completion, and the owner's wallet processes only the first completion log it finds, so the other payments can go undiscovered; see [Commitment trust model](#commitment-trust-model) before using a commitment as a payment guarantee.
- `mint_to_private(to, id, amount)` — Minter mints `id` into a private balance. Fully private.
- `burn_private(from, id, amount, nonce)` — Burns `id` from a private balance. Fully private.
- `cancel_authwit(inner_hash)` — Cancels a private authwit the caller previously granted, by emitting its `(msg_sender, inner_hash)` nullifier so it can no longer be consumed.

### Public Functions

- `transfer_public_to_public(from, to, id, amount, nonce)` — Moves `amount` of `id` between public balances.
- `transfer_public_to_commitment(from, id, commitment, amount, nonce)` — Debits `from`'s public balance and completes a commitment prepared by `initialize_transfer_commitment`. The caller must be the commitment's completer.
- `mint_to_public(to, id, amount)` — Minter mints `id` into a public balance.
- `mint_to_commitment(id, commitment, amount)` — Minter mints into a commitment; the minter must be its completer.
- `burn_public(from, id, amount, nonce)` — Burns `id` from a public balance.

### View Functions

- `balance_of_public(owner, id) -> u128` — Public balance of `owner` for `id`.
- `name() -> FieldCompressedString` — Token collection name.
- `symbol() -> FieldCompressedString` — Token collection symbol.
- `get_minter() -> AztecAddress` — Authorized minter address.
- `get_auth_contract() -> AztecAddress` — ARC-403 auth contract address (zero if disabled).

### Utility Functions

- `balance_of_private(owner, id) -> u128` — Off-chain helper that pages through the owner's notes filtered by `id` and sums their values. No on-chain or proving cost, and no fixed cap.
