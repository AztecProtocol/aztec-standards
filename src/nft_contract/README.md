# NFT Contract

The `NFT` contract implements an ERC-721-like non-fungible token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public ownership, offering full coverage of Aztec's confidentiality features for unique digital assets.

This contract provides a comprehensive NFT implementation that allows seamless transitions between private and public ownership states, making it ideal for applications requiring flexible privacy controls.

## Transfer Events

The contract emits a public `Transfer { from, to, token_id }` event on every ownership-changing operation (mints, burns, public transfers, and cross-domain private ↔ public moves), enabling indexers to track NFT movements.

| Operation | Event Pattern |
|-----------|---------------|
| Mint to public | `Transfer(0x0, recipient, tokenId)` |
| Mint to private | `Transfer(0x0, PRIVATE_ADDRESS, tokenId)` |
| Burn from public | `Transfer(from, 0x0, tokenId)` |
| Burn from private | `Transfer(PRIVATE_ADDRESS, 0x0, tokenId)` |
| Public-to-public | `Transfer(from, to, tokenId)` |
| Public-to-private | `Transfer(from, PRIVATE_ADDRESS, tokenId)` |
| Private-to-public (with or without commitment) | `Transfer(PRIVATE_ADDRESS, to, tokenId)` |
| Public-to-commitment | `Transfer(from, PRIVATE_ADDRESS, tokenId)` |
| Private-to-private | _(no public events)_ |
| Private-to-commitment | _(no public events; the token id is still published, see [Commitments](#commitments))_ |

**Sentinel values:** `0x0` denotes mint origin (`from`) or burn destination (`to`), following ERC-721. `PRIVATE_ADDRESS` (sha224 of `"PRIVATE_ADDRESS"`) denotes the private side of an ownership change when the counterpart cannot be revealed.

## Commitments

A commitment is a partial note: a private NFT note whose owner is fixed when it is created and whose token id is filled in later. Completing it needs only the commitment, not the owner's address, and does not publish the owner. That is privacy from chain observers, not from the completer: a contract that creates a return commitment knows whom it returns the token to.

- **Create.** `initialize_transfer_commitment(to, completer)` returns a commitment owned by `to`. `to` learns about it through an unconstrained message, so `to`, or a contract acting for it, should be the caller. `transfer_private_to_public_with_commitment` returns one owned by `from`, so a contract that takes custody of the token publicly can hand it back privately.
- **Complete.** Only `completer` can, as `msg_sender` of `transfer_public_to_commitment` or `transfer_private_to_commitment`. Under an authwit that is the caller, not `from`. The completer picks the token id.
- **What is bound.** The commitment binds the owner and randomness, and the validity nullifier pushed at creation binds the completer. The token id and storage slot are only fixed by the completed note hash.
- **What is public.** Completing publishes the token id in a log tagged by the commitment, including from `transfer_private_to_commitment`, which emits it unencrypted through the private-log channel. The owner stays private, and so does the sender on the private path.
- **Timing.** `transfer_private_to_commitment` needs the commitment to come from an earlier block. Public completion also works in the transaction that created it.
- **Complete at most once.** Nothing stops a second completion with another token, but the owner's wallet processes only the first completion log it finds, so reuse can leave a later token undiscovered and out of reach of normal wallet discovery.

## Storage Fields

- `name: FieldCompressedString`: NFT collection name (compressed).
- `symbol: FieldCompressedString`: NFT collection symbol (compressed).
- `private_nfts: Owned<PrivateSet<NFTNote>>`: Private NFT ownership; `private_nfts.at(owner)` is one account's note set.
- `nft_exists: Map<Field, bool>`: Mapping from token ID to existence status.
- `public_owners: Map<Field, AztecAddress>`: Public ownership mapping from token ID to owner address.
- `minter: AztecAddress`: Authorized minter address.

## Initializer Functions

### constructor_with_minter
```rust
/// @notice Initializes the NFT contract with a minter
/// @param name The name of the NFT collection
/// @param symbol The symbol of the NFT collection
/// @param minter The address of the minter
#[public]
#[initializer]
fn constructor_with_minter(
    name: str<31>,
    symbol: str<31>,
    minter: AztecAddress,
) { /* ... */ }
```

## Private Functions

### transfer_private_to_public
```rust
/// @notice Transfers token by id from private owner to a public owner
/// @dev Removes token from private owner, and enqueues a public call to update the public owner
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_private_to_public_with_commitment
```rust
/// @notice Transfers token by id from private owner to a public owner, with a return commitment for `from`
/// @dev The commitment is owned by `from` and completable only by `msg_sender`. See Commitments above.
/// @param from The address of the sender, and the owner of the commitment
/// @param to The address of the new public owner
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
/// @return commitment The return commitment owned by `from`
#[private]
fn transfer_private_to_public_with_commitment(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) -> Field { /* ... */ }
```

### transfer_private_to_private
```rust
/// @notice Transfers token by id from private owner to another private owner
/// @dev Removes token by id from private owner, and sends a nft note with id to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_private_to_commitment
```rust
/// @notice Transfers token by id from private owner to a commitment, completing it in private
/// @dev `msg_sender` must be the commitment's completer, and the commitment must come from an earlier block.
///      The token id is published.
/// @param from The address of the sender
/// @param token_id The id of the token to transfer
/// @param commitment The commitment to complete
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_private_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_public_to_private
```rust
/// @notice Transfers token by id from public owner to private owner
/// @dev Enqueues a public call to remove the public owner, and emits a nft note with id to the recipient
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[private]
fn transfer_public_to_private(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
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
/// @notice Mints a token to a private address
/// @dev Asserts that the caller is an authorized minter
/// @param to The address of the recipient
/// @param token_id The id of the token to mint
#[private]
fn mint_to_private(to: AztecAddress, token_id: Field) { /* ... */ }
```

### burn_private
```rust
/// @notice Burns a token from a private address
/// @dev Removes the token from `from`'s private notes and enqueues a public call to burn it
/// @param from The address of the owner
/// @param token_id The id of the token to burn
/// @param _nonce The nonce used for authwit
#[private]
fn burn_private(from: AztecAddress, token_id: Field, _nonce: Field) { /* ... */ }
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

## Public Functions

### transfer_public_to_public
```rust
/// @notice Transfers a token from one public owner to another public owner
/// @dev Asserts `from` owns the token publicly and updates the public owner
/// @param from The address of the sender
/// @param to The address of the recipient
/// @param token_id The id of the token to transfer
/// @param _nonce The nonce used for authwit
#[public]
fn transfer_public_to_public(
    from: AztecAddress,
    to: AztecAddress,
    token_id: Field,
    _nonce: Field,
) { /* ... */ }
```

### transfer_public_to_commitment
```rust
/// @notice Transfers a token from public owner to a commitment
/// @dev Asserts `from` owns the token publicly. `msg_sender` must be the commitment's completer: the caller, which is
///      not `from` under an authwit.
/// @param from The address of the sender
/// @param token_id The id of the token to transfer
/// @param commitment The commitment to complete
/// @param _nonce The nonce used for authwit
#[public]
fn transfer_public_to_commitment(
    from: AztecAddress,
    token_id: Field,
    commitment: Field,
    _nonce: Field,
) { /* ... */ }
```

### mint_to_public
```rust
/// @notice Mints a token to a public address
/// @dev Asserts that the caller is an authorized minter
/// @param to The address of the recipient
/// @param token_id The id of the token to mint
#[public]
fn mint_to_public(to: AztecAddress, token_id: Field) { /* ... */ }
```

### burn_public
```rust
/// @notice Burns a token from a public address
/// @dev Asserts `from` owns the token publicly, clears the public owner, and burns the token
/// @param from The address of the owner
/// @param token_id The id of the token to burn
/// @param _nonce The nonce used for authwit
#[public]
fn burn_public(from: AztecAddress, token_id: Field, _nonce: Field) { /* ... */ }
```

## View Functions

### public_get_name
```rust
/// @notice Returns the name of the NFT collection
/// @return name The name of the NFT collection
#[public]
#[view]
fn public_get_name() -> FieldCompressedString { /* ... */ }
```

### public_get_symbol
```rust
/// @notice Returns the symbol of the NFT collection
/// @return symbol The symbol of the NFT collection
#[public]
#[view]
fn public_get_symbol() -> FieldCompressedString { /* ... */ }
```

### public_owner_of
```rust
/// @notice Returns the owner of a token by id
/// @param token_id The id of the token
/// @return owner The owner of the token
#[public]
#[view]
fn public_owner_of(token_id: Field) -> AztecAddress { /* ... */ }
```

## Utility Functions

### get_private_nfts
```rust
/// @notice Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was reached
/// @dev Starts getting the notes from page with index `page_index`
/// @dev Zero values in the array are placeholder values for non-existing notes
/// @param owner The address of the owner
/// @param page_index The index of the page to start getting notes from
/// @return owned_nft_ids An array of token IDs owned by `owner`
/// @return page_limit_reached A flag indicating whether a page limit was reached
#[utility]
unconstrained fn get_private_nfts(
    owner: AztecAddress,
    page_index: u32,
) -> ([Field; MAX_NOTES_PER_PAGE], bool) { /* ... */ }
```

