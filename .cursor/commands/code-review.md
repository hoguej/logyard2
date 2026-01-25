# /code-review

Comprehensive code review using best practices. Checks testing, security, consistency, and engineering best practices.

## Usage

Type `/code-review` in Cursor chat, optionally provide:
- Comparison mode (defaults to `auto`):
  - `auto` - Automatically detect: uncommitted changes vs main, or current branch vs main
  - `uncommitted` - Review uncommitted changes against main
  - `branch` - Review current branch against main
  - `compare <base> <head>` - Compare specific branches/commits (e.g., `compare main feature-branch`)

## What it checks

### Testing
- Unit tests exist and pass
- E2E tests exist and pass
- Test coverage for new code
- Test files follow naming conventions

### Security
- SQL injection vulnerabilities
- XSS vulnerabilities
- Hardcoded secrets/credentials
- Insecure file operations
- Command injection risks
- Insecure dependencies

### Code Quality
- Syntax errors (JavaScript, shell scripts)
- Code style consistency
- TODO/FIXME comments
- Console.log statements (warns)
- Large files
- Dead code / unused variables

### Best Practices
- Error handling
- Input validation
- Proper use of async/await
- Resource cleanup
- Documentation
- Type safety (where applicable)

### Consistency
- Naming conventions
- File structure
- Import/require patterns
- Code formatting

## Example

```
/code-review

Comparison: auto
```

Or with specific comparison:

```
/code-review

Comparison: compare main feature/add-auth
```

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/code-review.sh [comparison-mode] [base] [head]
```

The script is located at `${workspaceFolder}/scripts/code-review.sh` and must be executed from the workspace root.

## Output

The script provides:
- Summary of findings by category
- Detailed findings with file locations and line numbers
- Recommendations for fixes
- Overall pass/fail status
