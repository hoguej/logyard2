#!/bin/bash
# /ly-next: Complete workflow - feature branch, commit, review, fix, push, PR, merge, checkout main
# Usage: ./scripts/ly-next.sh [branch-name] [commit-message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Generate branch name if not provided
BRANCH_NAME="${1:-feature/ly-next-$(date +%Y%m%d-%H%M%S)}"
COMMIT_MSG="${2:-Update from ly-next}"

log_info "Starting ly-next workflow..."
log_info "Branch: $BRANCH_NAME"
log_info "Commit message: $COMMIT_MSG"

# Step 1: Ensure we're on main and up to date
log_info "Step 1: Ensuring main branch is up to date..."
git checkout main 2>/dev/null || {
    log_error "Failed to checkout main branch"
    exit 1
}
git pull origin main || {
    log_warn "Could not pull from origin/main, continuing..."
}

# Step 2: Create feature branch from main
log_info "Step 2: Creating feature branch from main..."
if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    log_warn "Branch $BRANCH_NAME already exists, checking it out..."
    git checkout "$BRANCH_NAME"
    git merge main || {
        log_error "Failed to merge main into existing branch"
        exit 1
    }
else
    git checkout -b "$BRANCH_NAME"
fi

log_success "On feature branch: $BRANCH_NAME"

# Step 3: Check for changes
log_info "Step 3: Checking for changes..."
if git diff --quiet && git diff --cached --quiet; then
    log_warn "No changes to commit"
else
    # Step 4: Stage and commit
    log_info "Step 4: Staging and committing changes..."
    git add -A
    git commit -m "$COMMIT_MSG" || {
        log_error "Failed to commit changes"
        exit 1
    }
    log_success "Changes committed"
fi

# Step 5: Comprehensive code review
log_info "Step 5: Running comprehensive code review..."

REVIEW_FINDINGS=0

# Check for syntax errors in JavaScript files
log_info "  - Checking JavaScript syntax..."
JS_ERRORS=0
find app -name "*.js" -type f 2>/dev/null | while read -r file; do
    if [ -f "$file" ] && ! node -c "$file" 2>/dev/null; then
        log_error "    Syntax error in $file"
        JS_ERRORS=$((JS_ERRORS + 1))
    fi
done
# Note: JS_ERRORS won't be accessible outside the pipe, so we check files directly
for file in app/*.js; do
    if [ -f "$file" ] && ! node -c "$file" 2>/dev/null; then
        log_error "    Syntax error in $file"
        REVIEW_FINDINGS=$((REVIEW_FINDINGS + 1))
    fi
done

# Check for common issues in shell scripts
log_info "  - Checking shell scripts..."
for file in scripts/*.sh lib/*.sh; do
    if [ -f "$file" ] 2>/dev/null && ! bash -n "$file" 2>/dev/null; then
        log_error "    Syntax error in $file"
        REVIEW_FINDINGS=$((REVIEW_FINDINGS + 1))
    fi
done

# Check for TODO/FIXME comments
log_info "  - Checking for TODO/FIXME comments..."
TODO_COUNT=$(git diff main..HEAD | grep -i "TODO\|FIXME" | wc -l | tr -d ' ')
if [ "$TODO_COUNT" -gt 0 ]; then
    log_warn "    Found $TODO_COUNT TODO/FIXME comments in changes"
fi

# Check for console.log in production code (warn only)
log_info "  - Checking for console.log statements..."
CONSOLE_COUNT=$(git diff main..HEAD | grep -c "console\.log" || echo "0")
if [ "$CONSOLE_COUNT" -gt 0 ]; then
    log_warn "    Found $CONSOLE_COUNT console.log statements (consider removing for production)"
fi

# Check for large files
log_info "  - Checking for large files..."
git diff --cached --name-only | while read -r file; do
    if [ -f "$file" ]; then
        SIZE=$(wc -c < "$file" | tr -d ' ')
        if [ "$SIZE" -gt 1048576 ]; then  # 1MB
            log_warn "    Large file detected: $file ($(numfmt --to=iec-i --suffix=B $SIZE))"
        fi
    fi
done

# Run tests if they exist
log_info "  - Running tests..."
if [ -f "app/test-server.js" ]; then
    if node app/test-server.js > /tmp/ly-next-test.log 2>&1; then
        log_success "    Server test passed"
    else
        log_error "    Server test failed"
        REVIEW_FINDINGS=$((REVIEW_FINDINGS + 1))
        cat /tmp/ly-next-test.log | tail -10
    fi
fi

if [ -f "app/test-e2e.js" ]; then
    if node app/test-e2e.js > /tmp/ly-next-e2e.log 2>&1; then
        log_success "    E2E test passed"
    else
        log_error "    E2E test failed"
        REVIEW_FINDINGS=$((REVIEW_FINDINGS + 1))
        cat /tmp/ly-next-e2e.log | tail -10
    fi
fi

if [ "$REVIEW_FINDINGS" -gt 0 ]; then
    log_error "Code review found $REVIEW_FINDINGS issue(s)"
    log_info "Please fix the issues above before continuing"
    exit 1
fi

log_success "Code review passed"

# Step 6: Push to GitHub
log_info "Step 6: Pushing to GitHub..."
git push -u origin "$BRANCH_NAME" || {
    log_error "Failed to push to GitHub"
    exit 1
}
log_success "Pushed to GitHub"

# Step 7: Create PR
log_info "Step 7: Creating pull request..."
if ! command -v gh &> /dev/null; then
    log_warn "GitHub CLI (gh) not found, skipping PR creation"
    log_info "Create PR manually at: https://github.com/hoguej/logyard2/compare/$BRANCH_NAME"
else
    PR_NUMBER=$(gh pr create \
        --title "$COMMIT_MSG" \
        --body "Automated PR from ly-next workflow

## Changes
$COMMIT_MSG

## Review
- Code review passed
- Tests passed
- Ready for merge" \
        --head "$BRANCH_NAME" \
        --base main \
        --json number \
        --jq '.number' 2>/dev/null || echo "")

    if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ]; then
        log_success "PR created: #$PR_NUMBER"
        PR_URL="https://github.com/hoguej/logyard2/pull/$PR_NUMBER"
        log_info "PR URL: $PR_URL"

        # Step 8: Merge PR
        log_info "Step 8: Merging pull request..."
        gh pr merge "$PR_NUMBER" --merge --delete-branch || {
            log_error "Failed to merge PR"
            exit 1
        }
        log_success "PR merged"
    else
        log_warn "Could not create PR, may already exist"
        EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null || echo "")
        if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
            log_info "Merging existing PR: #$EXISTING_PR"
            gh pr merge "$EXISTING_PR" --merge --delete-branch || {
                log_error "Failed to merge existing PR"
                exit 1
            }
            log_success "PR merged"
        fi
    fi
fi

# Step 9: Checkout main and pull latest
log_info "Step 9: Checking out main and pulling latest..."
git checkout main
git pull origin main || {
    log_warn "Could not pull latest from main"
}

log_success "✓ ly-next workflow completed successfully!"
log_info "You are now on main branch with latest changes"
