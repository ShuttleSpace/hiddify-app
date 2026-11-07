# hiddifyctl

命令行（CLI）与 MCP server，用于控制本机 Hiddify 网络连接：连接 / 断开 / 查询状态。
底层统一通过 hiddify-core 的本地 gRPC 控制面（`127.0.0.1:17078`，明文无鉴权）工作。

## 工作原理

Hiddify 桌面 app 的所有连接 / 切换动作，最终都经过本机 gRPC 走到 Go 内核 `hiddify-core`。
`hiddifyctl` 是一个**纯 gRPC 客户端**，连上 `17078` 后调用 `Core` 服务的 `Start` / `Stop` /
`CoreInfoListener` / `GetSystemInfo` 等。两种目标都支持：

- **控制已运行的桌面 app（默认）**：app 在跑时 `17078` 已开，直接驱动它。
- **Headless 独立内核**：`17078` 不可达时，可用 `hiddifyctl run -c <订阅URL或配置>` 启动一个
  独立的 `HiddifyCli` 进程（不依赖 GUI app），或直接对接已运行的独立 core。

> 安全：本机 `17078` 是明文、无鉴权的回环端口——本机任意进程都能完整控制 VPN。
> `hiddifyctl` 仅本地使用（MCP 走 stdio），风险与「本机运行 Hiddify」同级。
> 不要在不可信的多用户主机上暴露它。

## 构建

```bash
cd tools/hiddifyctl
go build -o hiddifyctl .
# 可选：生成/刷新 gRPC 客户端（见 scripts/sync_proto.sh 说明）
```

生成的 gRPC 客户端（`internal/grpc/`）是从 `hiddify-core` 的 `.proto` **快照**而来，
依赖只有 `grpc` + `protobuf`，**不编入 sing-box 等重依赖**，可单二进制分发。

## CLI 用法

| 命令 | 说明 |
|------|------|
| `hiddifyctl status [--json]` | 连接状态、当前 profile / 节点、上下行流量 |
| `hiddifyctl connect [--config <path\|url>]` | 连接。默认用 app 数据库中 `active=1` 的 profile；也可显式指定 config |
| `hiddifyctl disconnect` | 断开 |
| `hiddifyctl toggle` | 按当前状态切换 |
| `hiddifyctl run -c <url\|path>` | Headless：启动独立 hiddify-core（阻塞运行） |
| `hiddifyctl locate` | 调试：打印探测到的 app 目录 / 数据库 / 当前 active profile |

全局参数：

```
--addr 127.0.0.1:17078   gRPC 地址
--app-dir <dir>           覆盖 app 工作目录（含 configs/）
--db-path <file>          覆盖 drift 数据库 db.sqlite 路径
--core-bin <path>         headless 模式下 HiddifyCli 二进制路径
--headless               17078 不可达时自动启动独立内核
--config <path|url>       显式配置（connect / run 用）
--timeout 5s             gRPC 拨号超时
```

### 示例

```bash
hiddifyctl status
hiddifyctl connect                       # 连当前 active profile
hiddifyctl connect --config /path/x.json # 连指定配置
hiddifyctl disconnect
hiddifyctl run -c "https://sub.example.com/xxxxx" --tun   # headless，开 TUN
```

## MCP 能力由 Hiddify app 内嵌提供

> `hiddifyctl` 现在是**纯命令行工具**。MCP server 已内嵌进 Hiddify 桌面 app：app 启动后即在
> `127.0.0.1:<port>/mcp` 暴露 Streamable HTTP 的 MCP 服务，agent 直接接入即可，无需本 CLI 中转。

app 内 MCP 工具：`hiddify_connect` / `hiddify_disconnect` / `hiddify_toggle` / `hiddify_status` /
`hiddify_list_profiles` / `hiddify_select_profile` / `hiddify_list_nodes` / `hiddify_select_node` /
`hiddify_service_mode` / `hiddify_url_test`，直接复用 app 内部逻辑（含 profile / 节点切换）。

启用方式：在 app「设置 → MCP 控制服务」中开启，复制生成的接入配置（含 Bearer Token）到你的 MCP 客户端
（Claude Code / OpenCode 等）即可。

## 已知限制 / 后续可扩展

- `connect`（app 模式）默认连接 app 数据库里标记为 `active` 的 profile；要连其它 profile 请传
  `--config <configs/<id>.json>`。列出 profile / 按名选择 / 切换节点 /
  服务模式 / 测速 等能力可复用同一 gRPC 客户端平滑添加（见 `internal/grpc`）。
- headless 模式启动依赖外部 `HiddifyCli` 二进制（仓库 `hiddify-core/bin` 或 `PATH` 中），
  可通过 `--core-bin` 指定；也可自行 `docker` 运行 hiddify-core 后让本工具直连其 `17078`。
