# /commit-and-pr

Commit all changes in a workspace, push to the feature branch, and create a pull request.

## Usage

Type `/commit-and-pr` in Cursor chat, then provide:
- Workspace name (e.g., `workspace_20240101_120000`)
- Optional commit message (defaults to "Update from workspace")

## What it does

1. Commits all changes in the workspace
2. Pushes to the feature branch
3. Creates a PR using context from `.context.json` for the description

## Example

```
/commit-and-pr

Workspace name: workspace_20240101_120000
Commit message: Add OAuth authentication
```

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/commit-and-pr.sh <workspace-name> [commit-message]
```

The script is located at `${workspaceFolder}/scripts/commit-and-pr.sh` and must be executed from the workspace root.
