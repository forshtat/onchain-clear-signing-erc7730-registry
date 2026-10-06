// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./structs/RegistrationRecord.sol";
import "./structs/ResolvedRecord.sol";

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface for an Ethereum registry that maps ERC-7730 binding context IDs
///         to attester-attested descriptors backed by an arbitrary off-chain attestation mechanism.
interface IClearSigningRegistry {

    /// @notice Emitted when an attester deletes the record for a context.
    /// @param attester       The attester whose record was deleted.
    /// @param contextKeyId   The context ID affected.
    event RecordDeleted(address indexed attester, bytes32 indexed contextKeyId);

    /// @notice Emitted when an attester writes the record for a context, replacing any previous one.
    /// @param attester       The attester whose record was set.
    /// @param contextKeyId   The context ID affected.
    /// @param record         The newly active record.
    event RecordWritten(address indexed attester, bytes32 indexed contextKeyId, RegistrationRecord record);

    /// @notice Emitted when an attester's active attestation set for a context ID changes.
    /// @param attester                  The attester whose active attestation set changed.
    /// @param contextKeyId                 The context ID affected.
    /// @param attestationSetId          The newly active attestation set ID, or bytes32(0) when cleared.
    /// @param previousAttestationSetId  The previously active attestation set ID.
    /// @param descriptorHash            The newly attested descriptor hash, or bytes32(0) when cleared.
    /// @param descriptorSchemaMajor               The schema MAJOR of the affected active record.
    event AttestationUpdated(
        address indexed attester,
        bytes32 indexed contextKeyId,
        bytes32 indexed attestationSetId,
        bytes32         previousAttestationSetId,
        bytes32         descriptorHash,
        uint256         descriptorSchemaMajor
    );

    /// @notice Emitted exactly once per attestation set when its write-once metadata is stored during registration.
    ///
    /// @param attester          The attester the attestation set is registered under.
    /// @param attestationSetId  The registered attestation set ID.
    /// @param descriptorHash    The attested descriptor hash.
    /// @param descriptorSchemaMajor       The declared schema MAJOR.
    /// @param attestationIds    The full contents of the attestation set.
    event AttestationRegistered(
        address indexed attester,
        bytes32 indexed attestationSetId,
        bytes32 indexed descriptorHash,
        uint256         descriptorSchemaMajor,
        AttestationIdentifier[] attestationIds
    );

    /// @notice Emitted the first time a MirrorList is stored on-chain, carrying its full URI contents.
    /// @param mirrorListId  The content hash of the published MirrorList.
    /// @param uris          The published URI list.
    event MirrorListPublished(bytes32 indexed mirrorListId, string[] uris);

    /// @notice Emitted when an attester invalidates their current EIP-712 nonce via 'invalidateNonce'.
    ///         Indicates cancelling any outstanding signature using the old nonce value.
    /// @param attester  The attester whose nonce was invalidated.
    /// @param newNonce  The next valid nonce after the invalidation.
    event NonceInvalidated(address indexed attester, uint256 newNonce);

    /// @notice Emitted when an attester's active MirrorList for a descriptor changes.
    /// @param attester                The attester updating their list.
    /// @param descriptorHash          The descriptor hash.
    /// @param descriptorMirrorListId  The new MirrorList ID.
    event DescriptorMirrorListUpdated(
        address indexed attester,
        bytes32 indexed descriptorHash,
        bytes32 indexed descriptorMirrorListId
    );

    /// @notice Emitted when an attester's active MirrorList for an attestation set changes.
    /// @param attester                 The attester updating their list.
    /// @param attestationSetId         The attestation set ID.
    /// @param attestationMirrorListId  The new MirrorList ID.
    event AttestationMirrorListUpdated(
        address indexed attester,
        bytes32 indexed attestationSetId,
        bytes32 indexed attestationMirrorListId
    );

    /// @notice Emitted when an attester's profile document URI changes.
    /// @param attester    The attester whose profile changed.
    /// @param profileURI  The new profile document URI.
    event AttesterProfileUpdated(address indexed attester, string profileURI);

    /// @notice Emitted when an attester changes its declared attestation formats.
    /// @param attester              The attester whose declaration changed.
    /// @param attestationFormatIds  The new declared format IDs, empty when cleared.
    event AttestationFormatIdsUpdated(address indexed attester, bytes32[] attestationFormatIds);

    /// @notice Emitted when an attester sets or clears its revocation controller for an attestation format.
    /// @param attester             The attester whose controller changed.
    /// @param attestationFormatId  The attestation format the controller applies to.
    /// @param controller           The new controller address, or address(0) when cleared.
    event RevocationControllerUpdated(
        address indexed attester,
        bytes32 indexed attestationFormatId,
        address         controller
    );

