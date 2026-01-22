# /ly-next

Complete workflow automation: feature branch, commit, code review, push, PR, merge, and checkout main.

## Usage

Type `/ly-next` in Cursor chat, optionally provide:
- Branch name (defaults to `feature/ly-next-YYYYMMDD-HHMMSS`)
- Commit message (defaults to "Update from ly-next")

## What it does

1. **Ensures feature branch from main**: Checks out main, pulls latest, creates/updates feature branch
2. **Commits changes**: Stages and commits all changes in project root
3. **Comprehensive code review**:
   - JavaScript syntax checking
   - Shell script syntax checking
   - TODO/FIXME detection
   - Console.log detection (warns)
   - Large file detection
   - Runs test suite (test-server.js, test-e2e.js)
4. **Fixes findings**: Stops if critical issues found (you fix them)
5. **Pushes to GitHub**: Pushes feature branch to origin
6. **Creates PR**: Creates pull request with automated description
7. **Merges PR**: Automatically merges the PR and deletes branch
8. **Checks out main**: Returns to main branch and pulls latest

## Example

```
/ly-next

Branch name: feature/add-new-feature
Commit message: Add new feature with tests
```

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/ly-next.sh [branch-name] [commit-message]
```

The script is located at `${workspaceFolder}/scripts/ly-next.sh` and must be executed from the workspace root.
