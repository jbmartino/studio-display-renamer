import CoreAudio
import Foundation

@Observable
final class AudioDeviceManager {
    var devices: [AudioDevice] = []
    var deviceGroups: [DeviceGroup] = []
    var defaultInputUID: String?
    var defaultOutputUID: String?

    private var listenerBlocks: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    init() {
        refresh()
        startListening()
    }

    deinit {
        stopListening()
    }

    // MARK: - Public

    func refresh() {
        devices = fetchAllDevices()
        assignDisplayLabels()
        buildGroups()
        defaultInputUID = getDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultInputDevice)
        defaultOutputUID = getDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func setDefaultInput(uid: String) {
        setDefaultDevice(uid: uid, selector: kAudioHardwarePropertyDefaultInputDevice)
        Preferences.preferredInputUID = uid
        defaultInputUID = uid
    }

    func setDefaultOutput(uid: String) {
        setDefaultDevice(uid: uid, selector: kAudioHardwarePropertyDefaultOutputDevice)
        Preferences.preferredOutputUID = uid
        defaultOutputUID = uid
    }

    /// Set both input and output for a device group (physical hardware)
    func setBoth(group: DeviceGroup) {
        if let output = group.output {
            setDefaultOutput(uid: output.uid)
        }
        if let input = group.input {
            setDefaultInput(uid: input.uid)
        }
    }

    // MARK: - CoreAudio Enumeration

    private func fetchAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { buildDevice(id: $0) }
    }

    private func buildDevice(id: AudioObjectID) -> AudioDevice? {
        guard let uid = getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID),
              let name = getStringProperty(id: id, selector: kAudioObjectPropertyName) else {
            return nil
        }

        // Filter out aggregate devices (virtual devices created by apps or the system)
        var transportType: UInt32 = 0
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transportType) == noErr,
           transportType == kAudioDeviceTransportTypeAggregate {
            return nil
        }

        let hasInput = streamCount(id: id, scope: kAudioObjectPropertyScopeInput) > 0
        let hasOutput = streamCount(id: id, scope: kAudioObjectPropertyScopeOutput) > 0

        guard hasInput || hasOutput else { return nil }

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            hasInput: hasInput,
            hasOutput: hasOutput,
            displayLabel: name
        )
    }

    func assignDisplayLabels() {
        let nameCounts = Dictionary(grouping: devices, by: \.name)
        for i in devices.indices {
            let device = devices[i]
            // Check for a group-level custom name first
            let groupKey = device.hardwareGroupKey
            if let groupName = Preferences.customName(for: groupKey) {
                let kind = device.hasOutput ? "Speaker" : "Mic"
                devices[i].displayLabel = "\(groupName) \(kind)"
            } else if let custom = Preferences.customName(for: device.uid) {
                devices[i].displayLabel = custom
            } else if let group = nameCounts[device.name], group.count > 1 {
                let suffix = String(device.uid.suffix(4))
                devices[i].displayLabel = "\(device.name) (\(suffix))"
            } else {
                devices[i].displayLabel = device.name
            }
        }
        buildGroups()
    }

    private func buildGroups() {
        let grouped = Dictionary(grouping: devices, by: \.hardwareGroupKey)
        deviceGroups = grouped.map { key, devices in
            let output = devices.first(where: \.hasOutput)
            let input = devices.first(where: \.hasInput)
            let serial = extractSerial(from: key)
            let baseName = extractPhysicalName(from: devices)
            return DeviceGroup(
                id: key,
                physicalName: baseName,
                serial: serial,
                output: output,
                input: input,
                customName: Preferences.customName(for: key)
            )
        }
        .filter { $0.output != nil || $0.input != nil }
        .sorted { ($0.serial) < ($1.serial) }
    }

    private func extractSerial(from groupKey: String) -> String {
        let parts = groupKey.split(separator: ":")
        return parts.count >= 3 ? String(parts[2]) : groupKey
    }

    private func extractPhysicalName(from devices: [AudioDevice]) -> String {
        // Use the output device name, stripping " Speakers" suffix, or input name stripping " Microphone"
        if let output = devices.first(where: \.hasOutput) {
            return output.name
                .replacingOccurrences(of: " Speakers", with: "")
                .replacingOccurrences(of: " Speaker", with: "")
        }
        if let input = devices.first(where: \.hasInput) {
            return input.name
                .replacingOccurrences(of: " Microphone", with: "")
                .replacingOccurrences(of: " Mic", with: "")
        }
        return "Unknown Device"
    }

    // MARK: - Default Device

    private func getDefaultDeviceUID(selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return getStringProperty(id: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private func setDefaultDevice(uid: String, selector: AudioObjectPropertySelector) {
        guard var deviceID = devices.first(where: { $0.uid == uid })?.id else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )
    }

    // MARK: - Listeners

    private func startListening() {
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
        ]

        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.handleChange()
                }
            }

            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            if status == noErr {
                listenerBlocks.append((selector, block))
            }
        }
    }

    private func stopListening() {
        for (selector, block) in listenerBlocks {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
        listenerBlocks.removeAll()
    }

    private func handleChange() {
        refresh()
        autoRestore()
    }

    private func autoRestore() {
        if let preferredInput = Preferences.preferredInputUID,
           preferredInput != defaultInputUID,
           devices.contains(where: { $0.uid == preferredInput && $0.hasInput }) {
            setDefaultDevice(uid: preferredInput, selector: kAudioHardwarePropertyDefaultInputDevice)
            defaultInputUID = preferredInput
        }
        if let preferredOutput = Preferences.preferredOutputUID,
           preferredOutput != defaultOutputUID,
           devices.contains(where: { $0.uid == preferredOutput && $0.hasOutput }) {
            setDefaultDevice(uid: preferredOutput, selector: kAudioHardwarePropertyDefaultOutputDevice)
            defaultOutputUID = preferredOutput
        }
    }

    // MARK: - Helpers

    private func getStringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }

    private func streamCount(id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return 0
        }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }
}
