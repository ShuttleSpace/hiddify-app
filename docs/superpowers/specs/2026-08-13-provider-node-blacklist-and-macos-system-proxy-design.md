# Provider Node Blacklist and macOS System Proxy Reliability

## Summary

This change delivers two related improvements to connection reliability:

1. Each subscription provider can maintain an independent blacklist of exact node names. Blacklisted nodes are excluded from manual selection, lowest-delay selection, and load balancing.
2. macOS system-proxy mode becomes state-aware. Hiddify verifies that macOS actually enabled its proxy, bypasses loopback services such as CC Switch, and reports a concrete failure instead of remaining in a connecting state.

The work is split into independently testable blacklist and system-proxy components. They meet in the connection pipeline, where configuration must be valid and the requested operating-system state must be verified before Hiddify reports a successful connection.

## Goals

- Store node blacklists independently for each profile/provider.
- Let users search the current node list by partial name and select one or many exact nodes to block.
- Preserve blocked names across subscription refreshes and application restarts.
- Support versioned JSON import and export, including cross-profile migration.
- Guarantee that blacklisted nodes cannot be selected manually or by automatic outbound groups.
- Prevent a blacklist from silently producing an empty selector.
- Make macOS system-proxy mode reflect actual operating-system state.
- Bypass local services so CC Switch on `127.0.0.1:15721` does not loop back through Hiddify.
- Surface proxy setup errors and leave the app disconnected instead of indefinitely connecting.
- Remove only Hiddify-owned proxy state when disconnecting.

## Non-goals

- Pattern-based blacklist rules that automatically match future nodes.
- Blocking nodes by IP address, country metadata, protocol, or provider-defined identifier.
- Sharing one blacklist globally across all providers.
- Rewriting or permanently deleting nodes from downloaded subscription content.
- Managing CC Switch configuration or changing its provider/model settings.
- Changing macOS DNS settings as part of system-proxy mode.

## Current State and Evidence

Profiles already have stable IDs and persisted user overrides. Runtime outbound groups are assembled in `hiddify-core/v2/config/builder.go`, where all parsed outbounds are collected into the selector, lowest-delay balancer, and general balancer.

On macOS, a mixed inbound with `set-system-proxy` delegates to sing-box's Darwin system-proxy implementation. During diagnosis, the Hiddify mixed proxy was listening on port `12334`, and an explicit request through it succeeded:

```text
explicit_hiddify_http=204 error=
```

At the same time, macOS reported all relevant proxy mechanisms disabled:

```text
HTTPEnable: 0
HTTPSEnable: 0
SOCKSEnable: 0
ProxyAutoConfigEnable: 0
```

This isolates the observed browser and ChatGPT App failures from node connectivity: the local Hiddify proxy works, but system traffic is not routed to it. The application currently has no post-start verification that macOS accepted the requested proxy state.

## Architecture

### Provider node blacklist

The persisted blacklist belongs to a profile and contains exact node names. Search terms are transient UI state and are never stored as rules.

The feature is divided into four units:

1. **Persistence** stores and retrieves the set of blocked names for a profile ID.
2. **Node inventory** parses the current profile and exposes selectable node names without mutating subscription content.
3. **Blacklist policy** normalizes names, filters node collections, validates that at least one usable node remains, and handles import merging or replacement.
4. **Blacklist management UI** provides search, selection, stale-entry display, import, and export from the profile details flow.

Filtering is enforced in the core configuration builder before outbound tags are assigned to any user-selectable or automatic group. The Flutter UI may filter its display for clarity, but core filtering remains the security boundary for the behavior.

### macOS system-proxy state

System-proxy operations are represented by a small platform service with these responsibilities:

- Resolve the active macOS network service from the default network interface.
- Capture relevant pre-existing proxy state before applying Hiddify settings.
- Enable HTTP, HTTPS, and SOCKS proxy entries for Hiddify's loopback mixed port.
- Configure loopback and local-host bypass values.
- Read back the effective configuration and compare it with the desired state.
- Reapply and verify settings when the default interface changes.
- Restore or remove only state still owned by the running Hiddify session.

The service returns structured status and error information to the core connection lifecycle. Flutter does not independently run a second proxy-setting implementation; it consumes the verified result from the core.

