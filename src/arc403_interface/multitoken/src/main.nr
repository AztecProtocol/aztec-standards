use aztec::macros::aztec;

/// ARC-403 authorization-hook interface for multi-token (ERC-1155-like) contracts (DRAFT).
/// Identical to `arc403_interface`'s `Arc403Authorizer`, extended with the token `id`
/// being moved. See ../README.md for draft status and usage.
#[aztec]
pub contract Arc403MultiTokenAuthorizer {
    use aztec::{macros::functions::external, protocol::address::AztecAddress};

    /// @notice Called by a multi-token in private context before a hooked operation
    /// @dev Revert to deny the operation. `selector` is the token function's own selector.
    /// @param from The address whose balance is being spent
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("private")]
    fn authorize_private(from: AztecAddress, id: Field, amount: u128, selector: Field) {
        let _ = (from, id, amount, selector);
    }

    /// @notice Called by a multi-token in public context before a hooked operation
    /// @dev Revert to deny the operation. `selector` is the token function's own selector.
    /// @param from The address whose balance is being spent
    /// @param id The token id being moved
    /// @param amount The amount of tokens being moved
    /// @param selector The function selector of the token operation that triggered the hook
    #[external("public")]
    fn authorize_public(from: AztecAddress, id: Field, amount: u128, selector: Field) {
        let _ = (from, id, amount, selector);
    }
}
