// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./structs/RegistrationRecord.sol";

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

    /// @notice Thrown when no registration records are passed.
    error EmptyRecords();

    /// @notice Thrown when 'contextKeyIds' and 'registrationRecords' differ in length.
    error ArrayLengthMismatch();

    /// @notice Thrown when a record declares no descriptor schema MAJOR versions.
    error EmptyDescriptorSchemaMajors();

    /// @notice Thrown when a record declares no attestation format IDs.
    error EmptyAttestationFormatIds();

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

    /// @notice Resolve all active attestation sets for the specified query with a filter.
    ///         The request fields are:
    ///             1. The list of attesters trusted by the wallet.
    ///             2. The list of potential context IDs matching the relevant signature request.
    ///             3. The list of schema MAJOR versions supported by the wallet.
    ///             4. The list of attestation format IDs the wallet can verify.
    ///
    /// The 'attesters', 'contextKeyIds' and 'descriptorSchemaMajors' parameters are lookup keys - an empty array yields no results.
    /// An empty 'attestationFormatIds' or 'allowedPrefixes' array applies no filter for that parameter.
    ///
    /// A resolved descriptor is returned even if every one of its attestations is filtered out.
    ///
    /// @param attesters        Queried attester addresses trusted by the wallet.
    /// @param contextKeyIds       Candidate context IDs to look up.
    /// @param descriptorSchemaMajors     The schema MAJOR versions supported by the wallet.
    /// @param attestationFormatIds        Attestation format IDs to include, or empty array for all formats.
    /// @param allowedPrefixes  Raw string prefixes filtering the returned URI lists.
    ///                         e.g. ["ipfs:", "https:"].
    ///                         A URI is returned only if it starts with at least one of the prefixes.
    /// @return resolved   One 'ResolvedDescriptor' entry per active '(attester, contextKeyId, descriptorSchemaMajor)' record.
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextKeyIds,
        uint256[] calldata descriptorSchemaMajors,
        bytes32[] calldata attestationFormatIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved);

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
}
