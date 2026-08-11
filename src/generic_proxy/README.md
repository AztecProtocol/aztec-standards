# GenericProxy Contract (internal test utility)

> **Note**: `GenericProxy` is an **internal test utility**, not a standard. It is used by the Noir test suites of the Token, NFT, MultiToken, and Vault contracts and carries no stability or compatibility guarantees. Do not build on it.

The `GenericProxy` contract forwards a private call to an arbitrary target contract and function selector. Tests deploy it to exercise flows where the caller must be a **contract** rather than an account — e.g. verifying `msg_sender`-sensitive behavior, authwit validation from a contract caller, or completing partial-note commitments from a contract context.

## Functions

```rust
#[external("private")]
fn forward_private_N(target: AztecAddress, selector: FunctionSelector, args: [Field; N])
```

One variant exists per argument arity `N` (0–8), plus `forward_private_4_and_return`, which returns the callee's return value as a `Field`. Variants are added as tests need them.

## Usage (from a Noir test)

```rust
use generic_proxy::GenericProxy;

let proxy = env.deploy("@generic_proxy/GenericProxy").without_initializer();
GenericProxy::at(proxy).forward_private_4(target, selector, args);
```
