import AppKit
import CoreGraphics
import IOKit.hidsystem

enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case none = "No Action"
    case openItem = "Open App, File or Folder"
    case openURL = "Open Website"
    case shortcut = "Keyboard Shortcut"
    case playPause = "Play / Pause"
    case mute = "Mute / Unmute"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "minus"
        case .openItem: return "folder"
        case .openURL: return "globe"
        case .shortcut: return "command"
        case .playPause: return "playpause"
        case .mute: return "speaker.slash"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        }
    }

    var mediaKey: Int? {
        switch self {
        case .playPause: return Int(NX_KEYTYPE_PLAY)
        case .mute: return Int(NX_KEYTYPE_MUTE)
        case .volumeUp: return Int(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: return Int(NX_KEYTYPE_SOUND_DOWN)
        default: return nil
        }
    }
}

struct RecordedShortcut: Codable, Equatable {
    let keyCode: UInt16
    let flags: UInt
    let label: String

    init(event: NSEvent) {
        keyCode = event.keyCode
        let modifiers: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")
        ]
        let held = modifiers.filter { event.modifierFlags.contains($0.0) }
        flags = held.reduce(0) { $0 | $1.0.rawValue }
        let specialKeys: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        let key = specialKeys[keyCode] ?? event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .controlCharacters).uppercased()
        label = held.map { $0.1 }.joined() + ((key?.isEmpty == false ? key : nil) ?? "Key \(keyCode)")
    }
}

struct DeckAction: Codable, Equatable {
    var kind: ActionKind = .none
    var target: String = ""
    var shortcut: RecordedShortcut?

    var title: String {
        switch kind {
        case .openItem:
            let name = URL(fileURLWithPath: target).lastPathComponent
            return name.isEmpty ? kind.rawValue : name
        case .openURL: return website?.host ?? kind.rawValue
        case .shortcut: return shortcut?.label ?? kind.rawValue
        default: return kind.rawValue
        }
    }

    var website: URL? {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    var isValid: Bool {
        switch kind {
        case .openItem: return !target.isEmpty && target.hasPrefix("/")
        case .openURL: return website != nil
        case .shortcut: return shortcut != nil
        default: return true
        }
    }

    func run() -> String {
        if let mediaKey = kind.mediaKey {
            guard CGPreflightPostEventAccess() else { return "Accessibility permission needed" }
            for state in [0x0a, 0x0b] {
                let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                    timestamp: 0, windowNumber: 0, context: nil,
                    subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                    data1: (mediaKey << 16) | (state << 8), data2: -1
                )
                guard let cgEvent = event?.cgEvent else { return "Could not create a media event" }
                cgEvent.post(tap: .cghidEventTap)
            }
            return "Media key sent"
        }

        switch kind {
        case .none:
            return "Unassigned"
        case .openItem:
            return NSWorkspace.shared.open(URL(fileURLWithPath: target)) ? "Item opened" : "Could not open the item"
        case .openURL:
            guard let website else { return "Invalid website" }
            return NSWorkspace.shared.open(website) ? "Website opened" : "Could not open the website"
        case .shortcut:
            guard let shortcut else { return "No shortcut recorded" }
            guard CGPreflightPostEventAccess() else { return "Accessibility permission needed" }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: down) else {
                    return "Could not create a keyboard event"
                }
                event.flags = CGEventFlags(rawValue: UInt64(shortcut.flags))
                event.post(tap: .cghidEventTap)
            }
            return "Keyboard shortcut sent"
        default:
            return "Action unavailable"
        }
    }
}
