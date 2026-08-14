# Android Per-App Proxy Access Control Enhancement

## Summary

This change improves the existing Android per-app proxy page without changing core routing or iOS. It brings the most useful FLClash access-control ideas into Hiddify while preserving Hiddify's existing `off`, `include`, and `exclude` model.

The page remains the single place to manage per-app proxy. It gains a live effective-state summary, package filters for system apps and internet permission, and batch selection scoped to the currently visible list. Existing auto-selection, import/export, and immediate persistence continue to work.

## Goals

- Show which mode is active and how many apps are affected without opening the full list.
- Distinguish user-selected, auto-selected, and force-deselected entries in the summary.
- Filter the visible app list by system/non-system apps and apps with or without internet permission.
- Select or deselect all apps in the current filter result.
- Keep all writes immediately effective and visible in real time.
- Keep failed bulk writes observable and non-destructive.

## Non-Goals

- Changing hiddify-core rule generation.
- Changing iOS behavior.
- Adding a second, parallel per-app proxy page.
- Persisting filter choices as permanent user preferences.
- Rewriting the existing auto-selection region algorithm.
- Introducing a complex wizard or staged editing session.

## Current State

Hiddify already has:

- `PerAppProxyMode.off/include/exclude`.
- `AppProxyDao` with include and exclude tables.
- User, auto-selection, and force-deselection flags.
- Search, auto-selection, import/export, and immediate package updates.
- `PerAppProxyService` that writes the effective package lists into preferences consumed by core.

FLClash's `AccessView` adds useful interaction patterns: select-all, filter system and non-internet apps, and a clearer editing model. This design adopts the interaction patterns while keeping Hiddify's existing storage and routing model.

## Architecture

The work is limited to the Flutter Android feature layer:

```text
InstalledApps / package metadata
  -> PerAppProxyPage filters and batch-selection helpers
  -> PerAppProxyProvider / AppProxyDao
  -> Preferences includeApps/excludeApps
  -> existing core routing
```

No database schema migration is required.

## Data Model

### Display-only package metadata

`AppPackageInfo` is extended with read-only fields:

- `isSystemApp`: whether Android reports the package as a system app.
- `hasInternetPermission`: whether the package declares internet permission.

These fields are used only for filtering. They are not stored in `AppProxyEntries` and do not affect which packages are actually proxied.

If internet-permission metadata cannot be resolved on a device, the corresponding filter appears unavailable and the page provides a reload action. The unfiltered list remains usable.

### Effective-state summary

The page derives four numbers from the current mode and current package data:

- Active count: packages selected after applying user, auto-selection, and force-deselection flags.
- User-selected count.
- Auto-selected count.
- Force-deselected count.

The summary is computed in the presentation layer from the same data used by the list. It does not create a second source of truth.

## Interaction Design

### Mode summary

The existing mode selector remains. Below it, the page shows a compact summary:

```text
Proxy selected apps
12 active · 10 user-selected · 2 auto-selected
```

For `exclude`, wording reflects bypassed apps. The exact strings use existing translation infrastructure.

### Filters

Filter chips are placed between the mode summary and the app list:

- All
- System
- Non-system
- Has internet permission
- No internet permission

Only one of these filters is active at a time. Search is applied after the active filter. Filter state is local to the page and resets when the page is recreated.

### Batch selection

When a filter or search result is displayed, the page provides:

- Select all visible
- Deselect all visible

Both actions use the current visible list only. Existing flag semantics are preserved:

- Selecting an auto-selected item turns it into a user selection.
- Deselecting an auto-selected item applies force-deselection.
- Selecting a force-deselected item removes force-deselection.
- Selecting an unselected item adds user selection.

The operations reuse `updatePkg` rather than introducing a separate bulk write path.

### Error feedback

- Metadata lookup failure marks the affected filters unavailable.
- Bulk writes run independently per package.
- Successful writes remain saved.
- Failed package names are aggregated in one error toast after the batch completes.

## Testing Strategy

### Unit tests

- Filtering combinations for system/non-system and internet/no-internet.
- Search combined with each filter.
- Summary counts with mixed user, auto-selection, and force-deselection flags.
- Batch selection targets only visible packages.
- Batch selection preserves existing flag semantics.

### Widget tests

- Filter chips render and update the visible list.
- Select-all and deselect-all buttons invoke the expected provider actions.
- Summary updates after individual and batch changes.
- Metadata failure displays unavailable filters without hiding the app list.

### Regression tests

- Existing import/export and auto-selection flows continue to pass.
- Include and exclude modes remain independent.
- Core preference lists remain unchanged by presentation filtering.

## Rollout

No core or iOS changes are included. The Android UI is the only deployment surface.
