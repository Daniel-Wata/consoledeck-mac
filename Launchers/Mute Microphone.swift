import AppKit
import CoreAudio
import Foundation
import OSLog

enum MicError: LocalizedError {
    case noDefaultInput
    case unavailableMute
    case coreAudio(OSStatus)
    case muteDidNotChange

    var errorDescription: String? {
        switch self {
        case .noDefaultInput: return "Choose an input device in System Settings → Sound."
        case .unavailableMute: return "The current input device does not expose a system mute control."
        case let .coreAudio(status): return "Core Audio returned error \(status)."
        case .muteDidNotChange: return "The input device did not confirm the mute change."
        }
    }
}

func readUInt32(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) throws -> UInt32 {
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    guard status == noErr else { throw MicError.coreAudio(status) }
    return value
}

func microphoneMute(statusOnly: Bool) throws -> Bool {
    var defaultInput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let device = try readUInt32(AudioObjectID(kAudioObjectSystemObject), &defaultInput)
    guard device != kAudioObjectUnknown else { throw MicError.noDefaultInput }

    var mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var settable = DarwinBoolean(false)
    guard AudioObjectHasProperty(device, &mute),
          AudioObjectIsPropertySettable(device, &mute, &settable) == noErr,
          settable.boolValue else { throw MicError.unavailableMute }
    let current = try readUInt32(device, &mute)
    if statusOnly { return current != 0 }

    var desired: UInt32 = current == 0 ? 1 : 0
    let status = AudioObjectSetPropertyData(
        device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &desired
    )
    guard status == noErr else { throw MicError.coreAudio(status) }
    for _ in 0..<20 {
        if try readUInt32(device, &mute) == desired { return desired != 0 }
        Thread.sleep(forTimeInterval: 0.015)
    }
    throw MicError.muteDidNotChange
}

let statusOnly = CommandLine.arguments.contains("--status")
let logger = Logger(subsystem: "local.codex.consoledeck.microphone", category: "mute")
do {
    let muted = try microphoneMute(statusOnly: statusOnly)
    let state = muted ? "Microphone muted" : "Microphone unmuted"
    if statusOnly {
        print(state)
    } else {
        logger.notice("\(state, privacy: .public)")
    }
} catch {
    logger.error("\(error.localizedDescription, privacy: .public)")
    if statusOnly {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Microphone could not be toggled"
    alert.informativeText = error.localizedDescription
    alert.runModal()
}
