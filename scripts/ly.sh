#!/bin/bash
# /ly: List all available ly-* commands
# Usage: ./scripts/ly.sh

echo "Available ly-* commands:"
echo ""
echo "  /ly-next [branch-name] [commit-message]"
echo "    Complete workflow:"
echo "    - Ensures feature branch from main"
echo "    - Commits current changes"
echo "    - Runs comprehensive code review"
echo "    - Fixes any findings"
echo "    - Pushes to GitHub"
echo "    - Creates PR"
echo "    - Merges PR"
echo "    - Checks out main"
echo ""
echo "  /ly"
echo "    Lists all available ly-* commands (this command)"
echo ""
