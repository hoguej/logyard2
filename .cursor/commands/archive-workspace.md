# /archive-workspace

Archive a workspace by moving it to `workspaces/archive/`.

## Usage

Type `/archive-workspace` in Cursor chat, then provide:
- Workspace name (e.g., `workspace_20240101_120000`)

## What it does

1. Updates `.context.json` with an archived timestamp
2. Moves the workspace from `workspaces/` to `workspaces/archive/`

## Example

```
/archive-workspace

Workspace name: workspace_20240101_120000
```

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/archive-workspace.sh <workspace-name>
```

The script is located at `${workspaceFolder}/scripts/archive-workspace.sh` and must be executed from the workspace root.
