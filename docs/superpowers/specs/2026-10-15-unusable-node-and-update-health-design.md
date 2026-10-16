# Unusable Node and Subscription Update Health

## Summary

Two gaps, both about the app staying silent while something is broken.

1. In macOS system-proxy mode, a reconnect whose nodes all time out leaves the OS proxy pointed at a mixed port that accepts connections but cannot route them. Every proxied app hangs while the UI shows "connecting".
2. A scheduled remote-profile update that fails only raises a toast. If the window is hidden the toast is invisible, and nothing in the tray says subscriptions are stale.

Nothing here is implemented. This document records the agreed design.

## Goals

- Stop pointing the macOS system proxy at a listener that has no working node.
- Say so, once, when it happens.
- Raise a visible, persistent warning when a scheduled subscription update fails.

## Non-Goals

- Automatically re-enabling the system proxy when a node recovers. Reconnecting is the way back.
- Changing the tray icon artwork.
- Warning about anything other than unusable nodes and failed subscription updates.
- Retrying a failed update on a different schedule.

## Current State

### Unusable nodes are indistinguishable from a pending url test

`connection_button.dart` and `system_tray_notifier.dart` both treat `delay <= 0 || delay >= 65000` as "not connected yet". Those are two different conditions:

- `delay >= 65000` — the core recorded a url test that never completed. No node answered.
- `delay == 0` — `hiddify-core/v2/hcore/proxy_info.go:61-63` zeroes `UrlTestDelay` when `url_test_history.IsFromCache`. This is a healthy result: history loaded from cache, or the first test has not finished yet.

Acting on `delay == 0` would release the proxy on working connections. `proxy_tile.dart:82` already draws the real distinction, showing `×` only above the threshold.

### A failed connect never gets a chance to fail

`releaseSystemProxy()` on `ConnectionRepository` exists as of the mode-switch work, so the RPC path is in place. What is missing is any decision about when to call it. Today the proxy is applied at `Listener.Start` and released only when the box closes, so a box that started but cannot route holds the OS setting indefinitely.

### Update failures have no durable signal

`ForegroundProfilesUpdateNotifier.state` holds a single `ProfileUpdateStatus?`, overwritten per profile inside the update loop. With three subscriptions where the first fails and the next two succeed, the final state reports success. There is nothing for a tray indicator to read.

`DialogNotifier._show` returns null when `rootNavKey.currentContext == null`, which is the normal state for a tray-only app. A dialog raised during a background update is therefore dropped.

### The macOS tray icon cannot carry a badge glyph

`SystemTrayNotifier` calls `setIcon(..., isTemplate: true)` on macOS, so the system recolours the image to match the menu bar. A coloured warning glyph cannot survive that. The existing text channel is the dock badge, which `_trayTooltip` already uses for `{urlTestDelay}ms`.

## Architecture

### Unusable-node release

A pure predicate, so the threshold lives in one testable place:

```dart
// lib/features/proxy/model/outbound_health.dart
const unusableNodeDelay = 65000;
bool isUnusableNodeDelay(int? delay) => delay != null && delay >= unusableNodeDelay;
```

`ConnectionNotifier.build()` listens to `activeProxyNotifierProvider` (already eagerly listened in `bootstrap.dart`, so it is alive). Each event either arms or cancels a single timer:

- Not unusable — cancel any pending timer.
- Unusable and not yet released — arm a 10s timer if none is pending.

When the timer fires, re-check the preconditions that matter at that moment (still system-proxy mode, still connected) before calling `releaseSystemProxy()` and raising the toast. A boolean latch keeps one connection cycle to one release and one toast. `_disconnect` clears the latch so the next connect gets its own grace period.

The 10s grace absorbs the window between a reconnect and the first completed url test. A brief timeout inside that window is a flapping node, not a dead one.

No re-enable path. `SetSystemProxyEnabled` still refuses `isEnabled: true`, because the proxy has to point at a port the owning inbound holds.

### Subscription update health

A dedicated keep-alive notifier, because the existing state cannot express "some failed":

```dart
// lib/features/profile/notifier/profile_update_health.dart
@Riverpod(keepAlive: true)
class ProfileUpdateHealthNotifier extends _$ProfileUpdateHealthNotifier {
  @override
  Set<String> build() => const {};   // profile names whose last update failed

  bool get isDegraded => state.isNotEmpty;

  /// Records a failure, reporting whether it is the first for this profile so the
  /// dialog is raised once per profile rather than once per cycle.
  bool reportFailure(String name);

  void reportSuccess();
}
```

`ForegroundProfilesUpdateNotifier.updateProfiles()` accumulates failures for the cycle instead of reacting per profile:

- Each failure calls `reportFailure`; the newly-added names drive the dialog, so one cycle raises at most one dialog listing them.
- A cycle that finishes with **zero** failures calls `reportSuccess`, which empties the set.

Clearing only on a fully clean cycle is deliberate. Clearing on any single success would let a permanently broken secondary subscription be masked by a healthy primary one.

### Tray warning

`SystemTrayNotifier` listens to the health notifier and, when the degraded flag flips, refreshes the badge and the tooltip. The badge is factored out of `_trayTooltip` into `_applyTrayBadge()` so it can be driven from either place.

- macOS: the dock badge shows `⚠️` while degraded, replacing the latency readout. A warning outranks a latency number; the latency returns on recovery.
- Windows and Linux: the icon is unchanged — no new artwork. The tooltip carries the warning instead.
- The failing profile names go into the tooltip in both cases. This is what makes the tray-only case work: the dialog is dropped when there is no window context, so the badge and tooltip together are the only notice those users get.

## Data Flow

```text
core url-test results
  -> OutboundInfo.urlTestDelay
  -> ActiveProxyNotifier
  -> ConnectionNotifier: isUnusableNodeDelay -> 10s timer
  -> ConnectionRepository.releaseSystemProxy() -> core RPC -> DarwinSystemProxy.Disable()
  -> toast

scheduled update cycle
  -> ForegroundProfilesUpdateNotifier.updateProfiles()
  -> ProfileUpdateHealthNotifier.reportFailure / reportSuccess
  -> DialogNotifier.showProfileUpdateFailed(newNames)
  -> SystemTrayNotifier: dock badge + tooltip
```

## Error Handling

- The release RPC failing is logged, not surfaced. The connection is still up and the user has a working direct path, which is the state the release was trying to protect.
- A profile failing to update does not stop the cycle. Other subscriptions are still attempted, and the dialog and badge reflect whatever actually failed.
- `rootNavKey.currentContext == null` suppresses the dialog without recording the names as announced, so a later cycle can still raise it. The badge is unaffected.

## Testing

- `outbound_health.dart`: threshold boundaries, including `0` (cache, not a failure), `null`, and exactly `65000`.
- `ProfileUpdateHealthNotifier`: first failure reports new, a repeat does not, a clean cycle clears, a cycle with one failure leaves the rest standing.
- The grace timer: a timeout shorter than 10s does not release; a sustained one does.
- `SystemTrayNotifier`: badge is `⚠️` while degraded and the latency readout once clear.

## Open Questions

- Does macOS render `⚠️` in a dock badge, or does it collapse to a monochrome outline? If it does not survive, fall back to `!`. This needs a look on real hardware.
- The `65000` literal appears in four or five places already (`connection_button.dart`, `system_tray_notifier.dart`, `proxy_tile.dart`). Introducing the constant without folding the existing sites in leaves two ways to say the same thing; folding them in is a separate cleanup.