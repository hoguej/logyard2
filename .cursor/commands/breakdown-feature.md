# /breakdown-feature

Break down a high-level feature description into workflow tasks and enqueue them for agents to work on.

## Usage

Type `/breakdown-feature` in Cursor chat, then provide:
- Feature title (e.g., "User Authentication", "Payment Processing")
- Feature description (high-level description of what needs to be built)

## What it does

Takes a high-level feature description and breaks it down into a repeatable workflow of 11 tasks:

1. **RESEARCH** (P4) - Research the requirements, existing codebase, and best practices
2. **CLARIFY** (P4) - Ask the user clarifying questions about the feature
3. **BREAKDOWN** (P3) - Break the feature into smaller, manageable subtasks
4. **DESIGN** (P3) - Design the coding work: identify files, architecture, data structures, APIs
5. **PLAN** (P3) - Create detailed implementation plan, sequence work, identify dependencies
6. **CODE** (P2) - Execute the coding work according to the plan
7. **TESTS** (P2) - Write comprehensive tests (unit, integration, edge cases)
8. **TEST** (P2) - Execute the test suite and verify all tests pass
9. **FIX** (P3) - Fix any failing tests (only if needed)
10. **META** (P4) - Create new tasks for bugs/issues found during implementation
11. **PR** (P2) - Commit code, push branch, and create pull request
12. **FEEDBACK** (P2) - Provide summary: what was done, how to test, other tasks created, PR link

## Task Priorities

- **P4 (High)**: Research, Clarify, Meta (bugs) - Need to be done early
- **P3 (Medium)**: Breakdown, Design, Plan, Fix - Important but can wait
- **P2 (Normal)**: Code, Tests, Test, PR, Feedback - Standard workflow tasks

## Example

```
/breakdown-feature

Feature title: User Authentication
Feature description: Add JWT-based authentication system with login, logout, password reset, and session management
```

This will create 11 tasks in the queue that agents can claim and work through.

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/breakdown-feature.sh <feature-title> <feature-description>
```

The script is located at `${workspaceFolder}/scripts/breakdown-feature.sh` and must be executed from the workspace root.

## Notes

- Tasks are created with dependencies implied by priority (higher priority tasks should be done first)
- The META task reminds agents to create new tasks for bugs/issues rather than fixing them inline
- Agents should follow the `/agent-instructions` workflow when executing these tasks
- Tasks can be claimed in order, but agents should check if prerequisites are met
