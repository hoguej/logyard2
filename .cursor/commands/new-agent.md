# /new-agent

Create a new agent workspace and register it in the queue system.

## Usage

Type `/new-agent` in Cursor chat, then provide:
- Agent name (e.g., `alpha`, `beta`, `gamma`)
- Optional context description explaining what this agent will work on

## What it does

1. Creates a unique timestamped workspace in `workspaces/agent_<name>_<timestamp>/`
2. Clones the logyard2 repository to that workspace
3. Creates a `.context.json` file with agent metadata
4. Registers the agent in the queue system
5. Read the agent-instructions command
6. Pull off the next piece of work and process it according to the agent-instructions
7. Workspaces can be used by agents that own them; however, when starting a new work item, be sure to 'checkout main' and 'git pull it'


## Example

```
/new-agent

Agent name: alpha
Context: Working on authentication features
```

This will create `workspaces/agent_alpha_20240101_120000/` and register the agent.

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/new-agent.sh <agent-name> [context-description]
```

The script is located at `${workspaceFolder}/scripts/new-agent.sh` and must be executed from the workspace root.
