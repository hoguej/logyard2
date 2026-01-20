# /agent-instructions

Instructions for agents on how to work in the logyard2 system.

## Usage

Type `/agent-instructions` in Cursor chat to view the agent workflow instructions.

## Agent Workflow

Follow these steps when working as an agent:

### 1. Workspace Setup
- Agents should have a dedicated workspace they work with
- The workspace is created using `/new-agent` command
- Each agent has a unique workspace path stored in the queue system

### 2. Pull Work from Queue
- After workspace is set up, pull a piece of work to do
- Use `/agent-queue claim <agent-name>` to claim the next available task
- Or claim a specific task: `/agent-queue claim <agent-name> <task-title>`

### 3. Read Task Context
- **Read `.task-context.md`** in your workspace - this file contains all the details about your current task
- The task context file includes: task description, context, instructions, and completion steps
- This file is created automatically when a task is claimed
- All task information is stored here, not passed via command line

### 4. Review Relevant Commands
- Scan the `.cursor/commands/` directory to see if there are any instructions you need to get up to speed on
- For example, if you're doing a requirements-research task, read the `requirements-research` command file
- Review any command files that relate to your current task
- This helps you understand the expected workflow and standards

### 5. Execute Work in Workspace
- All work should be executed within your assigned workspace
- Navigate to your workspace: `cd workspaces/agent_<name>_<timestamp>/`
- Make all code changes, file edits, and modifications within this workspace only

### 6. Stay Within Workspace Boundaries
- **CRITICAL**: The agent should NOT make any changes outside the workspace
- Do not modify files in the main project root (except through your workspace)
- All changes must be contained within your workspace directory

### 7. Commit Your Work
- After completing the work, commit the code with a good commit message
- Format: `[<agent-name>] <descriptive-message>`
- Example: `[alpha] Add authentication middleware with JWT support`
- Use `/cleanup-junk` before committing to remove any AI-generated junk files

### 8. Push Feature Branch
- Push your feature branch to the remote repository
- Use: `git push origin <branch-name>` or `git push -u origin <branch-name>`

### 9. Create Pull Request
- After pushing, create a PR using the context from `.context.json`
- Use `/commit-and-pr` command or create PR manually with GitHub CLI
- Include relevant context and description in the PR

### 10. Checkout Main and Get Next Task
- After creating the PR, checkout main branch: `git checkout main`
- Pull latest changes: `git pull origin main`
- Grab another task from the queue: `/agent-queue claim <agent-name>`
- Repeat the workflow from step 3

### 11. No More Tasks
- If there are no more tasks available in the queue:
  - Return to the user for more input
  - Report your status: `/agent-queue status <agent-name>`
  - Wait for new tasks to be added or for user instructions

### 12. Need More Information
- If at any time you need more data, context, or clarification:
  - **Ask the user for more data**
  - Do not proceed with assumptions
  - Use `/agent-queue heartbeat <agent-name> "Waiting for user input"` to update your status

## Best Practices

- **Always identify yourself**: Use your agent name in commits and messages
- **Update heartbeat regularly**: Use `/agent-queue heartbeat <agent-name> <activity>` to show you're active
- **Complete tasks properly**: Use `/agent-queue complete <agent-name> <result>` when done
- **Release if stuck**: Use `/agent-queue release <agent-name> <reason>` if you can't complete a task
- **Check queue status**: Use `/queue-status` to see overall progress and available work

## Example Workflow

```
1. Agent "alpha" is created: /new-agent alpha "Working on auth features"
2. Task is automatically claimed and .task-context.md is created
3. Read .task-context.md for full task details
4. Review commands: Look at the .cursor/commands/ directory to see which commands might be relevant to this task, and read those commands
5. Work in workspace: eg, 'cd workspaces/agent_alpha_20240101_120000/'. Never create files outside of the workspace.
6. Make changes, test, commit: git commit -m "[alpha] Add JWT authentication"
7. Push branch: git push origin feature/jwt-auth
8. Create PR: /commit-and-pr workspace_20240101_120000
9. Update the queue calling that task 'done' (handled by commit-and-pr script)
10. Tell the user what you did, and provide a link to the pr.
11. Checkout main: git checkout main && git pull (handled by commit-and-pr script)
12. Claim next task: /agent-queue claim alpha
13. If no tasks: Report to user and wait
```

## Execution

This is an informational command. When invoked, display these instructions to help guide agent behavior.