    /// @notice Thrown when no registration records are passed.
    error EmptyRecords();

    /// @notice Thrown when 'contextKeyIds' and 'registrationRecords' differ in length.
    error ArrayLengthMismatch();

    /// @notice Thrown when a record declares no descriptor schema MAJOR versions.
    error EmptyDescriptorSchemaMajors();

    /// @notice Thrown when an empty key array is passed to an update function.
    error EmptyKeys();

    /// @notice Thrown when bytes32(0) is passed where a descriptor hash is required.
    error ZeroDescriptorHash();

    /// @notice Thrown when bytes32(0) is passed where an attestation format ID is required.
    error ZeroAttestationFormat();

    /// @notice Thrown when two attestations of the same descriptor declare the same format ID.
    error DuplicateAttestationFormat(bytes32 attestationFormatId);

    /// @notice Thrown when a descriptor declares a zero schema MAJOR version.
    error ZeroDescriptorSchemaMajor();

    /// @notice Thrown when bytes32(0) is passed where an attestation ID is required.
    error ZeroAttestationId();

    /// @notice Thrown when a descriptor's contextKeyIds is empty.
    error EmptyContextKeyIds();

    /// @notice Thrown when a descriptor's attestationIds is empty.
    error EmptyAttestationIds();

    /// @notice Thrown when a registration reuses an attestation set ID whose stored record
    ///         does not match the incoming descriptor.
    error AttestationIdAlreadyUsed(bytes32 attestationId);

    /// @notice Thrown when 'updateDescriptorMirrorList' names a descriptor hash the
    ///         attester has never registered.
    error UnknownDescriptor(bytes32 descriptorHash);

    /// @notice Thrown when 'updateAttestationMirrorList' names an attestation set ID the
    ///         attester has never registered.
    error UnknownAttestationSet(bytes32 attestationSetId);

    /// @notice Thrown when an empty URI list is passed to publishMirrorLists.
    error EmptyMirrorList();

    /// @notice Thrown when a MirrorList id passed to 'writeRecords' was
    ///         never published via 'publishMirrorLists'.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice Thrown when the registration is submitted by an address other than
    ///         the attester and the provided EIP-712 registration signature does
    ///         not verify against the attester.
    error InvalidRegistrationSignature();

    /// @notice Write the caller's registration records, each for one or more contexts.
    ///
    ///         The attester produces the signed attestation artifacts locally and stores them off-chain.
    ///         Every record SHOULD reference at least one standard ERC-8176 EAS off-chain attestation.
    ///         The registry itself is attestation-agnostic and does not validate any attestation's
    ///         signature or content, nor the declared descriptor hash.
    ///
    ///         Each attester has at most one record per context. Writing a record replaces the
    ///         previous one at that context, for every descriptor schema MAJOR it declared.
    ///         To stop serving a record without a replacement, see 'deleteRecords'.
    ///
    ///         Both MirrorLists referenced by a record must already be published, see 'publishMirrorLists'.
    ///
    /// @param contextKeyIds        One array of context IDs per record: 'registrationRecords[i]'
    ///                             is written for every ID in 'contextKeyIds[i]'.
    /// @param registrationRecords  The records to write. Must be the same length as 'contextKeyIds'.
    function writeRecords(
        bytes32[][] calldata contextKeyIds,
        RegistrationRecord[] calldata registrationRecords
    ) external;

    /// @notice Delete the caller's record at every listed context.
    ///         A context without a record is skipped silently, and still emits 'RecordDeleted'.
    /// @param contextKeyIds  The context IDs whose records are deleted. Must not be empty.
    function deleteRecords(bytes32[] calldata contextKeyIds) external;

    /// @notice Publish a batch of MirrorLists on-chain.
    /// @param uriLists  The URI lists to publish. No list may be empty.
    function publishMirrorLists(string[][] calldata uriLists) external;

    /// @notice Resolve the records of the given attesters at the given contexts.
    ///
    ///         Returns one entry per '(attester, contextKeyId)' pair that currently has a record, ordered by
    ///         attester and then by context. Both parameters are lookup keys: an empty array yields no results.
    ///
    ///         The registry applies no filters. A wallet picks the schema MAJOR versions it supports from
    ///         'descriptorSchemaMajors', and may use the attester's declared formats
    ///         (see 'getAttestationFormatIds') and revocation controllers (see 'getRevocationController').
    ///
    /// @param attesters      Attester addresses trusted by the wallet.
    /// @param contextKeyIds  Candidate context IDs to look up.
    /// @return resolved  The records found.
    function resolveRecords(address[] calldata attesters, bytes32[] calldata contextKeyIds)
        external view returns (ResolvedRecord[] memory resolved);