## Data Model

### Storage

Add a profile-owned blacklist value. The preferred representation is a dedicated table keyed by profile ID and normalized node name, rather than embedding an unbounded list in `UserOverride`.

Conceptually:

```text
ProfileNodeBlacklistEntry
  profileId: String
  nodeName: String
  createdAt: DateTime
  primary key: (profileId, nodeName)
```

The table is cascade-cleaned by repository logic when a profile is deleted. A database migration creates the table without modifying existing profile data.

Names are compared after trimming surrounding whitespace. Comparison otherwise remains exact and case-sensitive because node tags may legitimately differ only by case. The original trimmed spelling is retained for display and export.

### Import/export format

The JSON document is versioned and self-describing:

```json
{
  "version": 1,
  "sourceProfile": {
    "name": "Example Provider"
  },
  "blockedNodeNames": [
    "Hong Kong 01",
    "US Premium 03"
  ]
}
```

`sourceProfile` is informational. Import into another profile is allowed after showing the source and destination names.

Import modes:

- **Merge**, the default: union imported and existing names, then deduplicate.
- **Replace**: replace the destination profile's current set with imported names.

Unknown document versions, malformed JSON, non-string entries, or an empty required field produce a validation error without partially updating storage. Duplicate names are accepted and collapsed.

## Blacklist User Experience

The profile details page gains a **Node blacklist** entry showing the number of blocked nodes. Opening it displays:

- A search field that performs case-insensitive substring filtering over the current node names.
- Checkboxes for multi-selection and ordinary row selection for a single node.
- Select-all and clear-selection actions scoped to the current search result.
- A distinction between current nodes and stored names no longer present in the subscription.
- Import and export actions.
- A save action with remaining-node validation.

Selecting a search result stores that node's exact normalized name, not the search text. Future nodes with merely similar names are not blocked.

Stale entries remain visible in a separate section and can be removed. Retaining them ensures that a temporarily removed node stays blocked if the provider later restores the same name.

The UI prevents saving when all current usable nodes would be blacklisted and explains that at least one node must remain. The same invariant is enforced below the UI because subscription content can change after the blacklist was saved.

## Runtime Filtering and Connection Flow

The connection pipeline becomes:

1. Load the active profile and its subscription content.
2. Load the exact-name blacklist for that profile ID.
3. Parse candidate outbound nodes and endpoints.
4. Remove candidates whose normalized tag is blacklisted.
5. Reject the configuration if no usable candidate remains.
6. Build the manual selector, lowest-delay group, and balance group from the same filtered tag list.
7. Start the local mixed proxy.
8. For macOS system-proxy mode, apply and verify operating-system proxy state.
9. Report connected only after both the core and requested system integration are ready.

Blacklisted outbound definitions may be omitted from the final runtime configuration to ensure no internal selection path can reach them. Hidden, direct, DNS, WARP, and Hiddify-generated control outbounds are not treated as provider nodes and are unaffected.

Saving blacklist changes while the profile is connected triggers a configuration rebuild and reconnect. If the active node was newly blocked, it cannot survive in the rebuilt selector and another remaining node is chosen by existing default-selection behavior.

## macOS System Proxy Behavior

### Apply

When system-proxy mode starts, Hiddify resolves the active hardware port/network service corresponding to the default interface and applies all three proxy types to `127.0.0.1:<mixedPort>`:

- Web proxy (HTTP)
- Secure web proxy (HTTPS)
- SOCKS proxy

The bypass list includes at minimum:

- `localhost`
- `127.0.0.1`
- `::1`
- `*.local`

This keeps requests to CC Switch at `127.0.0.1:15721` local. CC Switch's own upstream HTTP requests still use the system proxy normally unless CC Switch explicitly overrides it.

### Verify

After applying settings, Hiddify reads the active service state and requires:

- HTTP, HTTPS, and SOCKS are enabled.
- Each enabled proxy points at the expected loopback host and mixed port.
- Required bypass entries are present.

Verification has a short bounded timeout and returns a structured error naming the failed operation, network service, and expected versus observed state. It must not log credentials, subscription URLs, authorization headers, or CC Switch request bodies.

### Interface changes

