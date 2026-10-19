/// Memory map of the CZ configuration space, derived from the vendor SDK
/// (`CZ_SHARED_DATA`) device channel:
///
/// - keymap: `totalKeyAreaSize (512) * (4 * profile + layer)`,
///   `usedKeyAreaSize (3 * maxKeyCount) = 384` bytes addressed;
/// - trigger: `1024 * profile`, 1024 bytes (8 bytes/key);
/// - func config / lighting: `64 * profile`, 64 bytes.
///
/// Profiles are 0-based and the device reports `profileCount = 4` for the
/// Ace 68 Turbo 16K.
public enum DeviceMemoryMap {
    /// Number of keymap layers per profile in the vendor SDK (`MAX_LAYER`).
    public static let layers = 4
    /// Keymap area reserved per layer, in bytes (`totalKeyAreaSize`).
    public static let totalKeyAreaSize = 512
    /// Bytes actually used by the keymap (`usedKeyAreaSize`, 3 bytes/key).
    public static let usedKeyAreaSize = 384
    public static let triggerAreaSize = 1024
    public static let funcConfigSize = 64
    public static let baseSize = 56

    public static func keymapOffset(profile: Int, layer: Int) -> Int {
        totalKeyAreaSize * (layers * profile + layer)
    }

    public static func triggerOffset(profile: Int) -> Int {
        triggerAreaSize * profile
    }

    public static func funcConfigOffset(profile: Int) -> Int {
        funcConfigSize * profile
    }
}