    /// @notice Return the URI list for a given MirrorList ID, or an empty array if it was never published.
    ///
    /// @param mirrorListId  The MirrorList content hash.
    ///
    /// @return uris  The full URI list.
    function getMirrorListById(bytes32 mirrorListId) external view returns (string[] memory uris);

    /// @notice The next EIP-712 nonce for all relayed calls by the given attester.
    /// @param attester  The queried attester address.
    /// @return nonce  The next unused nonce.
    function getNonce(address attester) external view returns (uint256 nonce);

    /// @notice Invalidates the caller's current EIP-712 nonce and cancel any outstanding signature using that nonce.
    function invalidateNonce() external;

    /// @notice Update the MirrorList for existing descriptors without re-issuing attestations.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param descriptorHashes The hashes of the descriptors to update. Every hash MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownDescriptor' otherwise.
    /// @param descriptorMirrorListId The id of an already-published MirrorList to rotate
    ///                      to — see 'publishMirrorLists'. Reverts with 'UnknownMirrorList' if unpublished.
    /// @param signature EIP-712 signature authorizing this update.
    function updateDescriptorMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        bytes32 descriptorMirrorListId,
        bytes calldata signature
    ) external;

    /// @notice Update the MirrorList for existing attestation sets without re-registration.
    /// @param attester The attester whose MirrorList pointers are being updated.
    /// @param attestationSetIds The IDs of the attestation sets to update. Every ID MUST have
    ///                      been registered by the attester before, reverting with
    ///                      'UnknownAttestationSet' otherwise.
    /// @param attestationMirrorListId The id of an already-published MirrorList to rotate
    ///                      to — see 'publishMirrorLists'. Reverts with 'UnknownMirrorList' if unpublished.
    /// @param signature EIP-712 signature authorizing this update (ignored if msg.sender == attester).
    function updateAttestationMirrorList(
        address attester,
        bytes32[] calldata attestationSetIds,
        bytes32 attestationMirrorListId,
        bytes calldata signature
    ) external;

    /// @notice Set the caller's profile document URI — a self-declared "business card" pointing at its JSON profile.
    ///
    ///         The profile is display-only metadata and MUST NOT be used as trust input.
    ///         Wallets select and trust attesters by address ONLY.
    ///         Consumers SHOULD render profile data only for attesters they already trust.
    ///
    /// @param profileURI  The new profile document URI.
    function setAttesterProfileURI(string calldata profileURI) external;

    /// @notice The attester's current profile document URI, or an empty string if unset.
    /// @param attester  The queried attester address.
    /// @return profileURI  The profile document URI.
    function getAttesterProfileURI(address attester) external view returns (string memory profileURI);

    /// @notice Declare the attestation formats the caller uses consistently across all of its records,
    ///         or clear the declaration with an empty array.
    ///
    ///         A declaration only: the registry does not check records against it. Wallets MAY use it to skip
    ///         attesters that issue no format they can verify, and attesters that stray from their own
    ///         declaration can simply be ignored by wallets. Like a revocation controller and unlike the
    ///         profile, it is a functional hint, not display-only data.
    ///
    /// @param attestationFormatIds  The declared attestation format IDs.
    function setAttestationFormatIds(bytes32[] calldata attestationFormatIds) external;

    /// @notice The attester's declared attestation formats, or an empty array if none.
    /// @param attester  The queried attester address.
    /// @return attestationFormatIds  The declared attestation format IDs.
    function getAttestationFormatIds(address attester) external view returns (bytes32[] memory attestationFormatIds);

    /// @notice Declare the caller's revocation controller for an attestation format, or clear it with address(0).
    ///
    ///         A controller is an optional contract implementing 'IRevocationController' that wallets MAY ask
    ///         whether an attestation of this format was revoked. The registry never calls it, does not
    ///         interpret the attestation identifiers it accepts, and does not check that it is a contract.
    ///         A controller is chosen by the attester, so wallets that use it extend the trust they already
    ///         place in that attester and nothing more.
    ///
    /// @param attestationFormatId  The attestation format the controller applies to.
    /// @param controller           The controller address, or address(0) to clear.
    function setRevocationController(bytes32 attestationFormatId, address controller) external;

    /// @notice The attester's revocation controller for an attestation format, or address(0) if none.
    /// @param attester             The queried attester address.
    /// @param attestationFormatId  The queried attestation format.
    /// @return controller  The controller address.
    function getRevocationController(address attester, bytes32 attestationFormatId)
        external view returns (address controller);
}
