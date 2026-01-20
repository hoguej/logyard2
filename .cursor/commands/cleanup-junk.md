# /cleanup-junk

Clean up junk files created by AI in a workspace before committing.

## Usage

Type `/cleanup-junk` in Cursor chat. Optionally provide:
- Workspace path (defaults to current directory)

## What it does

1. Creates a `junk/` folder in the current working directory (or specified workspace)
2. Moves junk files to the junk folder, including:
   - Random markdown files (excluding README.md, CHANGELOG.md, etc.)
   - AI-generated explanation files (explanation.md, notes.md, summary.md, etc.)
   - Temporary files (*.tmp, *.temp, etc.)
   - Backup files (*.bak, *.backup, etc.)

## What gets moved

- Markdown files in the root directory (except important ones like README.md)
- Files with names like `explanation.md`, `notes.md`, `summary.md`
- Files matching patterns like `*_explanation.*`, `*_notes.*`
- Temporary and backup files

## What's preserved

- README.md, CHANGELOG.md, LICENSE.md, CONTRIBUTING.md
- Files in `docs/` directory
- Files in `.cursor/commands/` directory
- Files in `node_modules/`, `.git/`, etc.

## Example

```
/cleanup-junk

Workspace path: workspaces/workspace_20240101_120000
```

This will move all junk files to `workspaces/workspace_20240101_120000/junk/`

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/cleanup-junk.sh [workspace-path]
```

The script is located at `${workspaceFolder}/scripts/cleanup-junk.sh` and must be executed from the workspace root.
