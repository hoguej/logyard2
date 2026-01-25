#!/bin/bash
# /code-review: Comprehensive code review using best practices
# Usage: ./scripts/code-review.sh [comparison-mode] [base] [head]
#
# Comparison modes:
#   auto - Automatically detect: uncommitted vs main, or current branch vs main
#   uncommitted - Review uncommitted changes against main
#   branch - Review current branch against main
#   compare <base> <head> - Compare specific branches/commits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Create code-reviews directory
mkdir -p code-reviews

# Generate unique report filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="code-reviews/review-${TIMESTAMP}.html"

# Arrays to store findings
declare -a FINDINGS=()
FINDING_ID=0

# Rating mapping
get_rating() {
    case "$1" in
        error) echo "critical" ;;
        warn) echo "high" ;;
        info) echo "medium" ;;
        *) echo "low" ;;
    esac
}

# Add finding with structured format
add_finding() {
    local rating=$1
    local category=$2
    local file=$3
    local line=$4
    local socratic=$5
    local sustaining=$6
    local ai_prompt=$7
    
    FINDING_ID=$((FINDING_ID + 1))
    local id="FINDING-${FINDING_ID}"
    
    FINDINGS+=("$id|$rating|$category|$file|$line|$socratic|$sustaining|$ai_prompt")
}

# Determine comparison mode
COMPARISON_MODE="${1:-auto}"
BASE_REF="${2:-main}"
HEAD_REF="${3:-HEAD}"

echo "🔍 Starting code review..."
echo "   Comparison mode: $COMPARISON_MODE"
echo "   Project root: $PROJECT_ROOT"

# Determine what to review
REVIEW_FILES=()
DIFF_CMD=""
COMPARISON_DESC=""

case "$COMPARISON_MODE" in
    auto)
        if ! git diff --quiet || ! git diff --cached --quiet; then
            COMPARISON_DESC="Uncommitted changes vs main"
            DIFF_CMD="git diff main"
            REVIEW_FILES=($(git diff --name-only main | grep -E '\.(js|sh|html|css|json|md)$' || true))
        else
            CURRENT_BRANCH=$(git branch --show-current)
            if [ "$CURRENT_BRANCH" != "main" ]; then
                COMPARISON_DESC="Branch '$CURRENT_BRANCH' vs main"
                DIFF_CMD="git diff main..$CURRENT_BRANCH"
                REVIEW_FILES=($(git diff --name-only main..$CURRENT_BRANCH | grep -E '\.(js|sh|html|css|json|md)$' || true))
            else
                COMPARISON_DESC="All files (on main branch)"
                REVIEW_FILES=($(find . -type f \( -name "*.js" -o -name "*.sh" \) ! -path "./node_modules/*" ! -path "./.git/*" ! -path "./workspaces/*" ! -path "./tmp/*" ! -path "./code-reviews/*" | head -20))
            fi
        fi
        ;;
    uncommitted)
        COMPARISON_DESC="Uncommitted changes vs main"
        DIFF_CMD="git diff main"
        REVIEW_FILES=($(git diff --name-only main | grep -E '\.(js|sh|html|css|json|md)$' || true))
        ;;
    branch)
        CURRENT_BRANCH=$(git branch --show-current)
        COMPARISON_DESC="Branch '$CURRENT_BRANCH' vs main"
        DIFF_CMD="git diff main..$CURRENT_BRANCH"
        REVIEW_FILES=($(git diff --name-only main..$CURRENT_BRANCH | grep -E '\.(js|sh|html|css|json|md)$' || true))
        ;;
    compare)
        COMPARISON_DESC="$BASE_REF vs $HEAD_REF"
        DIFF_CMD="git diff $BASE_REF..$HEAD_REF"
        REVIEW_FILES=($(git diff --name-only $BASE_REF..$HEAD_REF | grep -E '\.(js|sh|html|css|json|md)$' || true))
        ;;
    *)
        echo "❌ Unknown comparison mode: $COMPARISON_MODE"
        echo "Valid modes: auto, uncommitted, branch, compare"
        exit 1
        ;;
esac

