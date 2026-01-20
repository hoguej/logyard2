# Create Work

Enqueues a high-level requirement to the requirements-research queue, starting the automated workflow.

## Usage

```
/create-work <high-level-description>
```

## Description

Takes a high-level requirement description from a human and enqueues it to the `requirements-research` queue. This is the entry point for the automated agent workflow.

## Workflow

After enqueuing to requirements-research, the workflow automatically progresses:

1. **Requirements Research** → Researches the requirement, then automatically queues to Planning
2. **Planning** → Breaks down into tasks, creates execution tasks
3. **Execution** → Creates workspace, implements code, queues to Pre-Commit Check
4. **Pre-Commit Check** → Uses existing workspace, validates code, queues to Commit-Build
5. **Commit-Build** → Uses existing workspace, commits, creates PR, monitors build, queues to Deploy
6. **Deploy** → Merges PR, monitors deployment, destroys workspace on success

## Examples

```
/create-work Add user authentication with OAuth2 support
/create-work Implement real-time chat feature using WebSockets
/create-work Create dashboard for monitoring system metrics
```

## Implementation

This command should:
1. Accept high-level requirement description
2. Create a task in the `requirements-research` queue
3. Set appropriate priority (default: 3)
4. Announce work creation via `announce` queue
5. Return task ID and status

## Notes

- All agents can announce their work via the `announce` queue
- E2E tests can be run in parallel by any step, or via the dedicated e2e-test queue
- Workspace lifecycle: Created in Execution (step 3), used by Pre-Commit Check and Commit-Build (steps 4-5), destroyed by Deploy (step 6) on success
