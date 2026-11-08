# Release Notes — v5.1.0

## What's new

### MCP control server (in-app)
- The desktop app now exposes an in-process **MCP server** over Streamable HTTP,
  so an agent can drive the running app without any external process.
- Bound to `127.0.0.1` only, protected by a **Bearer token** (auto-generated on
  first enable). Enable it from **Settings → MCP 控制服务**.
- Exposed tools: `hiddify_connect` / `hiddify_disconnect` / `hiddify_toggle` /
  `hiddify_status` / `hiddify_list_profiles` / `hiddify_select_profile` /
  `hiddify_list_nodes` / `hiddify_select_node` / `hiddify_service_mode` /
  `hiddify_url_test`.

### `hiddifyctl` CLI
- Added a standalone Go CLI (`tools/hiddifyctl`) to connect / disconnect / query
  status / toggle / locate the active profile, talking to the local core control
  plane on `127.0.0.1:17078`.
- Build it with `just hiddifyctl`, cross-compile or install to `$GOPATH/bin`
  with `just hiddifyctl-cross` / `just hiddifyctl-install`.

## Notes
- The MCP server is **off by default**. Turn it on in settings and restart the app.
- The Bearer token lives in app preferences; regenerate it from the settings page
  whenever you need to revoke access.
