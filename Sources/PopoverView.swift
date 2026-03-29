import SwiftUI
import AppKit
import CoreAudio
import AVFoundation

struct PopoverView: View {
    var manager: AudioDeviceManager
    @State private var editedNames: [String: String] = [:]
    @State private var testingOutput: String?
    @State private var testingInput: String?
    @State private var inputLevel: Float = 0
    @State private var inputMonitor = InputLevelMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Audio Devices")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Reset Names") {
                    for key in editedNames.keys {
                        editedNames[key] = ""
                        Preferences.setCustomName(nil, for: key)
                    }
                    manager.assignDisplayLabels()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Use Both section
            let pairedGroups = manager.deviceGroups.filter { $0.input != nil && $0.output != nil }
            if !pairedGroups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Use Both (Input + Output)", systemImage: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(pairedGroups) { group in
                            let isActive = group.output?.uid == manager.defaultOutputUID
                                && group.input?.uid == manager.defaultInputUID

                            Button {
                                manager.setBoth(group: group)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isActive ? .accentColor : .secondary)
                                        .font(.system(size: 12))
                                    Text(group.displayLabel)
                                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            // Two-column layout: Output left, Input right
            HStack(alignment: .top, spacing: 0) {
                // Output column
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Output", systemImage: "speaker.wave.2")
                            .font(.system(size: 13, weight: .semibold))

                        let outputDevices = manager.devices.filter(\.hasOutput)
                        if outputDevices.isEmpty {
                            Text("No output devices")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(outputDevices) { device in
                                OutputDeviceCard(
                                    device: device,
                                    isDefault: device.uid == manager.defaultOutputUID,
                                    isPreferred: device.uid == Preferences.preferredOutputUID,
                                    isTesting: testingOutput == device.uid,
                                    editedName: nameBinding(for: device),
                                    onSelect: { manager.setDefaultOutput(uid: device.uid) },
                                    onTest: { testOutput(uid: device.uid) },
                                    onSave: { saveName(for: device) }
                                )
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Input column
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Input", systemImage: "mic")
                            .font(.system(size: 13, weight: .semibold))

                        let inputDevices = manager.devices.filter(\.hasInput)
                        if inputDevices.isEmpty {
                            Text("No input devices")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(inputDevices) { device in
                                InputDeviceCard(
                                    device: device,
                                    isDefault: device.uid == manager.defaultInputUID,
                                    isPreferred: device.uid == Preferences.preferredInputUID,
                                    isTesting: testingInput == device.uid,
                                    inputLevel: testingInput == device.uid ? inputLevel : 0,
                                    editedName: nameBinding(for: device),
                                    onSelect: { manager.setDefaultInput(uid: device.uid) },
                                    onTest: { testInput(uid: device.uid) },
                                    onSave: { saveName(for: device) }
                                )
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Footer
            HStack {
                Text("Click a device to set as default")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 720, height: 520)
        .onAppear { loadNames() }
        .onDisappear { stopInputTest() }
    }

    // MARK: - Name Editing

    private func nameKey(for device: AudioDevice) -> String {
        if let group = manager.deviceGroups.first(where: { $0.id == device.hardwareGroupKey }),
           group.input != nil && group.output != nil {
            return group.id
        }
        return device.uid
    }

    private func nameBinding(for device: AudioDevice) -> Binding<String> {
        let key = nameKey(for: device)
        return Binding(
            get: { editedNames[key] ?? "" },
            set: { editedNames[key] = $0 }
        )
    }

    private func loadNames() {
        var names: [String: String] = [:]
        for group in manager.deviceGroups {
            if group.input != nil && group.output != nil {
                names[group.id] = group.customName ?? ""
            } else {
                let uid = (group.output ?? group.input)!.uid
                names[uid] = Preferences.customName(for: uid) ?? ""
            }
        }
        editedNames = names
    }

    private func saveName(for device: AudioDevice) {
        let key = nameKey(for: device)
        let name = editedNames[key] ?? ""
        Preferences.setCustomName(name.isEmpty ? nil : name, for: key)
        manager.assignDisplayLabels()
        // Remove focus from text field so selection highlight clears
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: - Output Test

    @State private var testEngine: AVAudioEngine?

    private func testOutput(uid: String) {
        if testingOutput == uid {
            testEngine?.stop()
            testEngine = nil
            testingOutput = nil
            return
        }

        testEngine?.stop()
        testingOutput = uid
        guard let deviceID = manager.devices.first(where: { $0.uid == uid })?.id else { return }

        let engine = AVAudioEngine()
        self.testEngine = engine

        // Route output to the target device directly (no system default switching)
        let outputUnit = engine.outputNode.audioUnit!
        var devID = deviceID
        AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &devID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )

        // Generate a gentle two-tone chime
        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        let duration = 0.8
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]

        // Two harmonious tones (C5 + E5) with a soft fade-in/out envelope
        let freq1: Double = 523.25  // C5
        let freq2: Double = 659.25  // E5
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // Envelope: quick attack, gentle decay
            let envelope = Float(min(t / 0.02, 1.0) * exp(-t * 3.0))
            let sample = Float(sin(2.0 * .pi * freq1 * t) + 0.6 * sin(2.0 * .pi * freq2 * t))
            data[i] = sample * envelope * 0.3
        }

        do {
            try engine.start()
            playerNode.play()
            playerNode.scheduleBuffer(buffer) { [weak testEngine] in
                DispatchQueue.main.async {
                    testEngine?.stop()
                    self.testEngine = nil
                    self.testingOutput = nil
                }
            }
        } catch {
            testEngine = nil
            testingOutput = nil
        }
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

// MARK: - Output Device Card

private struct OutputDeviceCard: View {
    let device: AudioDevice
    let isDefault: Bool
    let isPreferred: Bool
    let isTesting: Bool
    let editedName: Binding<String>
    let onSelect: () -> Void
    let onTest: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Device name + default indicator (clickable)
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isDefault ? .accentColor : .secondary)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.displayLabel)
                            .font(.system(size: 12, weight: isDefault ? .semibold : .regular))
                            .lineLimit(1)
                        Text(device.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isPreferred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
            .buttonStyle(.plain)

            // Rename + save + test row
            HStack(spacing: 6) {
                TextField("Custom name", text: editedName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { onSave() }

                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button(action: onTest) {
                    Image(systemName: isTesting ? "stop.fill" : "play.fill")
                        .frame(width: 14)
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isTesting ? .red : .accentColor)
                .help(isTesting ? "Stop" : "Play test sound")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(isDefault ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDefault ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Input Device Card

private struct InputDeviceCard: View {
    let device: AudioDevice
    let isDefault: Bool
    let isPreferred: Bool
    let isTesting: Bool
    let inputLevel: Float
    let editedName: Binding<String>
    let onSelect: () -> Void
    let onTest: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Device name + default indicator (clickable)
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isDefault ? .accentColor : .secondary)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.displayLabel)
                            .font(.system(size: 12, weight: isDefault ? .semibold : .regular))
                            .lineLimit(1)
                        Text(device.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isPreferred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
            .buttonStyle(.plain)

            // Rename + save + test row
            HStack(spacing: 6) {
                TextField("Custom name", text: editedName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { onSave() }

                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button(action: onTest) {
                    Image(systemName: isTesting ? "stop.fill" : "mic.fill")
                        .frame(width: 14)
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isTesting ? .red : .accentColor)
                .help(isTesting ? "Stop" : "Test microphone")
            }

            // Level meter
            if isTesting {
                HStack(spacing: 4) {
                    Text("Level")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(inputLevel))
                        }
                    }
                    .frame(height: 6)
                }
                .animation(.linear(duration: 0.05), value: inputLevel)
                .transition(.opacity)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(isDefault ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDefault ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
