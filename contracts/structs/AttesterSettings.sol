// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./AttestationFormatSettings.sol";

/// @notice Self-declared settings of an attester, replaced as a whole by 'updateAttesterSettings'.
struct AttesterSettings {
    /// The profile document URI, a self-declared "business card" pointing at the attester's JSON profile.
    /// Display-only metadata that MUST NOT be used as trust input: wallets select and trust attesters by
    /// address ONLY, and SHOULD render profile data only for attesters they already trust.
    string profileURI;
    /// The attestation formats the attester commits to use consistently across all of its records.
    /// Unlike the profile this is a functional hint: the registry does not check records against it, wallets
    /// MAY use it to skip attesters that issue no format they can verify, and attesters that stray from
    /// their own declaration can simply be ignored by wallets.
    AttestationFormatSettings[] attestationFormats;
}
