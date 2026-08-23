//
//  MinecraftServerPing.swift
//  MinecraftServerPingKit
//
//  © 2025-2026 hjy-233. All rights reserved.
//

@preconcurrency import Dispatch
import Foundation
@preconcurrency import Network

/// Represents information returned by the Minecraft Server List Ping protocol.
public struct MinecraftServerInfo: Codable, Sendable {
    /// The server version information.
    public struct Version: Codable, Sendable {
        public let name: String
        public let `protocol`: Int?

        public init(name: String, protocol: Int?) {
            self.name = name
            self.protocol = `protocol`
        }
    }

    /// The player information reported by the server.
    public struct Players: Codable, Sendable {
        public let max: Int
        public let online: Int
        public let sample: [Player]?

        public init(max: Int, online: Int, sample: [Player]?) {
            self.max = max
            self.online = online
            self.sample = sample
        }

        public struct Player: Codable, Sendable {
            public let name: String
            public let id: String?

            public init(name: String, id: String?) {
                self.name = name
                self.id = id
            }
        }
    }

    /// The server description (MOTD).
    public struct Description: Codable, Sendable {
        public let text: String?
        public let extra: [DescriptionElement]?

        public init(text: String?, extra: [DescriptionElement]?) {
            self.text = text
            self.extra = extra
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self.init(text: text, extra: nil)
                return
            }

            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                text: keyedContainer.decodeIfPresent(String.self, forKey: .text),
                extra: keyedContainer.decodeIfPresent([DescriptionElement].self, forKey: .extra),
            )
        }

        private enum CodingKeys: String, CodingKey {
            case text, extra
        }

        /// A description element represented by plain text or a nested object.
        public enum DescriptionElement: Codable, Sendable {
            case string(String)
            case object(Description)

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .string(string)
                } else {
                    self = try .object(container.decode(Description.self))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case let .string(string):
                    try container.encode(string)
                case let .object(description):
                    try container.encode(description)
                }
            }

            /// Returns this element as plain text with formatting codes removed.
            public var plainText: String {
                switch self {
                case let .string(value):
                    Description.stripFormatCodes(value)
                case let .object(description):
                    description.plainText
                }
            }
        }

        /// Returns the description text with Minecraft formatting codes removed.
        public var plainText: String {
            var result = text.map(Self.stripFormatCodes) ?? ""
            result += extra?.map(\.plainText).joined() ?? ""
            return result
        }

        private static func stripFormatCodes(_ text: String) -> String {
            var result = text
            while let range = result.range(of: "§") {
                let startIndex = range.lowerBound
                let endIndex = result.index(startIndex, offsetBy: 2, limitedBy: result.endIndex) ?? result.endIndex
                result.removeSubrange(startIndex ..< endIndex)
            }
            return result
        }
    }

    public let version: Version?
    public let players: Players?
    public let description: Description
    /// Base64-encoded server icon data, when supplied by the server.
    public let favicon: String?
    /// Mod information, when supplied by the server.
    public let modinfo: ModInfo?

    public init(
        version: Version?,
        players: Players?,
        description: Description,
        favicon: String?,
        modinfo: ModInfo?,
    ) {
        self.version = version
        self.players = players
        self.description = description
        self.favicon = favicon
        self.modinfo = modinfo
    }

    public struct ModInfo: Codable, Sendable {
        public let type: String
        public let modList: [Mod]?

        public init(type: String, modList: [Mod]?) {
            self.type = type
            self.modList = modList
        }

        public struct Mod: Codable, Sendable {
            public let modid: String
            public let version: String

            public init(modid: String, version: String) {
                self.modid = modid
                self.version = version
            }
        }
    }
}

