import SwiftUI
import AVFoundation
import CoreAudio

struct SettingsView: View {
    var manager: AudioDeviceManager
    @State private var editedNames: [String: String] = [:]
    @State private var testingOutput: String?
    @State private var testingInput: String?
    @State private var inputLevel: Float = 0
    @State private var inputMonitor = InputLevelMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Device Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 4)

            Text("Rename your devices to tell them apart.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let outputDevices = manager.devices.filter(\.hasOutput)
                    let inputDevices = manager.devices.filter(\.hasInput)

                    if !outputDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Output Devices", systemImage: "speaker.wave.2")
                                .font(.headline)

                            ForEach(outputDevices) { device in
                                DeviceRow(
                                    device: device,
                                    editedName: deviceBinding(for: device),
                                    isTesting: testingOutput == device.uid,
                                    level: 0,
                                    isInput: false,
                                    onTest: { testOutput(uid: device.uid) }
                                )
                            }
                        }
                    }

                    if !inputDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Input Devices", systemImage: "mic")
                                .font(.headline)

                            ForEach(inputDevices) { device in
                                DeviceRow(
                                    device: device,
                                    editedName: deviceBinding(for: device),
                                    isTesting: testingInput == device.uid,
                                    level: testingInput == device.uid ? inputLevel : 0,
                                    isInput: true,
                                    onTest: { testInput(uid: device.uid) }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.vertical, 8)

            HStack {
                Button("Reset All Names") {
                    editedNames = editedNames.mapValues { _ in "" }
                }

                Spacer()

                Button("Cancel") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveNames()
                    manager.assignDisplayLabels()
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .onAppear {
            loadNames()
        }
        .onDisappear {
            stopInputTest()
        }
    }

    // For grouped devices, editing one name applies to the whole group.
    // We key by group ID for grouped devices, by UID for ungrouped ones.
    private func nameKey(for device: AudioDevice) -> String {
        if let group = manager.deviceGroups.first(where: { $0.id == device.hardwareGroupKey }),
           group.input != nil && group.output != nil {
            return group.id // shared group key
        }
        return device.uid
    }

    private func deviceBinding(for device: AudioDevice) -> Binding<String> {
        let key = nameKey(for: device)
        return Binding(
            get: { editedNames[key] ?? "" },
            set: { editedNames[key] = $0 }
        )
    }

    private func loadNames() {
        var names: [String: String] = [:]
        // Load group-level names
        for group in manager.deviceGroups {
            if group.input != nil && group.output != nil {
                names[group.id] = group.customName ?? ""
            } else {
                // Standalone device — use device UID
                let uid = (group.output ?? group.input)!.uid
                names[uid] = Preferences.customName(for: uid) ?? ""
            }
        }
        editedNames = names
    }

    private func saveNames() {
        for (key, name) in editedNames {
            Preferences.setCustomName(name.isEmpty ? nil : name, for: key)
        }
    }

    // MARK: - Output Test

    private func testOutput(uid: String) {
        if testingOutput == uid {
            testingOutput = nil
            return
        }

        testingOutput = uid
        guard let deviceID = manager.devices.first(where: { $0.uid == uid })?.id else { return }

        let previousDefault = manager.defaultOutputUID

        setSystemOutput(deviceID: deviceID)
        let sound = NSSound(named: "Ping")
        sound?.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            testingOutput = nil
            if let prev = previousDefault,
               let prevID = manager.devices.first(where: { $0.uid == prev })?.id {
                setSystemOutput(deviceID: prevID)
            }
        }
    }

    private func setSystemOutput(deviceID: AudioObjectID) {
        var id = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &id
        )
    }

    // MARK: - Input Test

    private func testInput(uid: String) {
        if testingInput == uid {
            stopInputTest()
            return
        }

        stopInputTest()
        testingInput = uid
        inputLevel = 0

        inputMonitor.onLevel = { level in
            inputLevel = level
        }
        inputMonitor.start(deviceUID: uid)
    }

    private func stopInputTest() {
        inputMonitor.stop()
        testingInput = nil
        inputLevel = 0
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device: AudioDevice
    @Binding var editedName: String
    let isTesting: Bool
    let level: Float
    let isInput: Bool
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                    Text(device.uid)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 180, alignment: .leading)

                TextField("Custom name", text: $editedName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    onTest()
                } label: {
                    Image(systemName: isTesting ? "stop.fill" : (isInput ? "mic.fill" : "play.fill"))
                        .frame(width: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isTesting ? .red : .accentColor)
                .help(isTesting ? "Stop test" : (isInput ? "Test microphone" : "Play test sound"))
            }

            if isTesting && isInput {
                HStack(spacing: 4) {
                    Text("Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(level))
                        }
                    }
                    .frame(height: 8)
                }
                .animation(.linear(duration: 0.05), value: level)
                .transition(.opacity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}
