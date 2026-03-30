#!/usr/bin/env swift

// Standalone test runner — works without Xcode/XCTest.
// Usage: swift Tests/run_tests.swift
// Or:    chmod +x Tests/run_tests.swift && ./Tests/run_tests.swift

import Foundation

// MARK: - Minimal test harness

var passed = 0
var failed = 0
var currentSuite = ""

func suite(_ name: String) {
    currentSuite = name
    print("\n\u{001B}[1m\(name)\u{001B}[0m")
}

func test(_ name: String, _ body: () -> Bool) {
    if body() {
        passed += 1
        print("  \u{001B}[32m✓\u{001B}[0m \(name)")
    } else {
        failed += 1
        print("  \u{001B}[31m✗\u{001B}[0m \(name)")
    }
}

// MARK: - AudioDevice (copied minimal struct for standalone compilation)

struct AudioDevice {
    let id: UInt32
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    var displayLabel: String

    var hardwareGroupKey: String {
        let parts = uid.split(separator: ":")
        if parts.count >= 4 {
            return "\(parts[0]):\(parts[1]):\(parts[3])"
        }
        return nameBasedGroupKey
    }

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

func makeDevice(uid: String, name: String, hasInput: Bool = false, hasOutput: Bool = false) -> AudioDevice {
    AudioDevice(id: 0, uid: uid, name: name, hasInput: hasInput, hasOutput: hasOutput, displayLabel: name)
}

// MARK: - Tests

suite("AudioDevice Grouping — USB Audio")

test("USB devices with same serial share group key") {
    let speaker = makeDevice(uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:A1498802E:8,9", name: "Studio Display Speakers", hasOutput: true)
    let mic = makeDevice(uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display Microphone:A1498802E:6,7", name: "Studio Display Microphone", hasInput: true)
    return speaker.hardwareGroupKey == mic.hardwareGroupKey
}

test("USB devices with different serials get different keys") {
    let d1 = makeDevice(uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:AAA111:8,9", name: "Studio Display Speakers", hasOutput: true)
    let d2 = makeDevice(uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:BBB222:8,9", name: "Studio Display Speakers", hasOutput: true)
    return d1.hardwareGroupKey != d2.hardwareGroupKey
}

test("USB group key extracts vendor:manufacturer:serial") {
    let device = makeDevice(uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:SERIAL123:8,9", name: "Studio Display Speakers", hasOutput: true)
    return device.hardwareGroupKey == "AppleUSBAudioEngine:Apple Inc.:SERIAL123"
}

suite("AudioDevice Grouping — Name-based")

test("Strips ' Speakers' suffix") {
    let d = makeDevice(uid: "builtin:spk", name: "MacBook Pro Speakers", hasOutput: true)
    return d.nameBasedGroupKey == "name:MacBook Pro"
}

test("Strips ' Speaker' suffix") {
    let d = makeDevice(uid: "builtin:spk", name: "MAX Speaker", hasOutput: true)
    return d.nameBasedGroupKey == "name:MAX"
}

test("Strips ' Microphone' suffix") {
    let d = makeDevice(uid: "builtin:mic", name: "MacBook Pro Microphone", hasInput: true)
    return d.nameBasedGroupKey == "name:MacBook Pro"
}

test("Strips ' Mic' suffix") {
    let d = makeDevice(uid: "builtin:mic", name: "MAX Mic", hasInput: true)
    return d.nameBasedGroupKey == "name:MAX"
}

test("Strips ' Audio' suffix") {
    let d = makeDevice(uid: "virtual:teams", name: "Microsoft Teams Audio", hasInput: true)
    return d.nameBasedGroupKey == "name:Microsoft Teams"
}

test("Preserves name with no known suffix") {
    let d = makeDevice(uid: "virtual:zoom", name: "ZoomAudioDevice", hasOutput: true)
    return d.nameBasedGroupKey == "name:ZoomAudioDevice"
}

suite("AudioDevice Grouping — Fallback")

test("Built-in speaker and mic share group key") {
    let speaker = makeDevice(uid: "builtin:spk", name: "MacBook Pro Speakers", hasOutput: true)
    let mic = makeDevice(uid: "builtin:mic", name: "MacBook Pro Microphone", hasInput: true)
    return speaker.hardwareGroupKey == mic.hardwareGroupKey
}

test("Short UID falls back to name-based key") {
    let d = makeDevice(uid: "simple-uid", name: "Some Speaker", hasOutput: true)
    return d.hardwareGroupKey == "name:Some"
}

test("Three-part UID falls back to name-based key") {
    let d = makeDevice(uid: "part1:part2:part3", name: "Test Speakers", hasOutput: true)
    return d.hardwareGroupKey == "name:Test"
}

suite("Device Sort Alignment")

test("Sorting by group key aligns paired output and input devices") {
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

    guard outputs.count == inputs.count else { return false }

    for i in 0..<outputs.count {
        if outputs[i].hardwareGroupKey != inputs[i].hardwareGroupKey { return false }
    }
    return true
}

test("Unpaired devices don't break sorting") {
    let devices = [
        makeDevice(uid: "AppleUSBAudioEngine:Apple:Display:BBB:8,9", name: "Display Speakers", hasOutput: true),
        makeDevice(uid: "AppleUSBAudioEngine:Apple:Display Mic:BBB:6,7", name: "Display Microphone", hasInput: true),
        makeDevice(uid: "virtual:zoom-out", name: "ZoomAudioDevice", hasOutput: true),
        makeDevice(uid: "iphone:mic", name: "Josh's iPhone Microphone", hasInput: true),
    ]

    let outputs = devices.filter(\.hasOutput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }
    let inputs = devices.filter(\.hasInput).sorted { $0.hardwareGroupKey < $1.hardwareGroupKey }

    guard outputs.count == 2, inputs.count == 2 else { return false }

    let displayOutput = outputs.first { $0.name == "Display Speakers" }!
    let displayInput = inputs.first { $0.name == "Display Microphone" }!
    return displayOutput.hardwareGroupKey == displayInput.hardwareGroupKey
}

// MARK: - Results

print("\n\u{001B}[1m—————————————————————————\u{001B}[0m")
print("\u{001B}[1mResults: \(passed) passed, \(failed) failed\u{001B}[0m")
if failed > 0 {
    print("\u{001B}[31mFAILED\u{001B}[0m")
    exit(1)
} else {
    print("\u{001B}[32mALL TESTS PASSED\u{001B}[0m")
}
