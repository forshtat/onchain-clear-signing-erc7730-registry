struct MirrorList {
    /// The full list of URLs leading to the same contents using different network protocols.
    string[] urls;
    /// The declared non-enforceable list of network protocols used in the given mirror list.
    string[] networkProtocols;
}
