import AVFoundation
import CoreAudio
import Accelerate

class InputLevelMonitor {
    private var engine: AVAudioEngine?
    private var currentRMS: Float = 0
    private var displayTimer: Timer?
    private var smoothedLevel: Float = 0
    var onLevel: ((Float) -> Void)?

    func start(deviceUID: String) {
        stop()
        currentRMS = 0
        smoothedLevel = 0

        let engine = AVAudioEngine()
        self.engine = engine

        // Set the input device on the underlying AudioUnit
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!

        // Set input device by AudioObjectID
        setInputByID(audioUnit: audioUnit, deviceUID: deviceUID)

        let format = inputNode.outputFormat(forBus: 0)

        // Audio tap: just compute RMS and store it (no main thread dispatch)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData, frameLength > 0 else { return }

            var rms: Float = 0
            let count = vDSP_Length(frameLength)
            vDSP_rmsqv(data, 1, &rms, count)
            self.currentRMS = rms
        }

        // Display timer: update UI at ~30fps from the main thread
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rms = self.currentRMS
            let level = min(rms * 10, 1.0)

            // Smooth: fast attack, slower decay
            let smoothing: Float = level > self.smoothedLevel ? 0.7 : 0.2
            self.smoothedLevel += smoothing * (level - self.smoothedLevel)

            self.onLevel?(self.smoothedLevel)
        }

        do {
            try engine.start()
        } catch {
            self.engine = nil
        }
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func setInputByID(audioUnit: AudioUnit, deviceUID: String) {
        // Find the AudioObjectID for this UID and set it directly
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        for id in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &size, &name) == noErr,
               let value = name?.takeRetainedValue() as String?,
               value == deviceUID {
                var deviceID = id
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    UInt32(MemoryLayout<AudioObjectID>.size)
                )
                return
            }
        }
    }
}
