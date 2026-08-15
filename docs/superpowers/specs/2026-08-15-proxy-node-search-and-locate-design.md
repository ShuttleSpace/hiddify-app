# Proxy Node Search and Locate

## Summary

This change adds cross-group node search, jump-to-group highlighting, and automatic current-node location to the existing Hiddify proxy page. It does not add a separate search page or change how nodes are selected.

## Goals

- Search all proxy groups by group name or node name.
- Show a search result as group, node, and delay.
- On result tap, switch the proxy page to the matching group, scroll to the node, and briefly highlight it without selecting it.
- Automatically scroll to the currently selected node when the proxy page first loads.
- Keep the normal proxy grid usable when the search field is empty.

## Non-Goals

- Changing proxy selection semantics.
- Adding a separate full-screen search page.
- Persisting search terms.
- Editing, deleting, or blacklisting nodes from the search results.
- Replacing the current `ProxiesOverviewNotifier` group model.

## Current State

Hiddify's proxy page currently watches `proxiesOverviewNotifierProvider`, which returns a single `OutboundGroup` containing the selected group's items. Sorting is local to that group. There is no cross-group search or current-node auto-scroll.

`ProxyRepository` already exposes `watchActiveProxies()` as `Stream<Either<ProxyFailure, List<OutboundGroup>>>`, which is the correct source for all visible groups.

## Architecture

Add one read-only all-groups provider:

```text
ProxyRepository.watchActiveProxies()
  -> AllProxiesOverviewProvider
  -> ProxiesOverviewPage search results
```

The existing `proxiesOverviewNotifierProvider` remains the source for the currently displayed group. Search results are derived from `AllProxiesOverviewProvider`; they do not mutate the current group state.

## Data Model

### All group snapshot

The provider produces `AsyncValue<List<OutboundGroup>>`. Each group retains its tag, selected tag, and items.

### Search result

A page-local model:

```dart
class ProxySearchResult {
  const ProxySearchResult({
    required this.groupTag,
    required this.nodeTag,
    required this.delay,
  });

  final String groupTag;
  final String nodeTag;
  final int delay;
}
```

Search matches are case-insensitive against both group and node tags. Delay is copied from the node's `urlTestDelay`.

## Interaction Design

### Search field

The search field appears below the proxy page app bar. It is local state and does not persist. When empty, the normal current-group grid is shown.

### Search results

Results are shown in a constrained overlay below the search field. Each row displays:

```text
group name
node name - 128 ms
```

For an unknown or zero delay, display `--` instead of `0 ms`.

### Result tap

When a result is tapped:

1. The page requests the active group provider to display the target group.
2. The proxy grid scrolls to the target node.
3. The node is highlighted for a short duration.
4. The node is not selected.

If switching groups is not possible, the page stays on the current group and shows a non-blocking error message.

### Automatic current-node location

After the first non-empty current-group snapshot is received, the page scrolls once to the group's selected node. Subsequent group updates do not auto-scroll again unless the page is recreated or the user triggers a new search-result jump.

## Error Handling

- `watchActiveProxies` failure shows an error state in the search result area only; the current grid remains available.
- Group switch failure keeps the current group visible.
- Scroll or highlight failure does not block the page; it logs a diagnostic and leaves the grid unchanged.
- Empty search results show the existing "No proxies available" message.

## Testing Strategy

### Unit tests

- Filtering across groups by node name and group name, case-insensitive.
- Delay display uses `--` for zero delay.
- Result ordering is deterministic.
- Automatic-scroll trigger fires only once for the first non-empty snapshot.
- Result tap maps to the correct group and node targets.

### Provider tests

- `AllProxiesOverviewProvider` emits `AsyncError` when `watchActiveProxies` fails.
- It returns an empty list when no groups are active.

### Widget tests

- Search field appears above the grid.
- Empty search shows the normal grid.
- Non-empty search shows matching results.
- Tapping a result invokes group switch and node scroll/highlight callbacks.
- Error state in search does not hide the current grid.

## Rollout

This is a Flutter-only change. No core, Android, iOS, or database migration is required.
