#!/bin/bash

# Script to clean up junk files created by AI before committing
# Usage: ./cleanup-junk.sh [workspace-path]

set -e

WORKSPACE_PATH="${1:-.}"
JUNK_DIR="${WORKSPACE_PATH}/junk"

# Create junk directory if it doesn't exist
mkdir -p "$JUNK_DIR"

echo "Cleaning up junk files in: $WORKSPACE_PATH"
echo ""

FOUND_FILES=0

# Function to move a file and count it
move_file() {
    local file="$1"
    local rel_path="$2"
    
    if [ -f "$file" ]; then
        echo "Moving junk file: $rel_path"
        mv "$file" "$JUNK_DIR/" 2>/dev/null || true
        FOUND_FILES=$((FOUND_FILES + 1))
    fi
}

# Find and move junk markdown files in root directory (excluding important ones)
while IFS= read -r -d '' file; do
    REL_PATH=$(realpath --relative-to="$WORKSPACE_PATH" "$file" 2>/dev/null || echo "$file")
    DIR_NAME=$(dirname "$REL_PATH")
    
    # Only move markdown files in root directory
    if [ "$DIR_NAME" = "." ]; then
        FILENAME=$(basename "$file")
        # Skip important files
        case "$FILENAME" in
            README.md|CHANGELOG.md|LICENSE.md|CONTRIBUTING.md|.gitignore|.cursorrules)
                continue
                ;;
        esac
        move_file "$file" "$REL_PATH"
    fi
done < <(find "$WORKSPACE_PATH" -maxdepth 1 -type f -name "*.md" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/junk/*" \
    -print0 2>/dev/null || true)

# Look for common AI-generated file names (case-insensitive)
AI_GENERATED_NAMES=(
    "explanation.md"
    "notes.md"
    "summary.md"
    "changes.md"
    "what_i_did.md"
    "implementation_notes.md"
    "code_explanation.md"
    "implementation.md"
    "overview.md"
    "details.md"
)

for name in "${AI_GENERATED_NAMES[@]}"; do
    while IFS= read -r -d '' file; do
        REL_PATH=$(realpath --relative-to="$WORKSPACE_PATH" "$file" 2>/dev/null || echo "$file")
        move_file "$file" "$REL_PATH"
    done < <(find "$WORKSPACE_PATH" -maxdepth 3 -type f \
        -iname "$name" \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/junk/*" \
        ! -path "*/docs/*" \
        ! -path "*/.cursor/commands/*" \
        -print0 2>/dev/null || true)
done

# Find files with AI-generated patterns in their names
AI_PATTERNS=(
    "*_explanation.*"
    "*_notes.*"
    "*_summary.*"
    "*_changes.*"
    "*explanation*"
    "*notes*"
    "*summary*"
)

for pattern in "${AI_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        REL_PATH=$(realpath --relative-to="$WORKSPACE_PATH" "$file" 2>/dev/null || echo "$file")
        # Skip if in important directories
        if [[ "$REL_PATH" == docs/* ]] || [[ "$REL_PATH" == .cursor/* ]]; then
            continue
        fi
        move_file "$file" "$REL_PATH"
    done < <(find "$WORKSPACE_PATH" -maxdepth 3 -type f \
        -iname "$pattern" \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/junk/*" \
        ! -path "*/docs/*" \
        ! -path "*/.cursor/commands/*" \
        -print0 2>/dev/null || true)
done

# Find temporary files
TEMP_PATTERNS=(
    "*.tmp"
    "*.temp"
    "*.bak"
    "*.backup"
    "*~"
    "*.swp"
)

for pattern in "${TEMP_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        REL_PATH=$(realpath --relative-to="$WORKSPACE_PATH" "$file" 2>/dev/null || echo "$file")
        move_file "$file" "$REL_PATH"
    done < <(find "$WORKSPACE_PATH" -maxdepth 3 -type f \
        -name "$pattern" \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/junk/*" \
        -print0 2>/dev/null || true)
done

if [ $FOUND_FILES -eq 0 ]; then
    echo "✓ No junk files found"
else
    echo ""
    echo "✓ Moved $FOUND_FILES junk file(s) to $JUNK_DIR/"
fi
