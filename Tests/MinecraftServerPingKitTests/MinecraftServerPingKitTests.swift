import Foundation
@testable import MinecraftServerPingKit
import Testing

struct MinecraftServerPingKitTests {
    @Test
    func descriptionFlattensFormattingAndNestedElements() {
        let description = MinecraftServerInfo.Description(
            text: "§aVanilla ",
            extra: [
                .string("§bServer"),
                .object(.init(text: " §cOnline", extra: nil)),
            ],
        )

        #expect(description.plainText == "Vanilla Server Online")
    }

    @Test
    func decodesStringDescription() throws {
        let data = Data(#""§aWelcome""#.utf8)
        let description = try JSONDecoder().decode(MinecraftServerInfo.Description.self, from: data)

        #expect(description.plainText == "Welcome")
    }

    @Test
    func parsesStatusResponse() throws {
        let json = #"{"version":{"name":"1.21.8","protocol":772},"players":{"max":20,"online":3,"sample":[{"name":"Alex","id":"player-id"}]},"description":{"text":"§aWelcome"},"favicon":"data:image/png;base64,AA=="}"#
        let jsonData = try #require(json.data(using: .utf8))
        var payload = Data([0])
        payload.append(Self.encodeString(jsonData))

        var packet = Self.encodeVarInt(Int32(payload.count))
        packet.append(payload)

        let info = try #require(MinecraftServerPing.parseStatusResponse(packet))
        #expect(info.version?.name == "1.21.8")
        #expect(info.players?.online == 3)
        #expect(info.description.plainText == "Welcome")
        #expect(info.favicon != nil)
    }

    @Test
    func rejectsMalformedStatusResponse() {
        #expect(MinecraftServerPing.parseStatusResponse(Data([0x80])) == nil)
        #expect(MinecraftServerPing.parseStatusResponse(Data([0x01, 0x01])) == nil)
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

    private static func encodeString(_ data: Data) -> Data {
        var result = encodeVarInt(Int32(data.count))
        result.append(data)
        return result
    }
}
