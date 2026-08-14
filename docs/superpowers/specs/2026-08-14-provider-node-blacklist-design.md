# Provider Node Blacklist Design

## Goal

Add CRUD, import, and export for provider node blacklists. Blacklisted nodes are hidden from the provider node list, skipped by automatic selection, and surfaced to the user when the currently selected node is blacklisted.

## Scope Decisions

- Rules are provider-aware and support a global default plus per-provider overrides.
- A rule matches multiple conditions with either `any` or `all` semantics.
- A provider can use the global rules, its own rules only, or global plus its own rules.
- Filtering applies to display, automatic selection, and current-node protection.
- Import and export support JSON, plain text, clipboard, and deep links.

## Data Model

The app stores all node blacklist data in one local file:

```text
<workingDir>/node_blacklist.json
```

The document shape:

```json
{
  "version": 1,
  "global": {
    "rules": []
  },
  "providers": {
    "<profileId>": {
      "policy": "useGlobal",
      "rules": []
    }
  }
}
```

Provider policy values:

- `useGlobal`: use global rules only.
- `customOnly`: use provider rules only.
- `globalPlusCustom`: use global and provider rules.

Rule shape:

```json
{
  "enabled": true,
  "name": "Block Hong Kong",
  "matchMode": "any",
  "conditions": [
    {
      "field": "countryCode",
      "operator": "equals",
      "value": "HK"
    }
  ]
}
```

Supported condition fields:

- `countryCode`
- `region`
- `city`
- `nodeName`
- `ipCidr`
- `asn`
- `organization`

Supported operators:

- `equals`
- `contains`
- `startsWith`
- `cidrMatch`

`cidrMatch` applies to IP/CIDR fields. The other operators apply to text fields.

## Matching Engine

Create a standalone `NodeBlacklistEngine` with one primary API:

```dart
bool isBlacklisted(OutboundInfo node);
List<BlacklistRule> matchingRules(OutboundInfo node);
```

Rules are OR-ed together: if any enabled rule matches, the node is blacklisted. Inside a rule, `matchMode` controls condition evaluation:

- `any`: any condition can match.
- `all`: every condition must match.

The engine resolves the effective rule set for a provider:

- `useGlobal`: global rules only.
- `customOnly`: provider rules only.
- `globalPlusCustom`: global rules plus provider rules.

The same engine is used by:

- provider node list filtering
- automatic node selection
- current-node blacklist protection

## Integration Points

### Provider Node List

- `ProxiesOverviewPage` filters blacklisted nodes by default.
- The page shows a count of filtered nodes.
- The user can temporarily show filtered nodes to inspect them and their matching reason.
- A top action opens blacklist management for the current active provider.

### Current Node Protection

- Automatic selection skips blacklisted nodes.
- If the currently selected node is blacklisted, the app does not force-disconnect.
- The app shows a notice with a recommended non-blacklisted node.
- The user can choose to switch or keep the current node.

### Global Management

- Add a global node blacklist route under Settings > Routing.
- The page supports create, read, update, enable/disable, and delete.

### Provider Management

- Provider details page includes a node blacklist section.
- The section manages provider policy and provider-specific rules.

## Import and Export

### JSON

- Export a JSON file or copy JSON to the clipboard.
- Import from a JSON file or clipboard.
- Import scope can target global rules, the current provider, or a full backup document.

### Plain Text

- Import plain text where each line is one value.
- The import dialog asks the user to choose the field type for the batch.
- Plain text is convenient for lists such as `HK`, `Hong Kong`, or organization names.

### Deep Link

- Export can generate:

```text
hiddify://settings/node-blacklist?data=<base64(json)>
```

- Opening the deep link shows a confirmation dialog before importing.
- The flow follows the existing route-rule deep-link pattern.

## Error Handling

- File read or JSON parse errors show an error and keep the last successfully loaded rules.
- Invalid rules during import are skipped and reported as `Ignored N invalid rules`.
- A missing provider uses `useGlobal`.
- Invalid provider policy falls back to `useGlobal`.
- Invalid rule match mode falls back to `any`.

## Testing

### Engine Unit Tests

- country code matching
- region and city matching
- node name keyword matching
- IP and CIDR matching
- ASN and organization matching
- `any` and `all` condition semantics
- provider policy resolution

### Import/Export Tests

- JSON round-trip
- plain-text import
- invalid-rule skipping
- deep-link encode/decode

### Integration Tests

- node list filtering
- temporary show-filtered toggle
- current-node protection state
- automatic selection skipping

## Out of Scope

- Modifying sing-box subscription configuration directly.
- Automatically disconnecting the current connection when a node becomes blacklisted.
- Cloud sync of blacklist rules.
