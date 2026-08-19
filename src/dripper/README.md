# Dripper Contract

The `Dripper` contract provides a convenient faucet mechanism for minting tokens into private or public balances. Anyone can easily invoke the functions below to request tokens for testing or development purposes.

> [!WARNING]
> The Dripper is an **uncapped, permissionless minter**: `drip_to_public` / `drip_to_private` let *anyone* mint *any* amount (up to `u64::MAX` per call, repeatable) of any token for which the Dripper is the configured `minter`. Its only safety boundary is external — it must **never be granted `minter` on a token that holds real value**, on any network. It is a development/testing faucet only, and as a dev utility rather than a standard it is intentionally outside the repository's automated test scope.

## Public Functions

### drip_to_public
```rust
/// @notice Mints tokens into the public balance of the caller
/// @dev Caller obtains `amount` tokens in their public balance
/// @param token_address The address of the token contract
/// @param amount The amount of tokens to mint (u64, converted to u128 internally)
#[public]
fn drip_to_public(token_address: AztecAddress, amount: u64) { /* ... */ }
```

## Private Functions

### drip_to_private
```rust
/// @notice Mints tokens into the private balance of the caller
/// @dev Caller obtains `amount` tokens in their private balance
/// @param token_address The address of the token contract
/// @param amount The amount of tokens to mint (u64, converted to u128 internally)
#[private]
fn drip_to_private(token_address: AztecAddress, amount: u64) { /* ... */ }
```

## Usage

The Dripper contract is designed for testing and development environments where you need to quickly obtain tokens for experimentation. Simply call either function with the token contract address and the desired amount to receive tokens in your chosen balance type (public or private).
