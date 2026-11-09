# hiddifyctl — 命令行 + MCP 控制 Hiddify 网络

## 背景与决策（已调研确认）

Hiddify app 自身不暴露外部控制接口；所有连接/切换动作最终通过本机 gRPC 走到 Go 内核
`hiddify-core`，监听 `127.0.0.1:17078`（明文、无鉴权）。`Core` 服务原生支持
`Start/Stop/Restart/HotReload/SelectOutbound/UrlTest/ChangeHiddifySettings/Parse/CoreInfoListener`
等，覆盖 connect/disconnect/status。

- **app 模式**：桌面 Hiddify app 运行时 17078 已开；`connect` 需传 active profile 的
  config 路径 `<workingDir>/configs/<id>.json`。
  - macOS workingDir = `~/Library/Application Support/app.hiddify.com/`（bundle id `app.hiddify.com`）
  - drift DB = `db.sqlite`，表 `profile_entries`（列 `id`/`active`/`name`），active=1 即激活。
- **headless 模式**：独立起 `hiddify-core` 进程（`Setup` + `RunStandalone`），`configPath` 为
  本地 sing-box 配置或订阅 URL，同样监听 17078。

### 关键取舍：轻量 gRPC 客户端，不 import hiddify-core 全量
- `hiddifyctl` 只做 17078 的 gRPC **客户端**。从 `hiddify-core` 的 `.proto` 用 protoc 生成
  `hcore.CoreClient` + 消息类型，依赖仅 `google.golang.org/grpc` + `google.golang.org/protobuf`
  + well-known types。**不编入 sing-box 巨依赖树**，可单二进制分发。
- headless 启动**不内嵌 core**，而是调用已有的 `HiddifyCli` 二进制（repo 内 `hiddify-core/bin`
  或用户 `--core-bin` 指定，或 Docker），`hiddifyctl` 只负责「启动→等 17078→连接」。

## 目录结构（新建）

```
tools/hiddifyctl/
  go.mod                      # module github.com/hiddify/hiddify-app/tools/hiddifyctl
  main.go                    # cobra 根命令，分发子命令
  internal/
    grpc/                    # protoc 生成的 hcore client (gen)
      hcore.pb.go
      hcore_grpc.pb.go
      hcommon.pb.go          # 仅需要的消息(Empty/Response/...)
    client/
      client.go              # 连接 17078，封装 Start/Stop/Status/GetSystemInfo
      status.go              # 解析 CoreState + SystemInfo -> 结构化状态
    locate/
      locate.go              # 按平台探测 app workingDir / db.sqlite / active config
      db.go                  # 用 modernc.org/sqlite 读 profile_entries active=1
    headless/
      headless.go            # 找不到 17078 时启动 HiddifyCli run（后台），等端口就绪
  cmd/
    connect.go  disconnect.go  status.go  toggle.go  run.go  mcp.go  locate.go
  mcp/
    server.go                # stdio MCP server（mark3labs/mcp-go），暴露 tools
  scripts/
    gen_proto.sh             # protoc 生成 grpc client 的脚本
  README.md
```

## gRPC client 生成

`scripts/gen_proto.sh`：用 protoc 从 `hiddify-core/v2/hcore/*.proto` 生成（只需 proto 文件，
不需编译 Go 代码）。`--proto_path=../../hiddify-core`（解析 `v2/...` import）。
生成到 `internal/grpc/`。仅需要 `hcore_service.proto` + `hcore.proto` + `hcommon/common.proto`。
proto 依赖 `google/protobuf/timestamp.proto` → 用 protoc 的 well-known include。

依赖：仅 `google.golang.org/grpc`、`google.golang.org/protobuf`。

## CLI 子命令

| 命令 | 说明 |
|------|------|
| `hiddifyctl connect [--config <path\|url>]` | 连 17078 → 若 app 模式自动定位 active config；headless 下用 --config 或自动起 core |
| `hiddifyctl disconnect` | Stop |
| `hiddifyctl status [--json]` | CoreInfoListener + GetSystemInfo → 状态/当前 profile/节点/流量 |
| `hiddifyctl toggle` | 按当前状态 connect/disconnect |
| `hiddifyctl run --config <url\|path>` | headless：调 HiddifyCli run 起独立 core（阻塞） |
| `hiddifyctl mcp` | 启动 stdio MCP server |
| `hiddifyctl locate` | 调试：打印探测到的 app 目录 / db / active config 路径 |

