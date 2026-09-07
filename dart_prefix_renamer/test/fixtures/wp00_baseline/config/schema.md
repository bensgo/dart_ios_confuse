# WP-00 Schema Definitions

## Error Codes

All errors use stable error codes for programmatic handling:

| Code | Category | Description |
|------|----------|-------------|
| `E001` | Schema | Schema version mismatch |
| `E002` | Schema | Unknown field in YAML |
| `E003` | Schema | Missing required field |
| `E004` | Schema | Invalid field type |
| `E005` | Schema | Duplicate integration ID |
| `E006` | Path | Absolute path not allowed |
| `E007` | Path | Path traversal (`..`) detected |
| `E008` | Path | Path outside project root |
| `E009` | Config | Product ID conflict with CLI |
| `E010` | Config | Unknown capability in rules |
| `E011` | Config | Unknown capability in integration |
| `E012` | Config | Integration class not found |
| `E013` | Config | Integration method not found |
| `E014` | Config | Anchor not found in method |
| `E015` | Config | Duplicate integration for same class+capability |
| `E016` | Native | Unknown native capability |
| `E017` | Native | Unknown provider |
| `E018` | Native | Bridge consumer not found |
| `E019` | Dependency | Version not in lockfile |
| `E020` | Dependency | Lockfile mismatch |

## Path Safety Rules

1. All paths in config files MUST be relative to project root
2. Paths MUST NOT start with `/` or `~`
3. Paths MUST NOT contain `..` segments
4. Paths MUST resolve within project root directory
5. Paths use POSIX separators (`/`) regardless of platform

## Deterministic Snapshot Rules

1. All JSON output sorted by key
2. Timestamps excluded from comparison
3. SHA-256 of input files included in output
4. Tool version included in output
5. Seed values included for reproducibility

## Schema Versions

- `schema_version: 1` - Initial version (current)
- Future versions MUST be backward compatible for reading
- Writer always uses latest version
- Reader supports current and previous version