When the default interface changes, Hiddify resolves the new network service, reapplies the desired settings, and verifies them. Failure changes the connection to an error/disconnected state instead of leaving a false connected state.

### Cleanup and ownership

Before applying, Hiddify records the relevant proxy state for the active service for the lifetime of that connection session. On disconnect or mode change, it restores that state only if the current values still match the values Hiddify installed. If another tool changed the proxy meanwhile, Hiddify leaves the new values untouched and reports a non-fatal ownership conflict in logs.

Cleanup also runs after a partial apply or failed verification. A best-effort cleanup error is attached to the primary failure but does not hide it.

## Error Handling

Blacklist failures use specific user-facing cases:

- Profile content cannot be parsed into a node inventory.
- Blacklist would leave no usable provider node.
- Import file is malformed or uses an unsupported version.
- Imported replacement would leave no usable current node.
- Persistence or export fails.

System-proxy failures identify:

- Default interface or macOS network service cannot be resolved.
- `networksetup` or the underlying platform API lacks permission.
- A proxy setting command fails.
- Read-back verification does not match the desired state.
- Interface-change reapplication fails.
- Cleanup cannot safely restore owned state.

Any apply or verification failure terminates the connection attempt and returns the app to a stable disconnected/error state. The UI never represents the requested preference as proof that the system proxy is active.

## Testing Strategy

### Blacklist tests

- Exact, case-sensitive matching after whitespace trimming.
- Substring search is case-insensitive but does not become a stored rule.
- Single selection, multi-selection, select-all-visible, and clear-visible behavior.
- Selector, lowest-delay, and balance groups receive the same filtered node set.
- Subscription refresh preserves same-name blocks and does not block merely similar new names.
- Stale blacklist entries remain manageable.
- Blocking the last usable node fails in both UI policy and core configuration building.
- Import merge and replace are atomic, deduplicated, and version-validated.
- Export round-trips all stored names.
- Connected-profile edits trigger rebuild/reconnect.

### macOS proxy tests

Use an injectable command/state adapter in unit tests rather than changing the developer machine:

- Successful HTTP/HTTPS/SOCKS apply and read-back verification.
- Required bypass entries are installed.
- Permission failure produces a bounded, visible connection error.
- Missing network service and verification mismatch fail deterministically.
- Default-interface change reapplies to the new service.
- Disconnect restores captured state when Hiddify still owns it.
- Disconnect does not overwrite proxy settings changed by another tool.
- Partial apply is cleaned up.
- Loopback CC Switch traffic is bypassed while ordinary upstream traffic remains proxied.

A macOS integration diagnostic verifies the real state without exposing secrets:

```text
networksetup -getwebproxy <service>
networksetup -getsecurewebproxy <service>
networksetup -getsocksfirewallproxy <service>
scutil --proxy
curl -x http://127.0.0.1:<mixedPort> https://www.google.com/generate_204
```

## Acceptance Criteria

- Blacklist data is isolated by profile ID and survives restart and subscription refresh.
- A fuzzy search selects exact current nodes; it never creates a future matching rule.
- Blacklisted nodes are absent from manual selection, lowest-delay candidates, and balance candidates.
- The app never starts a selector with zero usable provider nodes.
- Import defaults to merge/deduplicate, supports explicit replacement, and can migrate between profiles.
- With macOS system-proxy mode connected, effective HTTP, HTTPS, and SOCKS state points to Hiddify's mixed port.
- Safari or Chrome can reach Google, YouTube, and `https://chatgpt.com` through that mode.
- ChatGPT App can pass its startup screen when the selected node supports its services.
- Codex CLI and ChatGPT App can reach CC Switch on `127.0.0.1:15721` without a local proxy loop.
- A failed system-proxy apply or verification produces a concrete error and does not remain indefinitely connecting.
- Disconnect leaves no Hiddify-owned system proxy behind and does not overwrite another tool's newer proxy configuration.

## Delivery Boundaries

Implementation should be staged so each subsystem can be reviewed and reverted independently:

1. Blacklist persistence, policy, core filtering, and tests.
2. Blacklist management UI and import/export.
3. macOS proxy adapter, verification, ownership-safe cleanup, and tests.
4. Connection lifecycle integration and end-to-end verification with and without CC Switch.