通用 flags：`--addr`（默认 `127.0.0.1:17078`）、`--app-dir`、`--db-path`、
`--core-bin`、`--headless`（强制 headless）、`--timeout`。

## MCP tools（stdio）

- `hiddify_connect` — 参数 `config?`（可选 path/url），连接。
- `hiddify_disconnect` — 断开。
- `hiddify_status` — 返回 JSON 结构化状态（state、current_profile、current_outbound、uplink/downlink）。
- `hiddify_toggle` — 切换。

MCP server 用 `mark3labs/mcp-go`，`stdio` 传输，工具结果返回人类可读文本 + 结构化 JSON。

## 核心模块实现要点

1. **client**：`dial(addr)` 用 `grpc.NewClient`（或 `grpc.Dial` insecure）连 17078；
   封装 `Start(StartRequest{config_path})` / `Stop` / `CoreInfoListener`（stream）/ `GetSystemInfo`。
   返回错误时区分「17078 不可达」（触发 headless fallback）与「core 拒绝」（配置错误等）。
2. **locate**：按 `runtime.GOOS` 构造 app 目录；macOS `~/Library/Application Support/app.hiddify.com`、
   Linux `~/.local/share/app.hiddify.com`（含 flatpak 变体探测）、Windows `%APPDATA%\app.hiddify.com`。
   `db.go` 用 `modernc.org/sqlite` 读 `profile_entries where active=1`，返回 `{id,name}` 并拼 config 路径。
   **若读不到 active config，回退到 `--config` 或列出 configs 目录报错**。
3. **headless**：`connect` 时若 17078 超时/不可达：
   - 若 `--core-bin` 或 repo `hiddify-core/bin/HiddifyCli` 存在 → `exec` 后台 `run --config <cfg>`，
     轮询 17078 直至就绪（或超时），再继续 connect。
   - 否则报错并提示用 `hiddifyctl run` / Docker 先起 core。
4. **status**：`CoreInfoListener` 取 `CoreStates`（STOPPED/STARTING/STARTED/STOPPING/HOT_RELOADING），
   叠加 `GetSystemInfo` 的 `current_profile`/`current_outbound`/流量。

## 安全说明

17078 为明文、无鉴权回环端口——本机任意进程都可完整控制 VPN。MCP server 仅本地 stdio、
供本用户 agent 使用，风险与「本机运行 Hiddify」同级。README 明示此点，并建议不要在不可信
多用户主机暴露；headless 启动的 core 同理。

## 构建与使用

- 生成：`bash tools/hiddifyctl/scripts/gen_proto.sh`（需 protoc + protoc-gen-go + protoc-gen-go-grpc）
- 构建：`cd tools/hiddifyctl && go build -o hiddifyctl .`
- MCP 接入（如 Claude Code `claude_desktop_config.json` / OpenCode mcp 配置）：
  ```json
  { "mcpServers": { "hiddify": { "command": "/abs/path/hiddifyctl", "args": ["mcp"] } } }
  ```
- CLI 示例：`hiddifyctl status`、`hiddifyctl connect`、`hiddifyctl disconnect`。

## 验证

1. 桌面 Hiddify 已运行 → `hiddifyctl status` 显示 STARTED + 当前 profile/节点/流量。
2. `hiddifyctl disconnect` 后 app 托盘/界面变断开；`hiddifyctl connect` 重新连上 active profile。
3. `hiddifyctl mcp` 被本地 agent 拉起后能调用 `hiddify_status`/`hiddify_connect`/`hiddify_disconnect`。
4. headless：`hiddifyctl run --config <订阅url>` 起独立 core，`status` 显示 STARTED。
5. `cd tools/hiddifyctl && go vet ./... && go build ./...` 通过（无 sing-box 编译）。

## 后续可扩展（不在首批）

切换节点 `SelectOutbound`、切换 profile（读 app 多 profile + HotReload）、服务模式、
测速 `UrlTest`、导入订阅 `Parse`。这些均可复用同一 gRPC client 平滑添加。
