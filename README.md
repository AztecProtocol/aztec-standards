# Aztec Standards

[![npm version](https://img.shields.io/npm/v/@aztec-foundation/aztec-standards.svg)](https://www.npmjs.com/package/@aztec-foundation/aztec-standards)

Aztec Standards is a comprehensive collection of reusable, standardized contracts for the Aztec Network. It provides a robust foundation of token primitives and utilities that support both private and public operations, empowering developers to build innovative privacy-preserving applications with ease.

## ⚠️ Security Status: Unaudited

> [!WARNING]
> **This code has not been audited. Do not use it in production or to secure assets of value.**
>
> The contracts in this repository are experimental, unaudited software under active development. They have not undergone any external security review, audit, or formal verification, and they may contain bugs, security vulnerabilities, or economic flaws that could result in the irrecoverable loss of funds.
>
> The software is provided on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied (see [LICENSE](LICENSE)). Anyone deploying or interacting with these contracts does so entirely at their own risk, and is responsible for obtaining their own independent security review. No representation is made that the code is free of defects, and nothing here should be relied upon as security, legal, or financial advice.
>
> This notice will be updated if and when an audit is completed.

## Development

**Prerequisite**: Start an Aztec local network in a separate terminal:
```bash
aztec start --local-network
```

**Tests**: `yarn test` runs Noir and JS tests. JS tests expect the network to be running at `http://localhost:8080` (or `NODE_URL`).

**Benchmarks**: `yarn bench` connects to the same running network.

Set `NODE_URL` to override the default (e.g. `http://localhost:9000`).

## Table of Contents
- [Security Status: Unaudited](#️-security-status-unaudited)
- [Development](#development)
- [Standards & Naming (AIP vs ARC)](#standards--naming-aip-vs-arc)
- [Dripper Contract](#dripper-contract)
- [Token Contract](#token-contract)
- [MultiToken Contract](#multitoken-contract)
- [Vault Contract](#vault-contract)
- [Vault Deployer Contract](#vault-deployer-contract)
- [NFT Contract](#nft-contract)
- [Escrow Standard Contract & Library](#escrow-standard-contract--library)
- [Scope & Maintenance](#scope--maintenance)
- [License](#license)

## Standards & Naming (AIP vs ARC)

Two proposal-numbering tracks appear in this repository, and they are not interchangeable:

- **AIP-x** — Aztec Improvement Proposals published as RFCs on the [Aztec forum](https://forum.aztec.network). This repository implements [AIP-20](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737) (Token) and [AIP-4626](https://forum.aztec.network/t/request-for-comments-aip-4626-tokenized-vault/8079) (Vault). Both are drafts under discussion, not ratified standards.
- **ARC-x** — Aztec Request for Comments, a separate track. The Token and MultiToken contracts implement [ARC-403](https://forum.aztec.network/t/arc-403-authtoken/7887), an optional authorization-hook extension (compliance checks on transfers via an external authorization contract). The ARC-403 spec is still under active discussion; the implementation here tracks the draft. The canonical hook interface lives in `src/arc403_interface`.

> [!CAUTION]
> The `Arc403Authorizer` and `Arc403MultiTokenAuthorizer` artifacts shipped with this package are **interface stubs with empty bodies**. They exist to define the ABI. Never deploy them or wire them as a token's `auth_contract` — an empty hook approves every operation. Deploy your own implementation of the interface instead.

There is no "AIP-403" — if you have seen that name, it refers to ARC-403.

## Dripper Contract

The `Dripper` contract provides a convenient faucet mechanism for minting tokens into private or public balances. Anyone can easily invoke the functions to request tokens for testing or development purposes.

📖 **[View detailed Dripper documentation](src/dripper/README.md)**

## Token Contract

The `Token` contract implements an ERC-20-like token with Aztec-specific privacy extensions. It supports transfers and interactions explicitly through private balances and public balances, offering full coverage of Aztec's confidentiality features.

We published the [AIP-20 Aztec Token Standard](https://forum.aztec.network/t/request-for-comments-aip-20-aztec-token-standard/7737) to the forum. Feel free to review and discuss the specification there. The token optionally implements the [ARC-403](https://forum.aztec.network/t/arc-403-authtoken/7887) authorization hook (draft).

📖 **[View detailed Token documentation](src/token_contract/README.md)**

## MultiToken Contract

The `MultiToken` contract implements an ERC-1155-like multi-token (many token ids under one contract) with Aztec-specific privacy extensions: per-id private and public balances, partial-note commitments for public→private transfers, and the [ARC-403](https://forum.aztec.network/t/arc-403-authtoken/7887) authorization hook (draft).

📖 **[View detailed MultiToken documentation](src/multitoken_contract/README.md)**

## Vault Contract

The `Vault` contract is a standalone yield-bearing vault that holds an underlying AIP-20 asset and issues AIP-20 share tokens to depositors. The vault and shares token are separate contracts — the vault manages deposit/withdraw/redeem logic while delegating share token operations (mint, burn, transfer) to an external AIP-20 `Token` contract configured with the vault as its minter.

We published the [AIP-4626: Tokenized Vault Standard](https://forum.aztec.network/t/request-for-comments-aip-4626-tokenized-vault/8079) to the forum. Feel free to review and discuss the specification there.

> [!WARNING]
> The Vault is **not production-ready**, even by this repository's unaudited standards. It is exposed to [reentrancy when the underlying asset token has an ARC-403 authorization hook configured](src/vault_contract/README.md) (its ordering-based protection does not hold, because the hook runs *during* a transfer, before balances move), and it has a known overflow issue in the asset↔share conversion logic plus known privacy limitations. No fix is currently scheduled — see its README before wrapping any hooked token.

📖 **[View detailed Vault documentation](src/vault_contract/README.md)**

## Vault Deployer Contract

The `VaultDeployer` contract deploys and links a `Vault` and its shares `Token` in a single transaction. It exists as a workaround until [public contract-instance registration](https://github.com/AztecProtocol/aztec-packages/issues/20771) lands upstream; without it, a vault and its shares token cannot be deployed and wired together atomically.

📖 **[View detailed Vault Deployer documentation](src/vault_deployer/README.md)**

## NFT Contract

The `NFT` contract implements an ERC-721-like non-fungible token with Aztec-specific privacy extensions. It supports transfers and interactions through both private and public ownership, offering full coverage of Aztec's confidentiality features for unique digital assets.

📖 **[View detailed NFT documentation](src/nft_contract/README.md)**

## Escrow Standard Contract & Library

The Escrow Standard contains two elements:
- Escrow Contract: a minimal private contract designed to have keys with which authorized callers can spend private balances of AIP-20 tokens and of the NFT contract in this repository.
- Logic Library: a set of contract library methods that standardizes and facilitates the management of Escrow contracts from another contract, a.k.a. the Logic contract. 

📖 **[View detailed Escrow documentation](src/escrow_contract/README.md)**

To see examples of Logic contract implementations, such as a linear vesting contract or a clawback escrow contract, go to [aztec-escrow-extensions](https://github.com/defi-wonderland/aztec-escrow-extensions).

## Scope & Maintenance

The contracts above are the complete, intended scope of this repository. The Aztec Foundation maintains them (dependency bumps, bug fixes, spec alignment), but **no new standards are planned unless there is clear ecosystem demand**. If you need a standard that isn't here — or want one of the draft specs (AIP-20, AIP-4626, ARC-403) pushed toward finalization — say so on the [Aztec forum](https://forum.aztec.network) or open a GitHub issue on this repository. Demand is what gets things built.

## License

Released under the [MIT License](LICENSE).
