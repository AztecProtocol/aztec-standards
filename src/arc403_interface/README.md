# ARC-403 Interface (draft)

This package defines the canonical interface for [ARC-403](https://forum.aztec.network/t/arc-403-authtoken/7887) authorization contracts — the compliance hook the `Token` and `MultiToken` contracts in this repository call on every hooked transfer and burn when an `auth_contract` is configured.

> **Draft status**: the ARC-403 specification is still under active discussion on the forum. This interface tracks the draft as implemented by the tokens in this repository and may change if the specification changes.

## Contracts

Noir limits each package to a single contract, so the two hook variants live in two packages under this directory:

- **`Arc403Authorizer`** (package `arc403_interface`, this directory) — the fungible-token hook:
  - `authorize_private(from: AztecAddress, amount: u128, selector: Field)` (private)
  - `authorize_public(from: AztecAddress, amount: u128, selector: Field)` (public)
- **`Arc403MultiTokenAuthorizer`** (package `arc403_multitoken_interface`, in [`multitoken/`](multitoken/)) — the multi-token (per-id) hook:
  - `authorize_private(from: AztecAddress, id: Field, amount: u128, selector: Field)` (private)
  - `authorize_public(from: AztecAddress, id: Field, amount: u128, selector: Field)` (public)

The function bodies in these packages are empty stubs: the artifacts define the ABI and are not meant to be deployed. **Never deploy the stubs as a real authorizer — an empty hook body approves everything.** To write an authorization contract, implement these exact signatures in your own contract and **revert to deny** the triggering token operation. The `selector` argument is the selector of the token function that invoked the hook, letting a policy distinguish e.g. burns from transfers.

### Why a stub contract?

This mirrors aztec-packages' own [`protocol_interface`](https://github.com/AztecProtocol/aztec-packages/tree/master/noir-projects/noir-contracts/contracts/protocol_interface) packages (FeeJuice, ContractInstanceRegistry), whose empty-bodied `#[aztec]` contracts exist purely to provide a generated Noir call interface. The `#[aztec]` macro derives the caller-side interface exclusively from function names, parameter types, and `#[external]` attributes — bodies are never read — so calls through a stub are byte-identical to calls through the real implementation. The alternative idiom (raw `FunctionSelector::from_signature` + `context.call_*_function`, as used by authwit) was considered and rejected: it leaves implementers with no compilable artifact to conform to, and forfeits compile-time type-checking at the token's call sites.

## Consuming the interface from Noir

```toml
arc403_interface = { git = "https://github.com/AztecProtocol/aztec-standards", directory = "src/arc403_interface" }
# or, for the per-id multi-token variant:
arc403_multitoken_interface = { git = "https://github.com/AztecProtocol/aztec-standards", directory = "src/arc403_interface/multitoken" }
```

```rust
use arc403_interface::Arc403Authorizer;
// e.g. from a contract that needs to call an authorizer:
Arc403Authorizer::at(auth_contract).authorize_public(from, amount, selector);
```

Test doubles used by this repository's own suites live in `src/token_contract/src/test/test_authorization_contract` and `src/multitoken_contract/src/test/multitoken_authorization_contract`; they are spy implementations of this interface.