if [ ${#REVIEW_FILES[@]} -eq 0 ]; then
    echo "⚠️  No files to review"
    exit 0
fi

echo "   Reviewing ${#REVIEW_FILES[@]} file(s)"

# ============================================================================
# 1. SYNTAX CHECKING
# ============================================================================
echo "   Checking syntax..."

for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        ERROR_OUTPUT=$(node -c "$file" 2>&1 || true)
        if [ -n "$ERROR_OUTPUT" ]; then
            LINE_NUM=$(echo "$ERROR_OUTPUT" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1 || echo "?")
            add_finding "critical" "Syntax" "$file" "$LINE_NUM" \
                "Will this syntax error prevent the code from running?" \
                "I'm noticing a JavaScript syntax error in $file at line $LINE_NUM. The error message indicates: ${ERROR_OUTPUT:0:100}" \
                "To resolve this, fix the syntax error at line $LINE_NUM in $file. The error is: $ERROR_OUTPUT"
        fi
    fi
    
    if [[ "$file" == *.sh ]] && [ -f "$file" ]; then
        ERROR_OUTPUT=$(bash -n "$file" 2>&1 || true)
        if [ -n "$ERROR_OUTPUT" ]; then
            LINE_NUM=$(echo "$ERROR_OUTPUT" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' | head -1 || echo "?")
            add_finding "critical" "Syntax" "$file" "$LINE_NUM" \
                "Will this shell script syntax error prevent execution?" \
                "I'm noticing a shell script syntax error in $file at line $LINE_NUM. The error message indicates: ${ERROR_OUTPUT:0:100}" \
                "To resolve this, fix the syntax error at line $LINE_NUM in $file. The error is: $ERROR_OUTPUT"
        fi
    fi
done

# ============================================================================
# 2. TESTING
# ============================================================================
echo "   Checking tests..."

# Unit tests
if [ -f "app/test-server.js" ]; then
    if ! node app/test-server.js > /tmp/code-review-unit-test.log 2>&1; then
        ERROR_OUTPUT=$(tail -30 /tmp/code-review-unit-test.log)
        add_finding "critical" "Testing" "app/test-server.js" "?" \
            "Will these failing unit tests cause production issues?" \
            "I'm noticing that the unit tests in app/test-server.js are failing. This indicates that the code may not work as expected." \
            "To resolve this, fix the failing unit tests. Review the test output: $ERROR_OUTPUT"
    fi
else
    add_finding "high" "Testing" "." "?" \
        "Will the lack of unit tests make it harder to catch regressions?" \
        "I'm noticing that there's no unit test file (app/test-server.js) in the project." \
        "To resolve this, consider adding unit tests for your code changes. Create test files that cover the main functionality."
fi

# E2E tests
if [ -f "app/test-e2e.js" ]; then
    if ! node app/test-e2e.js > /tmp/code-review-e2e-test.log 2>&1; then
        ERROR_OUTPUT=$(tail -30 /tmp/code-review-e2e-test.log)
        add_finding "critical" "Testing" "app/test-e2e.js" "?" \
            "Will these failing E2E tests indicate integration problems?" \
            "I'm noticing that the E2E tests in app/test-e2e.js are failing. This suggests integration issues." \
            "To resolve this, fix the failing E2E tests. Review the test output: $ERROR_OUTPUT"
    fi
else
    add_finding "medium" "Testing" "." "?" \
        "Will the lack of E2E tests make it harder to verify end-to-end functionality?" \
        "I'm noticing that there's no E2E test file (app/test-e2e.js) in the project." \
        "To resolve this, consider adding E2E tests to verify the complete user workflows."
fi

# Test coverage
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [[ ! "$file" == *test*.js ]] && [[ ! "$file" == *spec*.js ]]; then
        BASENAME=$(basename "$file" .js)
        DIRNAME=$(dirname "$file")
        if [ ! -f "${DIRNAME}/test-${BASENAME}.js" ] && [ ! -f "${DIRNAME}/${BASENAME}.test.js" ] && [ ! -f "${DIRNAME}/${BASENAME}.spec.js" ]; then
            add_finding "medium" "Testing" "$file" "?" \
                "Will the lack of tests for this file make it harder to maintain?" \
                "I'm noticing that $file doesn't have a corresponding test file." \
                "To resolve this, create a test file for $file (e.g., ${DIRNAME}/test-${BASENAME}.js) to ensure the code works correctly."
        fi
    fi
done

# ============================================================================
# 3. SECURITY
# ============================================================================
echo "   Checking security..."

# SQL Injection - Group by file
SQL_FILES_DATA=""
for file in "${REVIEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        LINE_NUM=0
        LINES=""
        while IFS= read -r line || [ -n "$line" ]; do
            LINE_NUM=$((LINE_NUM + 1))
            if echo "$line" | grep -qE "(SELECT|INSERT|UPDATE|DELETE).*\+.*['\"]" && ! echo "$line" | grep -qE "(prepared|parameterized|placeholder|\?)"; then
                if [ -z "$LINES" ]; then
                    LINES="$LINE_NUM"
                else
                    LINES="$LINES, $LINE_NUM"
                fi
            fi
        done < "$file" || true
        if [ -n "$LINES" ]; then
            SQL_FILES_DATA="${SQL_FILES_DATA}${file}|${LINES}
"
        fi
    fi
done
if [ -n "$SQL_FILES_DATA" ]; then
    while IFS='|' read -r file LINES; do
        [ -z "$file" ] && continue
        LINE_COUNT=$(echo "$LINES" | tr ',' '\n' | wc -l | tr -d ' ')
        add_finding "critical" "Security" "$file" "$LINES" \
            "Will this SQL query with string concatenation allow SQL injection attacks?" \
            "I'm noticing $LINE_COUNT SQL query construction(s) using string concatenation in $file at line(s): $LINES. This pattern is vulnerable to SQL injection if user input is included." \
            "To resolve this, use parameterized queries or prepared statements instead of string concatenation. For example, use placeholders like '?' or named parameters."
    done <<< "$SQL_FILES_DATA"
fi

# XSS vulnerabilities - Group by file
XSS_FILES_DATA=""
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        LINE_NUM=0
        LINES=""
        while IFS= read -r line || [ -n "$line" ]; do
            LINE_NUM=$((LINE_NUM + 1))
            if echo "$line" | grep -q "innerHTML.*\+" && ! echo "$line" | grep -qE "escapeHtml|textContent"; then
                if [ -z "$LINES" ]; then
                    LINES="$LINE_NUM"
                else
                    LINES="$LINES, $LINE_NUM"
                fi
            fi
        done < "$file" || true
        if [ -n "$LINES" ]; then
            XSS_FILES_DATA="${XSS_FILES_DATA}${file}|${LINES}
"
        fi
    fi
done
if [ -n "$XSS_FILES_DATA" ]; then
    while IFS='|' read -r file LINES; do
        [ -z "$file" ] && continue
        LINE_COUNT=$(echo "$LINES" | tr ',' '\n' | wc -l | tr -d ' ')
        add_finding "high" "Security" "$file" "$LINES" \
            "Will setting innerHTML with unescaped content allow XSS attacks?" \
            "I'm noticing $LINE_COUNT instance(s) of innerHTML being set with string concatenation in $file at line(s): $LINES without escaping. This could allow XSS if user input is included." \
            "To resolve this, use textContent for plain text, or escapeHtml() before setting innerHTML. Alternatively, use DOM methods like createElement and appendChild."
    done <<< "$XSS_FILES_DATA"
fi

# Hardcoded secrets - Group by file
SECRET_FILES_DATA=""
for file in "${REVIEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        LINE_NUM=0
        LINES=""
        while IFS= read -r line || [ -n "$line" ]; do
            LINE_NUM=$((LINE_NUM + 1))
            if echo "$line" | grep -qiE "password.*=.*['\"].*['\"]|api[_-]?key.*=.*['\"].*['\"]|secret.*=.*['\"].*['\"]|token.*=.*['\"].*['\"]"; then
                if [ -z "$LINES" ]; then
                    LINES="$LINE_NUM"
                else
                    LINES="$LINES, $LINE_NUM"
                fi
            fi
        done < "$file" || true
        if [ -n "$LINES" ]; then
            SECRET_FILES_DATA="${SECRET_FILES_DATA}${file}|${LINES}
"
        fi
    fi
done
if [ -n "$SECRET_FILES_DATA" ]; then
    while IFS='|' read -r file LINES; do
        [ -z "$file" ] && continue
        LINE_COUNT=$(echo "$LINES" | tr ',' '\n' | wc -l | tr -d ' ')
        add_finding "critical" "Security" "$file" "$LINES" \
            "Will hardcoding secrets in source code expose sensitive credentials?" \
            "I'm noticing $LINE_COUNT potential hardcoded secret(s) (password, API key, secret, or token) in $file at line(s): $LINES." \
            "To resolve this, move secrets to environment variables or a secure configuration system. Never commit secrets to version control."
    done <<< "$SECRET_FILES_DATA"
fi

# Command injection - SKIPPED: Local-only codebase, single user control

# ============================================================================
# 4. CODE QUALITY
# ============================================================================
echo "   Checking code quality..."

# TODO/FIXME - Group by file
TODO_FILES_DATA=""
if [ -n "$DIFF_CMD" ]; then
    TODO_LINES=$(eval "$DIFF_CMD" | grep -nE "TODO|FIXME" || true)
    if [ -n "$TODO_LINES" ]; then
        while IFS= read -r todo_line; do
            FILE_PATH=$(echo "$todo_line" | grep -oE "^[^:]+" | head -1 || echo "?")
            LINE_NUM=$(echo "$todo_line" | grep -oE ":[0-9]+" | grep -oE "[0-9]+" | head -1 || echo "?")
            if [ -n "$FILE_PATH" ] && [ "$FILE_PATH" != "?" ]; then
                EXISTING=$(echo "$TODO_FILES_DATA" | grep "^${FILE_PATH}|" || true)
                if [ -z "$EXISTING" ]; then
                    TODO_FILES_DATA="${TODO_FILES_DATA}${FILE_PATH}|${LINE_NUM}
"
                else
                    OLD_LINES=$(echo "$EXISTING" | cut -d'|' -f2)
                    NEW_LINES="$OLD_LINES, $LINE_NUM"
                    TODO_FILES_DATA=$(echo "$TODO_FILES_DATA" | grep -v "^${FILE_PATH}|")
                    TODO_FILES_DATA="${TODO_FILES_DATA}${FILE_PATH}|${NEW_LINES}
"
                fi
            fi
        done <<< "$TODO_LINES"
        if [ -n "$TODO_FILES_DATA" ]; then
            while IFS='|' read -r file_path LINES; do
                [ -z "$file_path" ] && continue
                LINE_COUNT=$(echo "$LINES" | tr ',' '\n' | wc -l | tr -d ' ')
                add_finding "medium" "Code Quality" "$file_path" "$LINES" \
                    "Will leaving TODO/FIXME comments cause issues to be forgotten?" \
                    "I'm noticing $LINE_COUNT TODO or FIXME comment(s) in $file_path at line(s): $LINES." \
                    "To resolve this, either implement the TODO/FIXME items or create tracking issues and remove the comments."
            done <<< "$TODO_FILES_DATA"
        fi
    fi
fi

# Console.log - Group by file
CONSOLE_FILES_DATA=""
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        LINE_NUM=0
        LINES=""
        while IFS= read -r line || [ -n "$line" ]; do
            LINE_NUM=$((LINE_NUM + 1))
            if echo "$line" | grep -q "console\.log"; then
                if [ -z "$LINES" ]; then
                    LINES="$LINE_NUM"
                else
                    LINES="$LINES, $LINE_NUM"
                fi
            fi
        done < "$file" || true
        if [ -n "$LINES" ]; then
            CONSOLE_FILES_DATA="${CONSOLE_FILES_DATA}${file}|${LINES}
"
        fi
    fi
done
if [ -n "$CONSOLE_FILES_DATA" ]; then
    while IFS='|' read -r file LINES; do
        [ -z "$file" ] && continue
        LINE_COUNT=$(echo "$LINES" | tr ',' '\n' | wc -l | tr -d ' ')
        add_finding "low" "Code Quality" "$file" "$LINES" \
            "Will console.log statements in production code expose sensitive information or clutter logs?" \
            "I'm noticing $LINE_COUNT console.log statement(s) in $file at line(s): $LINES." \
            "To resolve this, remove console.log statements or replace them with a proper logging library that can be controlled by environment."
    done <<< "$CONSOLE_FILES_DATA"
fi

# Large files
for file in "${REVIEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        SIZE=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$SIZE" -gt 1048576 ]; then  # 1MB
            SIZE_HR=$(numfmt --to=iec-i --suffix=B $SIZE 2>/dev/null || echo "${SIZE} bytes")
            add_finding "medium" "Code Quality" "$file" "?" \
                "Will this large file be harder to maintain and review?" \
                "I'm noticing that $file is quite large ($SIZE_HR). Large files can be difficult to maintain." \
                "To resolve this, consider splitting the file into smaller, more focused modules."
        fi
    fi
done

# Error handling
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        ASYNC_COUNT=$(grep -cE "async.*function|async\s+\(" "$file" || echo "0")
        TRY_COUNT=$(grep -c "try\s*{" "$file" || echo "0")
        if [ "$ASYNC_COUNT" -gt 0 ] && [ "$ASYNC_COUNT" -gt "$TRY_COUNT" ]; then
            add_finding "high" "Code Quality" "$file" "?" \
                "Will async functions without error handling cause unhandled promise rejections?" \
                "I'm noticing that $file has $ASYNC_COUNT async functions but only $TRY_COUNT try-catch blocks. Some async functions may lack error handling." \
                "To resolve this, wrap async function calls in try-catch blocks or use .catch() handlers to prevent unhandled promise rejections."
        fi
    fi
done

# ============================================================================
# 5. BEST PRACTICES
# ============================================================================
echo "   Checking best practices..."

# Input validation
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        if grep -qE "req\.(body|query|params)\." "$file" 2>/dev/null && ! grep -qE "(validate|sanitize|check)" "$file" 2>/dev/null; then
            add_finding "high" "Best Practices" "$file" "?" \
                "Will unvalidated user input cause errors or security issues?" \
                "I'm noticing that $file uses req.body, req.query, or req.params but doesn't appear to validate the input." \
                "To resolve this, add input validation using a library like joi, express-validator, or custom validation functions before using user input."
        fi
    fi
done

# Resource cleanup
for file in "${REVIEW_FILES[@]}"; do
    if [[ "$file" == *.js ]] && [ -f "$file" ]; then
        if grep -qE "(createReadStream|createWriteStream|createConnection)" "$file" 2>/dev/null && ! grep -qE "(\.close\(|\.destroy\(|\.end\()" "$file" 2>/dev/null; then
            add_finding "high" "Best Practices" "$file" "?" \
                "Will unclosed resources cause memory leaks or connection pool exhaustion?" \
                "I'm noticing that $file creates resources (streams, connections) but doesn't appear to close them." \
                "To resolve this, ensure all resources are properly closed using .close(), .destroy(), or .end() methods, preferably in finally blocks or cleanup handlers."
        fi
    fi
done

# ============================================================================
# GENERATE HTML REPORT
# ============================================================================
echo "   Generating HTML report..."

# Count findings by rating
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
INFO_COUNT=0

for finding in "${FINDINGS[@]:-}"; do
    IFS='|' read -r id rating category file line socratic sustaining ai_prompt <<< "$finding"
    case "$rating" in
        critical) CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
        high) HIGH_COUNT=$((HIGH_COUNT + 1)) ;;
        medium) MEDIUM_COUNT=$((MEDIUM_COUNT + 1)) ;;
        low) LOW_COUNT=$((LOW_COUNT + 1)) ;;
        info) INFO_COUNT=$((INFO_COUNT + 1)) ;;
    esac
