# /cleanup-archives

Remove old archived workspaces after a specified time period.

## Usage

Type `/cleanup-archives` in Cursor chat, then optionally provide:
- Number of days old (defaults to 30 days)

## What it does

1. Scans `workspaces/archive/` for old workspaces
2. Uses `archived_at` from `.context.json` or directory modification time
3. Removes workspaces older than the specified threshold

## Example

```
/cleanup-archives

Days old: 30
```

This will remove all archived workspaces that are 30 days or older.

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/cleanup-archives.sh [days-old]
```

The script is located at `${workspaceFolder}/scripts/cleanup-archives.sh` and must be executed from the workspace root. If no days-old argument is provided, use the default value of 30.
