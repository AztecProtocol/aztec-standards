use aztec::macros::aztec;

/// ARC-403 authorization-hook interface (DRAFT).
///
/// The sole purpose of this contract is to serve as a Noir interface: it is the canonical
/// set of signatures that ARC-403 authorization contracts must conform to. The Token
/// contract in this repository calls these entry points on its configured `auth_contract`
/// before every hooked transfer or burn. The id-bearing variant used by MultiToken lives
/// in the `arc403_multitoken_interface` sub-package.
///
/// This stub-contract-as-interface pattern follows aztec-packages' own
/// `noir-contracts/contracts/protocol_interface` packages (FeeJuice,
/// ContractInstanceRegistry), which use empty-bodied `#[aztec]` contracts for the same
/// purpose. The generated call interface depends only on function names, parameter
/// types, and the `#[external]` attributes — never on bodies.
///
/// The ARC-403 specification is a draft under active discussion:
/// https://forum.aztec.network/t/arc-403-authtoken/7887
/// This interface tracks the draft as implemented by the tokens in this repository and
/// may change if the specification changes.
///
/// The function bodies below are empty stubs — this artifact exists to define the ABI,
/// not to be deployed. WARNING: deploying this contract as-is and wiring it as a token's
/// `auth_contract` would produce an allow-all authorizer that never denies anything.
/// Implementations provide their own authorization logic (allowlists, KYC attestations,
/// transfer caps, pausability, ...) behind these exact signatures, and must revert to
/// deny the triggering token operation.
#[aztec]
pub contract Arc403Authorizer {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Called by a fungible token in private context before a hooked operation
    /// @dev Revert to deny the operation. `selector` is the token function's own selector.
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("private")]
    fn authorize_private(from: AztecAddress, amount: u128, selector: Field) {
        let _ = (from, amount, selector);
    }

    /// @notice Called by a fungible token in public context before a hooked operation
    /// @dev Revert to deny the operation. `selector` is the token function's own selector.
    /// @param from The address whose balance is being spent
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    fn authorize_public(from: AztecAddress, amount: u128, selector: Field) {
        let _ = (from, amount, selector);
    }
}
