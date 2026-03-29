import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    var displayLabel: String

    /// The shared portion of the UID that identifies the physical hardware.
    /// For Apple Studio Displays: "AppleUSBAudioEngine:Apple Inc.:Studio Display:A1498802E:8,9"
    /// and "AppleUSBAudioEngine:Apple Inc.:Studio Display Microphone:A1498802E:6,7"
    /// share the serial "A1498802E". We extract up to (but not including) the last colon-segment.
    var hardwareGroupKey: String {
        // For Apple USB Audio UIDs like "AppleUSBAudioEngine:Apple Inc.:Studio Display:A1498802E:8,9"
        // group by vendor + serial: parts[0]:parts[1]:parts[3]
        let parts = uid.split(separator: ":")
        if parts.count >= 4 {
            return "\(parts[0]):\(parts[1]):\(parts[3])"
        }
        // For built-in devices like "MacBook Pro Speakers" / "MacBook Pro Microphone",
        // or virtual devices like "Microsoft Teams Audio" that share the same name stem,
        // group by stripping known suffixes to find a common base name.
        return nameBasedGroupKey
    }

    /// Strips known audio suffixes to produce a grouping key from the device name.
    var nameBasedGroupKey: String {
        let suffixes = [" Speakers", " Speaker", " Microphone", " Mic", " Audio"]
        var base = name
        for suffix in suffixes {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        return "name:\(base)"
    }
}

/// A group of devices that belong to the same physical hardware (e.g., one Studio Display)
struct DeviceGroup: Identifiable {
    let id: String // the hardware group key
    let physicalName: String // e.g., "Studio Display"
    let serial: String // e.g., "A1498802E"
    let output: AudioDevice?
    let input: AudioDevice?
    var customName: String? // user-assigned name

    var displayLabel: String {
        customName ?? physicalName
    }
}
