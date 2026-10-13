pub mod types;
pub mod test;

use aztec::macros::aztec;

#[aztec]
pub contract NFT {
    // aztec library
    use aztec::{
        authwit::auth::compute_authwit_nullifier,
        macros::{
            events::event,
            functions::{authorize_once, external, initializer, internal, only_self, view},
            storage::storage,
        },
        messages::delivery::MessageDelivery,
        note::{
            constants::MAX_NOTES_PER_PAGE, note_getter_options::NoteGetterOptions,
            note_interface::NoteProperties, note_viewer_options::NoteViewerOptions,
        },
        protocol::{address::AztecAddress, traits::FromField},
        state_vars::{Map, Owned, PrivateSet, PublicImmutable, PublicMutable, StateVariable},
        utils::comparison::Comparator,
    };
    // compression library
    use compressed_string::FieldCompressedString;
    // nft note structs
    use crate::types::nft_note::{NFTNote, PartialNFTNote};

    /// @param symbol The symbol of the NFT
    /// @param name The name of the NFT
    /// @param private_nfts The private NFT notes; `private_nfts.at(owner)` is one account's note set
    /// @param nft_exists A map from token ID to a boolean indicating if the NFT exists
    /// @param public_owners A map from token ID to the public owner of the NFT
    /// @param minter The address that can mint
    #[storage]
    struct Storage<Context> {
        symbol: PublicImmutable<FieldCompressedString, Context>,
        name: PublicImmutable<FieldCompressedString, Context>,
        private_nfts: Owned<PrivateSet<NFTNote, Context>, Context>,
        nft_exists: Map<Field, PublicMutable<bool, Context>, Context>,
        public_owners: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
    }

    // Sentinel address used in Transfer events to represent the private side of a balance change.
    // sha224sum 'PRIVATE_ADDRESS'
    global PRIVATE_ADDRESS_MAGIC_VALUE: AztecAddress =
        AztecAddress::from_field(0x1ea7e01501975545617c2e694d931cb576b691a4a867fed81ebd3264);

    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
    }

    /// @dev Initializes the token with a minter
    /// @param name The name of the NFT
    /// @param symbol The symbol of the NFT
    /// @param minter The address of the minter
    #[external("public")]
    #[initializer]
    fn constructor_with_minter(name: str<31>, symbol: str<31>, minter: AztecAddress) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.minter.initialize(minter);
    }

    /** ==========================================================
     * ========================= PRIVATE =========================
     * ======================================================== */

    /// @notice Transfers token by id from private owner to a public owner
    /// @dev Removes token from private owner, and enqueues a public call to update the public owner
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.update_public_token_owner_from_zero_internal(to, token_id);
    }

    /// @notice Transfers token by id from private owner to a public owner, with a return commitment for `from`
    /// @dev Lets a contract take custody of the token publicly and later hand it back to `from` privately via
    ///      `transfer_public_to_commitment`. The commitment is owned by `from` and completable only by `msg_sender`
    ///      (the integrating contract when called through an authwit). Complete it at most once (see README).
    /// @param from The address of the sender, and the owner of the commitment
    /// @param to The address of the new public owner
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    /// @return commitment The return commitment owned by `from`
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public_with_commitment(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) -> Field {
        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.update_public_token_owner_from_zero_internal(to, token_id);
        let completer = self.msg_sender();
        let commitment = self.internal._initialize_transfer_commitment(from, completer);
        commitment.commitment
    }

    /// @notice Transfers token by id from private owner to another private owner
    /// @dev Removes token by id from private owner, and sends a nft note with id to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        self.internal._remove_private_token_owner(from, token_id);
        self.internal._update_private_token_owner(to, token_id);
    }

    /// @notice Transfers token by id from private owner to a commitment, completing it in private
    /// @dev `msg_sender` must be the commitment's completer, and the commitment must come from an earlier block.
    ///      The token id is published.
    /// @param from The address of the sender
    /// @param token_id The id of the token to transfer
    /// @param commitment The commitment to complete
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        self.internal._remove_private_token_owner(from, token_id);
        let completer = self.msg_sender();
        PartialNFTNote { commitment }.complete_from_private(
            self.context,
            completer,
            self.storage.private_nfts.get_storage_slot(),
            token_id,
        );
    }

    /// @notice Transfers token by id from public owner to private owner
    /// @dev Enqueues a public call to remove the public owner, and emits a nft note with id to the recipient
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_public_to_private(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        self.enqueue_self.transfer_public_to_private_internal(from, token_id);
        self.internal._update_private_token_owner(to, token_id);
    }

    /// @notice Creates a commitment owned by `to` that only `completer` can complete
    /// @dev `to` discovers it through an unconstrained message, so `to` (or a contract acting for it) should call this.
    ///      The completer fills it, as `msg_sender`, with `transfer_public_to_commitment` or
    ///      `transfer_private_to_commitment`, and chooses the token id. Complete it at most once (see README).
    /// @param to The owner of the commitment
    /// @param completer The only address allowed to complete the commitment
    /// @return commitment The commitment
    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.commitment
    }

    /** ==========================================================
     * ========================= PUBLIC ==========================
     * ======================================================== */

    /// @notice Transfers a token from one public owner to another public owner
    /// @dev Asserts `from` owns the token publicly and updates the public owner
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param token_id The id of the token to transfer
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_public(
        from: AztecAddress,
        to: AztecAddress,
        token_id: Field,
        _nonce: Field,
    ) {
        self.internal._validate_public_token_owner(from, token_id);

        self.internal._update_public_token_owner(to, token_id);
        self.emit(Transfer { from, to, token_id });
    }

    /// @notice Transfers a token from public owner to a commitment
    /// @dev Asserts `from` owns the token publicly. `msg_sender` must be the commitment's completer: the caller, which
    ///      is not `from` under an authwit.
    /// @param from The address of the sender
    /// @param token_id The id of the token to transfer
    /// @param commitment The commitment to complete
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn transfer_public_to_commitment(
        from: AztecAddress,
        token_id: Field,
        commitment: Field,
        _nonce: Field,
    ) {
        self.internal._validate_public_token_owner(from, token_id);

        self.internal._update_public_token_owner(AztecAddress::zero(), token_id);
        let completer = self.msg_sender();
        PartialNFTNote { commitment }.complete(
            self.context,
            completer,
            self.storage.private_nfts.get_storage_slot(),
            token_id,
        );
        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, token_id });
    }

    /// @notice Clears the public owner and emits a Transfer event for a public-to-private transfer
    /// @param from The address of the sender
    /// @param token_id The id of the token to transfer
    #[external("public")]
    #[only_self]
    fn transfer_public_to_private_internal(from: AztecAddress, token_id: Field) {
        self.internal._validate_public_token_owner(from, token_id);
        self.internal._update_public_token_owner(AztecAddress::zero(), token_id);
        self.emit(Transfer { from, to: PRIVATE_ADDRESS_MAGIC_VALUE, token_id });
    }

    /// @notice Initializes the public token owner from zero address
    /// @param to The address of the new owner
    /// @param token_id The id of the token to update
    #[external("public")]
    #[only_self]
    fn update_public_token_owner_from_zero_internal(to: AztecAddress, token_id: Field) {
        self.internal._update_public_token_owner(to, token_id);
        self.emit(Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to, token_id });
    }

    /// @notice Finalizes a mint to private by registering the token and emitting a Transfer event
    /// @param token_id The id of the token to mint
    #[external("public")]
    #[only_self]
    fn mint_to_private_internal(token_id: Field) {
        self.internal._set_nft_exists(token_id, true);
        self.emit(
            Transfer { from: AztecAddress::zero(), to: PRIVATE_ADDRESS_MAGIC_VALUE, token_id },
        );
    }

    /// @notice Finalizes a burn from private by deregistering the token and emitting a Transfer event
    /// @param token_id The id of the token to burn
    #[external("public")]
    #[only_self]
    fn burn_private_internal(token_id: Field) {
        self.internal._set_nft_exists(token_id, false);
        self.emit(
            Transfer { from: PRIVATE_ADDRESS_MAGIC_VALUE, to: AztecAddress::zero(), token_id },
        );
    }

    /** ==========================================================
     * ====================== VIEW FUNCTIONS =====================
     * ======================================================== */

    /// @return name The name of the NFT collection
    #[external("public")]
    #[view]
    fn public_get_name() -> pub FieldCompressedString {
        self.storage.name.read()
    }

    /// @return symbol The symbol of the NFT collection
    #[external("public")]
    #[view]
    fn public_get_symbol() -> pub FieldCompressedString {
        self.storage.symbol.read()
    }

    /// @return owner The owner of a token by id
    #[external("public")]
    #[view]
    fn public_owner_of(token_id: Field) -> pub AztecAddress {
        self.storage.public_owners.at(token_id).read()
    }

    /** ==========================================================
     * ===================== UNCONSTRAINED =======================
     * ======================================================== */

    /// @notice Returns an array of token IDs owned by `owner` in private and a flag indicating whether a page limit was reached
    /// @dev Starts getting the notes from page with index `page_index`
    /// @dev Zero values in the array are placeholder values for non-existing notes
    /// @param owner The address of the owner
    /// @param page_index The index of the page to start getting notes from
    /// @return owned_nft_ids An array of token IDs owned by `owner`
    /// @return page_limit_reached A flag indicating whether a page limit was reached
    #[external("utility")]
    unconstrained fn get_private_nfts(
        owner: AztecAddress,
        page_index: u32,
    ) -> pub ([Field; MAX_NOTES_PER_PAGE], bool) {
        let offset = page_index * MAX_NOTES_PER_PAGE;
        let mut options = NoteViewerOptions::new();
        let nfts = self.storage.private_nfts.at(owner).view_notes(options.set_offset(offset));
        let mut owned_nft_ids = [0; MAX_NOTES_PER_PAGE];
        for i in 0..options.limit {
            if i < nfts.len() {
                owned_nft_ids[i] = nfts.get_unchecked(i).token_id;
            }
        }
        let page_limit_reached = nfts.len() == options.limit;
        (owned_nft_ids, page_limit_reached)
    }

    /** ==========================================================
    * ======================= MINTABLE ==========================
    * ======================================================== */

    /// @notice Mints a token to a private address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The id of the token to mint
    #[external("private")]
    fn mint_to_private(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.enqueue_self.mint_to_private_internal(token_id);
        self.storage.private_nfts.at(to).insert(NFTNote { token_id }).deliver(
            MessageDelivery::onchain_constrained(),
        );
    }

    /// @notice Mints a token to a public address
    /// @dev Asserts that the caller is an authorized minter
    /// @param to The address of the recipient
    /// @param token_id The id of the token to mint
    #[external("public")]
    fn mint_to_public(to: AztecAddress, token_id: Field) {
        assert(token_id != 0, "zero token ID not supported");
        _validate_minter(self.msg_sender(), self.storage.minter.read());

        self.internal._set_nft_exists(token_id, true);
        self.storage.public_owners.at(token_id).write(to);
        self.emit(Transfer { from: AztecAddress::zero(), to, token_id });
    }

    /** ==========================================================
     * ======================= BURNABLE ==========================
     * ======================================================== */

    /// @notice Burns a token from a private address
    /// @dev Removes the token from `from`'s private notes and enqueues a public call to burn it
    /// @param from The address of the owner
    /// @param token_id The id of the token to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn burn_private(from: AztecAddress, token_id: Field, _nonce: Field) {
        self.internal._remove_private_token_owner(from, token_id);
        self.enqueue_self.burn_private_internal(token_id);
    }

    /// @notice Burns a token from a public address
    /// @dev Asserts `from` owns the token publicly, clears the public owner, and burns the token
    /// @param from The address of the owner
    /// @param token_id The id of the token to burn
    /// @param _nonce The nonce used for authwitness
    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn burn_public(from: AztecAddress, token_id: Field, _nonce: Field) {
        self.internal._validate_public_token_owner(from, token_id);
        self.internal._update_public_token_owner(AztecAddress::zero(), token_id);
        self.internal._set_nft_exists(token_id, false);
        self.emit(Transfer { from, to: AztecAddress::zero(), token_id });
    }

    /// @notice Cancels a private authentication witness the caller previously granted
    /// @dev Emits the authwit nullifier for `(msg_sender, inner_hash)`, so an authwit that has been
    ///      granted but not yet consumed can no longer be used. Matches the upstream NFT contract.
    /// @param inner_hash The inner hash of the authwit to cancel
    #[external("private")]
    fn cancel_authwit(inner_hash: Field) {
        let on_behalf_of = self.msg_sender();
        let nullifier = compute_authwit_nullifier(on_behalf_of, inner_hash);
        self.context.push_nullifier_unsafe(nullifier);
    }

    /** ==========================================================
     * ================= TOKEN LIBRARIES =========================
     * ======================================================== */

    /// @notice Sets the existence of a token
    /// @dev Asserts token does not exist when setting `exists` to true (minting) and that token exists when setting `exists` to false (burning)
    /// @param token_id The id of the token to set
    /// @param exists The new exists value
    #[internal("public")]
    fn _set_nft_exists(token_id: Field, exists: bool) {
        if exists {
            assert(!self.storage.nft_exists.at(token_id).read(), "token already exists");
        } else {
            assert(self.storage.nft_exists.at(token_id).read(), "token does not exist");
        }
        self.storage.nft_exists.at(token_id).write(exists);
    }

    /// @notice Initializes a transfer commitment
    /// @param to The owner of the commitment
    /// @param completer The only address allowed to complete the commitment
    /// @return commitment The commitment
    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialNFTNote {
        NFTNote::partial(to, self.context, to, completer)
    }

    /// @notice Updates the private token owner
    /// @param to The address of the recipient
    /// @param token_id The id of the token to update
    #[internal("private")]
    fn _update_private_token_owner(to: AztecAddress, token_id: Field) {
        let new_note = NFTNote { token_id };
        self.storage.private_nfts.at(to).insert(new_note).deliver(
            MessageDelivery::onchain_constrained(),
        );
    }

    /// @notice Removes the private token owner
    /// @param from The address of the owner
    /// @param token_id The id of the token to remove
    #[internal("private")]
    fn _remove_private_token_owner(from: AztecAddress, token_id: Field) {
        let notes = self.storage.private_nfts.at(from).pop_notes(NoteGetterOptions::new()
            .select(NFTNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "nft not found");
    }

    /// @notice Updates the public token owner
    /// @param to The address of the recipient
    /// @param token_id The id of the token to update
    #[internal("public")]
    fn _update_public_token_owner(to: AztecAddress, token_id: Field) {
        self.storage.public_owners.at(token_id).write(to);
    }

    /// @notice Validates that the caller is the owner of a token
    /// @param from The address of the sender
    /// @param token_id The id of the token to validate
    #[internal("public")]
    fn _validate_public_token_owner(from: AztecAddress, token_id: Field) {
        let owner = self.storage.public_owners.at(token_id).read();
        assert(owner.eq(from), "caller is not owner");
    }

    /// @notice Validates that the caller is an authorized minter
    /// @param sender The address of the caller
    /// @param minter The address of the minter
    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }
}