done

TOTAL_FINDINGS=${#FINDINGS[@]:-0}

# Generate HTML
cat > "$REPORT_FILE" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Code Review Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 30px;
        }
        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 2em;
        }
        .header-info {
            color: #7f8c8d;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 2px solid #ecf0f1;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .summary-card {
            padding: 20px;
            border-radius: 6px;
            text-align: center;
        }
        .summary-card.total { background: #3498db; color: white; }
        .summary-card.critical { background: #e74c3c; color: white; }
        .summary-card.high { background: #e67e22; color: white; }
        .summary-card.medium { background: #f39c12; color: white; }
        .summary-card.low { background: #95a5a6; color: white; }
        .summary-card.info { background: #3498db; color: white; }
        .summary-card .number {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .summary-card .label {
            font-size: 0.9em;
            opacity: 0.9;
        }
        .finding {
            margin-bottom: 25px;
            padding: 20px;
            border-left: 4px solid #ddd;
            background: #fafafa;
            border-radius: 4px;
            position: relative;
        }
        .finding.critical { border-left-color: #e74c3c; }
        .finding.high { border-left-color: #e67e22; }
        .finding.medium { border-left-color: #f39c12; }
        .finding.low { border-left-color: #95a5a6; }
        .finding.info { border-left-color: #3498db; }
        .finding-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .finding-id {
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 0.85em;
            color: #7f8c8d;
            background: #ecf0f1;
            padding: 4px 8px;
            border-radius: 4px;
        }
        .finding-rating {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: bold;
            text-transform: uppercase;
        }
        .finding-rating.critical { background: #e74c3c; color: white; }
        .finding-rating.high { background: #e67e22; color: white; }
        .finding-rating.medium { background: #f39c12; color: white; }
        .finding-rating.low { background: #95a5a6; color: white; }
        .finding-rating.info { background: #3498db; color: white; }
        .finding-meta {
            font-size: 0.9em;
            color: #7f8c8d;
            margin-bottom: 15px;
        }
        .finding-section {
            margin-bottom: 15px;
        }
        .finding-section h3 {
            font-size: 0.95em;
            color: #2c3e50;
            margin-bottom: 8px;
            font-weight: 600;
        }
        .finding-section p {
            color: #555;
            margin-bottom: 5px;
        }
        .copy-btn {
            position: absolute;
            top: 20px;
            right: 20px;
            background: #3498db;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85em;
            transition: background 0.2s;
        }
        .copy-btn:hover {
            background: #2980b9;
        }
        .copy-btn:active {
            background: #21618c;
        }
        .copy-btn.copied {
            background: #27ae60;
        }
        .category-badge {
            display: inline-block;
            background: #ecf0f1;
            color: #2c3e50;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 0.8em;
            margin-right: 8px;
        }
        .file-path {
            font-family: 'Monaco', 'Menlo', monospace;
            color: #3498db;
        }
        .no-findings {
            text-align: center;
            padding: 40px;
            color: #27ae60;
            font-size: 1.2em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Code Review Report</h1>
        <div class="header-info">
            <p><strong>Comparison:</strong> COMPARISON_PLACEHOLDER</p>
            <p><strong>Files Reviewed:</strong> FILES_COUNT_PLACEHOLDER</p>
            <p><strong>Generated:</strong> TIMESTAMP_PLACEHOLDER</p>
        </div>
        
        <div class="summary">
            <div class="summary-card total">
                <div class="number">TOTAL_PLACEHOLDER</div>
                <div class="label">Total Findings</div>
            </div>
            <div class="summary-card critical">
                <div class="number">CRITICAL_PLACEHOLDER</div>
                <div class="label">Critical</div>
            </div>
            <div class="summary-card high">
                <div class="number">HIGH_PLACEHOLDER</div>
                <div class="label">High</div>
            </div>
            <div class="summary-card medium">
                <div class="number">MEDIUM_PLACEHOLDER</div>
                <div class="label">Medium</div>
            </div>
            <div class="summary-card low">
                <div class="number">LOW_PLACEHOLDER</div>
                <div class="label">Low</div>
            </div>
            <div class="summary-card info">
                <div class="number">INFO_PLACEHOLDER</div>
                <div class="label">Info</div>
            </div>
        </div>
        
        FINDINGS_PLACEHOLDER
    </div>
    
    <script>
        function copyFinding(findingId) {
            const finding = document.getElementById(findingId);
            const id = finding.querySelector('.finding-id').textContent;
            const rating = finding.querySelector('.finding-rating').textContent;
            const category = finding.querySelector('.category-badge').textContent;
            const file = finding.querySelector('.file-path').textContent;
            const metaText = finding.querySelector('.finding-meta').textContent;
            const lineMatch = metaText.match(/\\(line (\\d+)\\)/);
            const line = lineMatch ? lineMatch[1] : '';
            const socratic = finding.querySelectorAll('.finding-section')[0].querySelector('p').textContent;
            const sustaining = finding.querySelectorAll('.finding-section')[1].querySelector('p').textContent;
            const aiPrompt = finding.querySelectorAll('.finding-section')[2].querySelector('p').textContent;
            
            const text = `Finding ID: ${id}
Rating: ${rating}
Category: ${category}
File: ${file}${line ? ' (line ' + line + ')' : ''}

🤔 Socratic Question:
${socratic}

📋 Sustaining Details:
${sustaining}

🔧 AI Prompt to Fix:
${aiPrompt}`;
            
            navigator.clipboard.writeText(text).then(() => {
                const btn = finding.querySelector('.copy-btn');
                const originalText = btn.textContent;
                btn.textContent = '✓ Copied!';
                btn.classList.add('copied');
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.classList.remove('copied');
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy:', err);
                alert('Failed to copy to clipboard');
            });
        }
    </script>
</body>
</html>
HTML_EOF

# Replace placeholders
# Generate findings HTML
if [ ${#FINDINGS[@]:-0} -eq 0 ]; then
    FINDINGS_HTML='<div class="no-findings">✓ No issues found! Code review passed.</div>'
else
    FINDINGS_HTML=""
    for finding in "${FINDINGS[@]:-}"; do
        IFS='|' read -r id rating category file line socratic sustaining ai_prompt <<< "$finding"
        
        # Escape HTML in text fields
        socratic_escaped=$(echo "$socratic" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        sustaining_escaped=$(echo "$sustaining" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        ai_prompt_escaped=$(echo "$ai_prompt" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        file_escaped=$(echo "$file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        
        FINDINGS_HTML+="<div class=\"finding $rating\" id=\"$id\">"
        FINDINGS_HTML+="<button class=\"copy-btn\" onclick=\"copyFinding('$id')\">Copy Finding</button>"
        FINDINGS_HTML+="<div class=\"finding-header\">"
        FINDINGS_HTML+="<span class=\"finding-id\">$id</span>"
        FINDINGS_HTML+="<span class=\"finding-rating $rating\">$rating</span>"
        FINDINGS_HTML+="</div>"
        FINDINGS_HTML+="<div class=\"finding-meta\">"
        FINDINGS_HTML+="<span class=\"category-badge\">$category</span>"
        FINDINGS_HTML+="<span class=\"file-path\">$file_escaped</span>"
        if [ "$line" != "?" ]; then
            FINDINGS_HTML+=" <span style=\"color: #7f8c8d;\">(line $line)</span>"
        fi
        FINDINGS_HTML+="</div>"
        FINDINGS_HTML+="<div class=\"finding-section\">"
        FINDINGS_HTML+="<h3>🤔 Socratic Question</h3>"
        FINDINGS_HTML+="<p>$socratic_escaped</p>"
        FINDINGS_HTML+="</div>"
        FINDINGS_HTML+="<div class=\"finding-section\">"
        FINDINGS_HTML+="<h3>📋 Sustaining Details</h3>"
        FINDINGS_HTML+="<p>$sustaining_escaped</p>"
        FINDINGS_HTML+="</div>"
        FINDINGS_HTML+="<div class=\"finding-section\">"
        FINDINGS_HTML+="<h3>🔧 AI Prompt to Fix</h3>"
        FINDINGS_HTML+="<p>$ai_prompt_escaped</p>"
        FINDINGS_HTML+="</div>"
        FINDINGS_HTML+="</div>"
    done
fi

# Replace all placeholders at once using a temp file
TEMP_FILE="${REPORT_FILE}.tmp"
sed "s|COMPARISON_PLACEHOLDER|$COMPARISON_DESC|g; \
     s|FILES_COUNT_PLACEHOLDER|${#REVIEW_FILES[@]}|g; \
     s|TIMESTAMP_PLACEHOLDER|$(date '+%Y-%m-%d %H:%M:%S')|g; \
     s|TOTAL_PLACEHOLDER|$TOTAL_FINDINGS|g; \
     s|CRITICAL_PLACEHOLDER|$CRITICAL_COUNT|g; \
     s|HIGH_PLACEHOLDER|$HIGH_COUNT|g; \
     s|MEDIUM_PLACEHOLDER|$MEDIUM_COUNT|g; \
     s|LOW_PLACEHOLDER|$LOW_COUNT|g; \
     s|INFO_PLACEHOLDER|$INFO_COUNT|g; \
     s|FINDINGS_PLACEHOLDER|$FINDINGS_HTML|g" "$REPORT_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$REPORT_FILE"

# Open in browser
echo "   Report saved to: $REPORT_FILE"
if command -v open &> /dev/null; then
    open "$REPORT_FILE"
elif command -v xdg-open &> /dev/null; then
    xdg-open "$REPORT_FILE"
elif command -v start &> /dev/null; then
    start "$REPORT_FILE"
fi

# Exit code based on critical issues
if [ $CRITICAL_COUNT -eq 0 ]; then
    echo "✓ Code review completed - No critical issues found"
    exit 0
else
    echo "✗ Code review found $CRITICAL_COUNT critical issue(s)"
    exit 1
fi
