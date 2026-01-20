# /create-workspace

Create a new workspace by cloning the logyard2 repo to a unique folder and checking out a feature branch.

## Usage

Type `/create-workspace` in Cursor chat, then provide:
- Branch name (e.g., `feature/my-feature`)
- Context description explaining why this workspace exists

## What it does

1. Clones the logyard2 repository to a unique timestamped folder in `workspaces/`
2. Checks out or creates the specified feature branch
3. Creates a `.context.json` file with workspace metadata

## Example

```
/create-workspace

Branch name: feature/authentication
Context: Working on new OAuth integration
```

This will create `workspaces/workspace_20240101_120000/` with the feature branch checked out.

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/create-workspace.sh <branch-name> <context-description>
```

The script is located at `${workspaceFolder}/scripts/create-workspace.sh` and must be executed from the workspace root.
