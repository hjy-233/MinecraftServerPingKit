## MinecraftServerPingKit

MinecraftServerPingKit 是一个纯 Swift Package，用于查询 Minecraft Java 服务器状态：

- 支持解析服务器版本、在线玩家、MOTD、图标和模组信息
- 提供 MOTD 格式代码清理后的纯文本
- 不依赖 UI

## Usage

```swift
import MinecraftServerPingKit

let serverInfo = await MinecraftServerPing.ping(
    connectAddress: "play.example.com",
    connectPort: 25565,
    originalAddress: "play.example.com",
    originalPort: 25565,
)

let motd = serverInfo?.description.plainText
let onlinePlayers = serverInfo?.players?.online
```

如果已经取得完整的 Server List Ping 响应数据，也可以直接解析：

```swift
let serverInfo = MinecraftServerPing.parseStatusResponse(packetData)
```

## Architecture

- `MinecraftServerPing` — 建立 TCP 连接、发送握手和状态请求、接收服务器响应
- `MinecraftServerInfo` — 表示服务器版本、玩家、MOTD、图标和模组信息
- `Description.plainText` — 清理 Minecraft `§` 格式代码并展开嵌套 MOTD
- `parseStatusResponse` — 解析完整的状态响应数据包

## Build

```bash
swift build
swift test
```

### License

MIT License. 具体条款请见仓库中的 [LICENSE](./LICENSE) 文件。
