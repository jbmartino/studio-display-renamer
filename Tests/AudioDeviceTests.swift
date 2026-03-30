import Testing
@testable import StudioDisplayRenamer

@Suite("AudioDevice Grouping")
struct AudioDeviceGroupingTests {

    // MARK: - hardwareGroupKey (USB Audio devices)

    @Test("USB audio devices with same serial share group key")
    func usbSameSerialShareKey() {
        let speaker = makeDevice(
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:A1498802E:8,9",
            name: "Studio Display Speakers",
            hasOutput: true
        )
        let mic = makeDevice(
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display Microphone:A1498802E:6,7",
            name: "Studio Display Microphone",
            hasInput: true
        )

        #expect(speaker.hardwareGroupKey == mic.hardwareGroupKey)
    }

    @Test("USB audio devices with different serials get different keys")
    func usbDifferentSerials() {
        let display1 = makeDevice(
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:AAA111:8,9",
            name: "Studio Display Speakers",
            hasOutput: true
        )
        let display2 = makeDevice(
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:BBB222:8,9",
            name: "Studio Display Speakers",
            hasOutput: true
        )

        #expect(display1.hardwareGroupKey != display2.hardwareGroupKey)
    }

    @Test("USB group key extracts vendor:manufacturer:serial")
    func usbGroupKeyFormat() {
        let device = makeDevice(
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:SERIAL123:8,9",
            name: "Studio Display Speakers",
            hasOutput: true
        )

        #expect(device.hardwareGroupKey == "AppleUSBAudioEngine:Apple Inc.:SERIAL123")
    }

    // MARK: - nameBasedGroupKey (built-in / virtual devices)

    @Test("Strips ' Speakers' suffix")
    func stripSpeakersSuffix() {
        let device = makeDevice(uid: "builtin:spk", name: "MacBook Pro Speakers", hasOutput: true)
        #expect(device.nameBasedGroupKey == "name:MacBook Pro")
    }

    @Test("Strips ' Speaker' suffix")
    func stripSpeakerSuffix() {
        let device = makeDevice(uid: "builtin:spk", name: "MAX Speaker", hasOutput: true)
        #expect(device.nameBasedGroupKey == "name:MAX")
    }

    @Test("Strips ' Microphone' suffix")
    func stripMicrophoneSuffix() {
        let device = makeDevice(uid: "builtin:mic", name: "MacBook Pro Microphone", hasInput: true)
        #expect(device.nameBasedGroupKey == "name:MacBook Pro")
    }

    @Test("Strips ' Mic' suffix")
    func stripMicSuffix() {
        let device = makeDevice(uid: "builtin:mic", name: "MAX Mic", hasInput: true)
        #expect(device.nameBasedGroupKey == "name:MAX")
    }

    @Test("Strips ' Audio' suffix")
    func stripAudioSuffix() {
        let device = makeDevice(uid: "virtual:teams", name: "Microsoft Teams Audio", hasInput: true)
        #expect(device.nameBasedGroupKey == "name:Microsoft Teams")
    }

    @Test("Preserves name with no known suffix")
    func noKnownSuffix() {
        let device = makeDevice(uid: "virtual:zoom", name: "ZoomAudioDevice", hasOutput: true)
        #expect(device.nameBasedGroupKey == "name:ZoomAudioDevice")
    }

    @Test("Built-in speaker and mic share group key")
    func builtInPairShareKey() {
        let speaker = makeDevice(uid: "builtin:spk", name: "MacBook Pro Speakers", hasOutput: true)
        let mic = makeDevice(uid: "builtin:mic", name: "MacBook Pro Microphone", hasInput: true)

        #expect(speaker.hardwareGroupKey == mic.hardwareGroupKey)
    }

    // MARK: - hardwareGroupKey fallback

    @Test("Short UID falls back to name-based key")
    func shortUIDFallback() {
        let device = makeDevice(uid: "simple-uid", name: "Some Speaker", hasOutput: true)
        #expect(device.hardwareGroupKey == "name:Some")
    }

    @Test("Three-part UID falls back to name-based key")
    func threePartUIDFallback() {
        let device = makeDevice(uid: "part1:part2:part3", name: "Test Speakers", hasOutput: true)
        #expect(device.hardwareGroupKey == "name:Test")
    }
}

@Suite("Device Sort Alignment")
struct DeviceSortAlignmentTests {

    @Test("Sorting by group key aligns paired output and input devices")
    func sortingAlignsPairs() {
        let devices = [
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display:BBB:8,9", name: "Second Display Speakers", hasOutput: true),
            makeDevice(uid: "builtin:spk", name: "MacBook Air Speakers", hasOutput: true),
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display:AAA:8,9", name: "Main Display Speakers", hasOutput: true),
            makeDevice(uid: "builtin:mic", name: "MacBook Air Microphone", hasInput: true),
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display Mic:AAA:6,7", name: "Main Display Microphone", hasInput: true),
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display Mic:BBB:6,7", name: "Second Display Microphone", hasInput: true),
        ]

        let outputs = devices.filter(\.hasOutput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }
        let inputs = devices.filter(\.hasInput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }

        #expect(outputs.count == inputs.count)

        for i in 0..<outputs.count {
            #expect(
                outputs[i].hardwareGroupKey == inputs[i].hardwareGroupKey,
                "Row \(i): output '\(outputs[i].name)' should pair with input '\(inputs[i].name)'"
            )
        }
    }

    @Test("Unpaired devices don't break sorting")
    func unpairedDevices() {
        let devices = [
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display:BBB:8,9", name: "Display Speakers", hasOutput: true),
            makeDevice(uid: "AppleUSBAudioEngine:Apple:Display Mic:BBB:6,7", name: "Display Microphone", hasInput: true),
            makeDevice(uid: "virtual:zoom-out", name: "ZoomAudioDevice", hasOutput: true),
            makeDevice(uid: "iphone:mic", name: "Josh's iPhone Microphone", hasInput: true),
        ]

        let outputs = devices.filter(\.hasOutput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }
        let inputs = devices.filter(\.hasInput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }

        #expect(outputs.count == 2)
        #expect(inputs.count == 2)

        // The paired device (Display) should share a group key at matching indices
        let displayOutput = outputs.first { $0.name == "Display Speakers" }!
        let displayInput = inputs.first { $0.name == "Display Microphone" }!
        #expect(displayOutput.hardwareGroupKey == displayInput.hardwareGroupKey)
    }
}

// MARK: - Helper

private func makeDevice(
    uid: String,
    name: String,
    hasInput: Bool = false,
    hasOutput: Bool = false
) -> AudioDevice {
    AudioDevice(
        id: 0,
        uid: uid,
        name: name,
        hasInput: hasInput,
        hasOutput: hasOutput,
        displayLabel: name
    )
}
