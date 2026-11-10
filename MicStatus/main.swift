import AppKit
import CoreAudio
import OSLog
import ServiceManagement

private let system = AudioObjectID(kAudioObjectSystemObject)
private let log = Logger(subsystem: "local.codex.consoledeck.mic-status", category: "indicator")

private enum MicState: String {
    case muted = "Microphone muted"
    case unmuted = "Microphone unmuted"
    case unavailable = "Microphone mute state unavailable"

    var symbol: String {
        switch self {
        case .muted: return "mic.slash.fill"
        case .unmuted: return "mic"
        case .unavailable: return "questionmark.circle"
        }
    }
}

private final class Indicator: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var statusItem: NSStatusItem?
    private let status = NSMenuItem()
    private let login = NSMenuItem(title: "Start Mic Indicator at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var fallback: Timer?

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(status)
        menu.addItem(.separator())
        login.target = self
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit Mic Indicator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        if AudioObjectAddPropertyListenerBlock(system, &input, .main, listener) != noErr {
            startFallback()
        }
        refresh()

        if CommandLine.arguments.contains("--setup"), SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                log.error("Login registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.notice("Start at login status \(SMAppService.mainApp.status.rawValue)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Login setting failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func read(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value: UInt32 = 0
        var bytes = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &value) == noErr else { return nil }
        return value
    }

    private func refresh() {
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
        guard state != next, let button = statusItem?.button else { return }
        state = next
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let configuration = next == .muted
            ? size.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            : size
        let icon = NSImage(systemSymbolName: next.symbol, accessibilityDescription: next.rawValue)?
            .withSymbolConfiguration(configuration)
        icon?.isTemplate = next != .muted
        button.image = icon
        button.toolTip = next.rawValue
        button.setAccessibilityLabel(next.rawValue)
        status.title = next.rawValue
        log.notice("Menu bar shows \(next.rawValue, privacy: .public)")
    }
}

let app = NSApplication.shared
private let indicator = Indicator()
app.delegate = indicator
app.setActivationPolicy(.accessory)
withExtendedLifetime(indicator) { app.run() }