/// Implements the Minecraft Server List Ping protocol over TCP.
public enum MinecraftServerPing {
    /// Pings a Minecraft server and returns its status, or `nil` on failure.
    ///
    /// - Parameters:
    ///   - connectAddress: The address to which the TCP connection is made.
    ///   - connectPort: The port to which the TCP connection is made.
    ///   - originalAddress: The address written into the Minecraft handshake.
    ///   - originalPort: The port written into the Minecraft handshake.
    ///   - timeout: The timeout in seconds.
    public static func ping(
        connectAddress: String,
        connectPort: Int,
        originalAddress: String,
        originalPort: Int,
        timeout: TimeInterval = 5.0,
    ) async -> MinecraftServerInfo? {
        guard (1 ... Int(UInt16.max)).contains(connectPort), (1 ... Int(UInt16.max)).contains(originalPort) else {
            return nil
        }

        let host = NWEndpoint.Host(connectAddress)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(connectPort)) else { return nil }
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        return await withCheckedContinuation { (continuation: CheckedContinuation<MinecraftServerInfo?, Never>) in
            let state = PingState()
            let timeoutTask = DispatchWorkItem { [weak state] in
                guard let state else { return }
                if state.setResumedAndTimedOut() {
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            state.setTimeoutTask(timeoutTask)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutTask)

            @Sendable
            func receiveData() {
                guard !state.hasResumed else { return }

                connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, _, isComplete, error in
                    guard !state.hasResumed else { return }

                    if error != nil {
                        finish(nil, state: state, timeoutTask: timeoutTask, connection: connection, continuation: continuation)
                        return
                    }

                    if let data, !data.isEmpty {
                        state.receivedData.append(data)
                        if let serverInfo = parseStatusResponse(state.receivedData) {
                            finish(serverInfo, state: state, timeoutTask: timeoutTask, connection: connection, continuation: continuation)
                        } else if isComplete {
                            finish(nil, state: state, timeoutTask: timeoutTask, connection: connection, continuation: continuation)
                        } else {
                            receiveData()
                        }
                    } else if isComplete {
                        finish(nil, state: state, timeoutTask: timeoutTask, connection: connection, continuation: continuation)
                    }
                }
            }

            connection.stateUpdateHandler = { stateUpdate in
                guard !state.hasResumed else { return }

                switch stateUpdate {
                case .ready:
                    sendHandshakeAndStatusRequest(connection: connection, address: originalAddress, port: originalPort)
                case .failed, .cancelled:
                    finish(nil, state: state, timeoutTask: timeoutTask, connection: connection, continuation: continuation)
                default:
                    break
                }
            }

            receiveData()
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    /// Parses a complete status response packet. This is useful for callers that already manage the connection.
    public static func parseStatusResponse(_ data: Data) -> MinecraftServerInfo? {
        var offset = 0
        guard let (packetLength, lengthBytes) = decodeVarInt(data: data, offset: &offset), packetLength >= 0 else {
            return nil
        }
        let totalLength = lengthBytes + Int(packetLength)
        guard data.count >= totalLength,
              let (packetId, _) = decodeVarInt(data: data, offset: &offset),
              packetId == 0,
              let (jsonString, _) = decodeString(data: data, offset: &offset),
              let jsonData = jsonString.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(MinecraftServerInfo.self, from: jsonData)
    }

    private static func sendHandshakeAndStatusRequest(connection: NWConnection, address: String, port: Int) {
        var handshakeData = Data()
        handshakeData.append(encodeVarInt(0))
        handshakeData.append(encodeVarInt(-1))
        handshakeData.append(encodeString(address))
        handshakeData.append(contentsOf: withUnsafeBytes(of: UInt16(port).bigEndian, Array.init))
        handshakeData.append(encodeVarInt(1))

        var handshakePacket = encodeVarInt(Int32(handshakeData.count))
        handshakePacket.append(handshakeData)
        connection.send(content: handshakePacket, completion: .contentProcessed { error in
            guard error == nil else { return }

            let statusData = encodeVarInt(0)
            var statusPacket = encodeVarInt(Int32(statusData.count))
            statusPacket.append(statusData)
            connection.send(content: statusPacket, completion: .contentProcessed { _ in })
        })
    }

    private static func finish(
        _ result: MinecraftServerInfo?,
        state: PingState,
        timeoutTask: DispatchWorkItem,
        connection: NWConnection,
        continuation: CheckedContinuation<MinecraftServerInfo?, Never>,
    ) {
        guard state.setResumed() else { return }
        timeoutTask.cancel()
        connection.cancel()
        continuation.resume(returning: result)
    }

    private static func encodeVarInt(_ value: Int32) -> Data {
        var result = Data()
        var value = UInt32(bitPattern: value)
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            result.append(byte)
        } while value != 0
        return result
    }

    private static func encodeString(_ value: String) -> Data {
        guard let data = value.data(using: .utf8) else { return encodeVarInt(0) }
        var result = encodeVarInt(Int32(data.count))
        result.append(data)
        return result
    }

    private static func decodeVarInt(data: Data, offset: inout Int) -> (Int32, Int)? {
        var result: UInt32 = 0
        var shift = 0
        var bytesRead = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            bytesRead += 1
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return (Int32(bitPattern: result), bytesRead)
            }
            shift += 7
            if shift >= 32 {
                return nil
            }
        }
        return nil
    }

    private static func decodeString(data: Data, offset: inout Int) -> (String, Int)? {
        guard let (length, lengthBytes) = decodeVarInt(data: data, offset: &offset), length >= 0 else { return nil }
        let stringLength = Int(length)
        guard data.count - offset >= stringLength else { return nil }
        let end = offset + stringLength
        guard let string = String(data: data[offset ..< end], encoding: .utf8) else { return nil }
        offset = end
        return (string, lengthBytes)
    }
}

private final class PingState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var timeoutTask: DispatchWorkItem?
    var receivedData = Data()

    var hasResumed: Bool {
        lock.withLock { resumed }
    }

    func setResumed() -> Bool {
        lock.withLock {
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    func setResumedAndTimedOut() -> Bool {
        lock.withLock {
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    func setTimeoutTask(_ task: DispatchWorkItem) {
        lock.withLock { timeoutTask = task }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
