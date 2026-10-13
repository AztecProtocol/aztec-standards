# Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public balances, offering full coverage of Aztec's confidentiality features.

This implementation provides a robust foundation for fungible tokens on Aztec, enabling developers to build applications with flexible privacy controls and seamless interoperability between private and public states.

## AIP-20: Aztec Token Standard

This contract follows the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737). Feel free to review and discuss the specification on the Aztec forum.

## ARC-403: Authorization Hook

This contract also implements [ARC-403](https://forum.aztec.network/t/arc-403-authtoken/7887), an optional authorization hook that calls an external **authorization contract** on every transfer and burn. This enables compliance policies (KYC, allowlists, transfer caps, sanctions screening, audit logging, pausability, etc.) to be plugged in without changing the token interface. If no authorization contract is set, the token behaves as a standard AIP-20 token. The ARC-403 specification is a draft under active discussion; this implementation tracks the draft. See [ARC-403 Authorization Hook](#arc-403-authorization-hook-1) for details.

## Transfer Events

The contract emits a public `Transfer { from, to, amount }` event on every balance-changing operation (mints, burns, public transfers, and cross-domain private ↔ public moves), enabling indexers to track token movements.

| Operation | Event Pattern |
|-----------|---------------|
| Mint to public | `Transfer(0x0, recipient, amount)` |
| Mint to private | `Transfer(0x0, PRIVATE_ADDRESS, amount)` |
| Burn from public | `Transfer(from, 0x0, amount)` |
| Burn from private | `Transfer(PRIVATE_ADDRESS, 0x0, amount)` |
| Public-to-public | `Transfer(from, to, amount)` |
| Public-to-private | `Transfer(from, PRIVATE_ADDRESS, amount)` |
| Private-to-public (with or without commitment) | `Transfer(PRIVATE_ADDRESS, to, amount)` |
| Public-to-commitment | `Transfer(from, PRIVATE_ADDRESS, amount)` |
| Mint to commitment | `Transfer(0x0, PRIVATE_ADDRESS, amount)` |
| Private-to-private | _(no public events)_ |
| Private-to-commitment | _(no public events; the amount is still published, see [Commitments](#commitments))_ |

**Sentinel values:** `0x0` denotes mint origin (`from`) or burn destination (`to`), following ERC-20. `PRIVATE_ADDRESS` (sha224 of `"PRIVATE_ADDRESS"`) denotes the private side of a balance change when the counterpart cannot be revealed.

## Commitments

A commitment is a partial note: a private note whose owner is fixed when it is created and whose amount is filled in later. Completing it needs only the commitment, not the owner's address, and does not publish the owner. That is privacy from chain observers, not from the completer: a contract that creates a refund commitment knows whom it refunds.

- **Create.** `initialize_transfer_commitment(to, completer)` returns a commitment owned by `to`. `to` learns about it through an unconstrained message, so `to`, or a contract acting for it, should be the caller. `transfer_private_to_public_with_commitment` returns one owned by `from` for refunds (below).
- **Complete.** Only `completer` can, as `msg_sender` of `transfer_public_to_commitment`, `transfer_private_to_commitment` or `mint_to_commitment`. Under an authwit that is the caller, not `from`. The completer picks the amount: a commitment is a request to be paid, not a guarantee.
- **What is bound.** The commitment binds the owner and randomness, and the validity nullifier pushed at creation binds the completer. The amount and storage slot are only fixed by the completed note hash.
- **What is public.** Completing publishes the storage slot and the amount in a log tagged by the commitment, including from `transfer_private_to_commitment`, which emits it unencrypted through the private-log channel. The owner is never published, but public completion also exposes the commitment and the completer, so anyone can recompute the validity nullifier and find the transaction that created the commitment; whatever that transaction reveals, such as a public fee payer, which by default is `to`, is linked to the payment. Private completion exposes neither.
- **Timing.** `transfer_private_to_commitment` proves the validity nullifier against the block its transaction is anchored to, so the commitment must come from an earlier block. Public completion also works in the transaction that created it.
- **Complete at most once.** Nothing stops a second completion, and it is paid for again, but the owner's wallet processes only the first completion log it finds, so reuse can leave the other payments undiscovered, not necessarily the later ones, and the funds out of reach of normal wallet discovery.
- **Zero.** Public completion rejects `amount == 0`. `transfer_private_to_commitment` accepts it and completes the commitment with an empty note.

### Refunds

`transfer_private_to_public_with_commitment(from, to, amount, nonce)` moves `amount` to `to`'s public balance and returns a commitment owned by `from` that only `msg_sender` can complete. A contract (an AMM, a fee payment contract) calls it with `from`'s authwit, keeps what it needs, and returns the rest privately with `transfer_public_to_commitment(self, commitment, change, 0)`, skipped when `change` is zero, since public completion rejects it. This mirrors `transfer_to_public_and_prepare_private_balance_increase` in the Aztec Labs token.

## Storage Fields

- `name: str<31>`: Token name (compressed).
- `symbol: str<31>`: Token symbol (compressed).
- `decimals: u8`: Decimal precision.
- `private_balances: Owned<BalanceSet>`: Private balances; `private_balances.at(owner)` is one account's note set.
- `public_balances: Map<AztecAddress, u128>`: Public balances per account.
- `total_supply: u128`: Total token supply.
- `minter: AztecAddress`: Authorized minter address (if set).
- `auth_contract: AztecAddress`: ARC-403 authorization contract address (zero address disables the hook).

## Initializer Functions

### constructor_with_initial_supply
```rust
/// @notice Initializes the token with an initial supply
/// @dev The minter is initialized to the zero address, so the mint functions are disabled
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param initial_supply The initial supply of the token
/// @param to The address to mint the initial supply to
/// @param auth_contract The ARC-403 authorization contract address (zero address to disable)
#[public]
#[initializer]
fn constructor_with_initial_supply(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    initial_supply: u128,
    to: AztecAddress,
    auth_contract: AztecAddress,
) { /* ... */ }
```

### constructor_with_minter
```rust
/// @notice Initializes the token with a minter
/// @param name The name of the token
/// @param symbol The symbol of the token
/// @param decimals The number of decimals of the token
/// @param minter The address of the minter
/// @param auth_contract The ARC-403 authorization contract address (zero address to disable)
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    decimals: u8,
    minter: AztecAddress,
    auth_contract: AztecAddress,
) { /* ... */ }
```

## View Functions

### balance_of_public
```rust
/// @notice Returns the public balance of `owner`
/// @param owner The address of the owner
/// @return The public balance of `owner`
#[public]
#[view]
fn balance_of_public(owner: AztecAddress) -> u128 { /* ... */ }
```

### total_supply
```rust
/// @notice Returns the total supply of the token
/// @return The total supply of the token
#[public]
#[view]
fn total_supply() -> u128 { /* ... */ }
```

### name
```rust
/// @notice Returns the name of the token
/// @return The name of the token
#[public]
#[view]
fn name() -> FieldCompressedString { /* ... */ }
```

### symbol
```rust
/// @notice Returns the symbol of the token
/// @return The symbol of the token
#[public]
#[view]
fn symbol() -> FieldCompressedString { /* ... */ }
```

### decimals
```rust
/// @notice Returns the decimals of the token
/// @return The decimals of the token
#[public]
#[view]
fn decimals() -> u8 { /* ... */ }
```

### get_auth_contract
```rust
/// @notice Returns the ARC-403 authorization hook contract address
/// @return The auth contract address (zero address means authorization is disabled)
#[public]
#[view]
fn get_auth_contract() -> AztecAddress { /* ... */ }
```

### get_minter
```rust
/// @notice Returns the authorized minter address
/// @return The minter address (zero address means minting is disabled)
#[public]
#[view]
fn get_minter() -> AztecAddress { /* ... */ }
```

## Utility Functions

### balance_of_private
```rust
/// @notice Returns the private balance of `owner`
/// @param owner The address of the owner
/// @return The private balance of `owner`
#[utility]
unconstrained fn balance_of_private(owner: AztecAddress) -> u128 { /* ... */ }
```

## Public Functions

### transfer_public_to_public
```rust
/// @notice Transfers tokens from public balance to public balance
/// @dev Public call to decrease account balance and a public call to increase recipient balance
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Transfer tokens from public balance to a commitment
/// @dev `msg_sender` must be the commitment's completer: the caller, which is not `from` under an authwit.
/// @param from The address of the sender
/// @param commitment The commitment to complete
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints tokens to a public balance
/// @dev Increases the public balance of `to` by `amount` and the total supply
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_public(
    to: AztecAddress,
    amount: u128,
) { /* ... */ }
```

### mint_to_commitment
```rust
/// @notice Mints tokens to a commitment
/// @dev The minter must be the commitment's completer. Increases the total supply.
/// @param commitment The commitment to complete
/// @param amount The amount of tokens to mint
#[public]
fn mint_to_commitment(
    commitment: Field,
    amount: u128,
) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns tokens from a public balance
/// @dev Burns tokens from a public balance and updates the total supply
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[public]
fn burn_public(
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

## Private Functions

### transfer_private_to_public
```rust
/// @notice Transfer tokens from private balance to public balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and enqueues a public call
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfer tokens from private balance to public balance, with a refund commitment for `from`
/// @dev The commitment is owned by `from` and completable only by `msg_sender`. See Refunds above.
/// @param from The address of the sender, and the owner of the commitment
/// @param to The address of the recipient of the public balance
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
/// @return commitment The refund commitment owned by `from`
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfer tokens from private balance to private balance
/// @dev Spends notes, emits a new note (UintNote) with any remaining change, and sends a note to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfer tokens from private balance to a commitment, completing it in private
/// @dev `msg_sender` must be the commitment's completer, and the commitment must come from an earlier block.
///      The amount is published.
/// @param from The address of the sender
/// @param commitment The commitment to complete
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    commitment: Field,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfer tokens from public balance to private balance
/// @dev Enqueues a public call to decrease account balance and emits a new note with balance difference
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param amount The amount of tokens to transfer
/// @param nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
    nonce: Field,
) { /* ... */ }
```

### initialize_transfer_commitment
```rust
/// @notice Creates a commitment owned by `to` that only `completer` can complete
/// @dev See Commitments above.
/// @param to The owner of the commitment
/// @param completer The only address allowed to complete the commitment
/// @return commitment The commitment
#[private]
fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field { /* ... */ }
```

### mint_to_private
```rust
/// @notice Mints tokens into a private balance
/// @dev Requires minter, enqueues supply update
/// @param to The address of the recipient
/// @param amount The amount of tokens to mint
#[private]
fn mint_to_private(to: AztecAddress, amount: u128) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns tokens from a private balance
/// @dev Requires authwit, enqueues supply update
/// @param from The address of the sender
/// @param amount The amount of tokens to burn
/// @param nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, amount: u128, nonce: Field) { /* ... */ }
```

### cancel_authwit
```rust
/// @notice Cancels a private authentication witness the caller previously granted
/// @dev Emits the authwit nullifier for `(msg_sender, inner_hash)`, so an authwit that has been
///      granted but not yet consumed can no longer be used
/// @param inner_hash The inner hash of the authwit to cancel
#[private]
fn cancel_authwit(inner_hash: Field) { /* ... */ }
```

## ARC-403 Authorization Hook

The authorization contract address is set at construction via the `auth_contract` parameter on both constructors and stored as an immutable field. A zero address disables the hook. When set, each hooked function calls either `authorize_private(from, amount, selector)` or `authorize_public(from, amount, selector)` on the authorization contract after authwit validation and before any balance mutation. The token operation reverts if the authorization call reverts. The hook variant matches the calling function's context — private functions call `authorize_private`, public functions call `authorize_public` — and the `selector` passed is the calling function's own selector.

| Token function | Hook called |
|----------------|-------------|
| `transfer_private_to_private` | `authorize_private` |
| `transfer_private_to_public` | `authorize_private` |
| `transfer_private_to_public_with_commitment` | `authorize_private` |
| `transfer_private_to_commitment` | `authorize_private` |
| `transfer_public_to_private` | `authorize_private` |
| `transfer_public_to_public` | `authorize_public` |
| `transfer_public_to_commitment` | `authorize_public` |
| `burn_private` | `authorize_private` |
| `burn_public` | `authorize_public` |

### Considerations

- **Mints are not hooked.** `mint_to_public`, `mint_to_private`, and `mint_to_commitment` do not call the hook — minting is already gated by the `minter` address set at construction. **An authorization contract is therefore not a universal kill switch**: pausing it halts transfers and burns, but the `minter` can still issue new supply. Deployments that treat the hook as an emergency stop should note that a compromised `minter` key cannot be contained by the authorization contract, since `minter` is a single immutable address while the hook can encode richer governance. Whether mints should invoke the hook (with `from` as the zero address, which would enable pause and supply-cap policies but still not recipient screening, since `to` is not forwarded) is an open question for the [ARC-403 draft](https://forum.aztec.network/t/arc-403-authtoken/7887).
- **`to` is not forwarded to the hook.** The recipient cannot be provided consistently across all transfer flows (commitment-based transfers seal the recipient inside a hash preimage the sender never sees), so it is omitted entirely rather than passed inconsistently. As a result, a blocked sender can still receive funds, but might not be able to spend them.
- **`transfer_public_to_private` is not fully private.** It calls `authorize_private`, but spending a public balance inherently reveals `from` and `amount` on-chain regardless of any privacy the authorization contract provides. Authorization contracts can use the `selector` argument to distinguish this case.

The canonical hook interface lives in [`src/arc403_interface`](../arc403_interface/README.md) — implement its `Arc403Authorizer` signatures to write an authorization contract. Design discussion and example authorization policies (allowlist, signature-by-authority, transfer caps, pausable, etc.) live in the [ARC-403 forum thread](https://forum.aztec.network/t/arc-403-authtoken/7887). No maintained reference-implementation repository currently exists.

## Internal Functions

These functions are part of the on-chain ABI but are `#[only_self]` — they can only be called by the token contract itself (enqueued from its own private executions). They are listed for completeness; external callers cannot invoke them.

| Function | Context | Purpose |
|----------|---------|---------|
| `recurse_subtract_balance_internal(account, amount) -> u128` | private | Continues subtracting private balance when a spend exceeds the per-call note limit |
| `increase_public_balance_internal(to, amount)` | public | Credits a public balance during a private→public flow; emits `Transfer` |
| `decrease_public_balance_internal(from, amount)` | public | Debits a public balance during a public→private flow; emits `Transfer` |
| `increase_total_supply_internal(amount)` | public | Updates total supply for private mints; emits `Transfer` |
| `decrease_total_supply_internal(amount)` | public | Updates total supply for private burns; emits `Transfer` |