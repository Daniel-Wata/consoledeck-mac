import CoreAudio
import Foundation

private let system = AudioObjectID(kAudioObjectSystemObject)

enum MicState: String {
    case muted = "Microphone muted"
    case unmuted = "Microphone unmuted"
    case unavailable = "Microphone mute state unavailable"

    var symbol: String {
        switch self {
        case .muted: return "mic.slash.fill"
        case .unmuted, .unavailable: return "square.grid.3x3"
        }
    }
}

final class MicrophoneStatus {
    private var input = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var observedDevice: AudioDeviceID?
    private var state: MicState?
    private var fallback: Timer?
    private let didChange: (MicState) -> Void

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }

    init(didChange: @escaping (MicState) -> Void) {
        self.didChange = didChange
    }

    func start() {
        if AudioObjectAddPropertyListenerBlock(system, &input, .main, listener) != noErr {
            startFallback()
        }
        refresh()
    }

    func stop() {
        AudioObjectRemovePropertyListenerBlock(system, &input, .main, listener)
        if let observedDevice {
            AudioObjectRemovePropertyListenerBlock(observedDevice, &mute, .main, listener)
        }
        fallback?.invalidate()
    }

    private func read(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value: UInt32 = 0
        var bytes = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value) == noErr else { return nil }
        return value
    }

    func refresh() {
        let device = read(system, &input) ?? kAudioObjectUnknown
        if device != observedDevice {
            if let observedDevice {
                AudioObjectRemovePropertyListenerBlock(observedDevice, &mute, .main, listener)
            }
            observedDevice = nil
            if device != kAudioObjectUnknown && AudioObjectHasProperty(device, &mute) {
                if AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener) == noErr {
                    observedDevice = device
                } else {
                    startFallback()
                }
            }
        }
        guard device != kAudioObjectUnknown, let value = read(device, &mute) else {
            show(.unavailable)
            return
        }
        show(value == 0 ? .unmuted : .muted)
    }

    private func startFallback() {
        guard fallback == nil else { return }
        fallback = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func show(_ next: MicState) {
        guard state != next else { return }
        state = next
        didChange(next)
    }
}
