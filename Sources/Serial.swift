import Darwin
import Foundation
import IOKit
import IOKit.serial

final class DeckSerial {
    private let queue = DispatchQueue(label: "local.codex.consoledeck.serial")
    private var timer: DispatchSourceTimer?
    private var reader: DispatchSourceRead?
    private var fd: Int32 = -1
    private var buffer = Data()
    private var ready = false
    private var attempts = 0
    private var currentPort = ""
    private var preferredPort = UserDefaults.standard.string(forKey: "deckSerialPort")
    private let status: (String, Bool) -> Void
    private let receive: (String) -> Void

    init(status: @escaping (String, Bool) -> Void, receive: @escaping (String) -> Void) {
        self.status = status
        self.receive = receive
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    private func poll() {
        if fd >= 0 {
            if !FileManager.default.fileExists(atPath: currentPort) {
                disconnect()
            } else if !ready {
                attempts += 1
                if attempts >= 6 {
                    disconnect()
                    status("ConsoleDeck firmware did not respond", false)
                } else {
                    let ping: [UInt8] = [63]
                    _ = Darwin.write(fd, ping, ping.count)
                }
            }
            return
        }

        let ports = Self.nanoPorts()
        let port = ports.count == 1 ? ports.first : ports.first { $0 == preferredPort }
        guard let port else {
            status(ports.isEmpty ? "Connect the ConsoleDeck by USB" : "More than one matching USB serial device", false)
            return
        }

        let device = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard device >= 0 else {
            status(errno == EBUSY ? "Serial port is already in use" : "Could not open the serial port", false)
            return
        }
        var settings = termios()
        guard ioctl(device, TIOCEXCL) == 0, tcgetattr(device, &settings) == 0 else {
            Darwin.close(device)
            status("Could not reserve the serial port", false)
            return
        }
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        cfsetspeed(&settings, speed_t(B115200))
        guard tcsetattr(device, TCSANOW, &settings) == 0 else {
            Darwin.close(device)
            status("Could not set the serial speed", false)
            return
        }

        fd = device
        currentPort = port
        status("Connecting to the deck…", false)
        let source = DispatchSource.makeReadSource(fileDescriptor: device, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable(device) }
        reader = source
        source.resume()
    }

    private func readAvailable(_ device: Int32) {
        guard device == fd else { return }
        var bytes = [UInt8](repeating: 0, count: 512)
        while true {
            let count = Darwin.read(device, &bytes, bytes.count)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                disconnect()
                status("ConsoleDeck disconnected", false)
                return
            }
            buffer.append(contentsOf: bytes.prefix(count))
            while let end = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<end], as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
                buffer.removeSubrange(...end)
                if line == "READY CONSOLEDECK_V1" {
                    if !ready {
                        ready = true
                        preferredPort = currentPort
                        UserDefaults.standard.set(currentPort, forKey: "deckSerialPort")
                        status("ConsoleDeck connected", true)
                    }
                } else if ready && !line.isEmpty {
                    receive(line)
                }
            }
            if buffer.count > 256 { buffer.removeAll() }
        }
    }

    private func disconnect() {
        reader?.cancel()
        reader = nil
        Darwin.close(fd)
        fd = -1
        ready = false
        attempts = 0
        buffer.removeAll()
    }

    static func nanoPorts() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var ports: [String] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let options = IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            let vendor = IORegistryEntrySearchCFProperty(
                entry, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault, options
            ) as? NSNumber
            let product = IORegistryEntrySearchCFProperty(
                entry, kIOServicePlane, "idProduct" as CFString, kCFAllocatorDefault, options
            ) as? NSNumber
            guard vendor?.intValue == 0x1a86, product?.intValue == 0x7523,
                  let port = IORegistryEntryCreateCFProperty(
                    entry, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? String else { continue }
            ports.append(port)
        }
        return ports
    }
}
