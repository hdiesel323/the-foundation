# Workflows

The Foundation includes a workflow engine that orchestrates multi-step processes across agents. Workflows define a sequence of steps with dependencies, parallel execution, critic chain validation, and human approval gates.

## How Workflows Work

1. A human submits a task via pre-flight (`POST /seldon/preflight`) with a `workflow_template`
2. Seldon creates a Discord thread and posts the plan for review
3. Human approves the pre-flight ("Go")
4. The workflow engine loads the template, initializes step tracking, and begins execution
5. Steps are dispatched to agents in dependency order — steps without unmet dependencies run in parallel
6. Gate steps pause the workflow until a human responds
7. Critic chain steps can VETO output and return work to the originating agent
8. When all steps complete, the workflow is marked done and a summary is posted

## Workflow Templates

Five templates are included. Each is defined in `config/workflows.json`.

### Feature Build

Full feature lifecycle from research to production deployment.

```
intake (seldon) ─► research (mis) ─► design (demerzel) ─► build (daneel)
                                                              │
                                              ┌───────────────┤
                                              ▼               ▼
                                     security_review    quality_review
                                       (hardin)           (gaal)
                                              │               │
                                              └───────┬───────┘
                                                      ▼
                                              human_merge (gate)
                                                      │
                                                      ▼
                                                deploy (daneel)
```

| Step | Agent | Description | Notes |
|------|-------|-------------|-------|
| intake | seldon | Pre-flight plan, wait for "Go" | Human approval gate |
| research | mis | Research patterns, competitors, prior art | Optional |
| design | demerzel | Architecture and approach | Infrastructure critic chain |
| build | daneel | Create branch, write code, open PR | Produces branch_name, pr_number |
| security_review | hardin | Vulnerability scan, credential audit | **Can VETO** |
| quality_review | gaal | Fact-check, verify claims | **Can VETO**, parallel with security |
| human_merge | seldon | Human reviews and merges PR | Human action gate |
| deploy | daneel | Docker build, health check, monitoring | Produces deploy_url |

### Content Publish

Content creation from research through publication.

```
intake ─► research (mis) ─► creative_brief (magnifico) ─► write (arkady)
              ─► fact_check (gaal) ─► human_approve (gate) ─► publish (arkady)
```

| Step | Agent | Description | Notes |
|------|-------|-------------|-------|
| intake | seldon | Pre-flight approval | Human gate |
| research | mis | SEO research, keyword targets | |
| creative_brief | magnifico | Tone, angle, visual style | |
| write | arkady | Write content per brief | |
| fact_check | gaal | Verify all claims and stats | **Can VETO** |
| human_approve | seldon | Human reviews final content | Human action gate |
| publish | arkady | Publish to target platform | |

### Sales Outreach

Lead research through outreach execution.

```
intake ─► lead_research (mis) ─► qualify (preem) ─► creative_messaging (magnifico)
              ─► human_approve (gate) ─► execute_outreach (preem)
```

| Step | Agent | Description | Notes |
|------|-------|-------------|-------|
| intake | seldon | Pre-flight approval | Human gate |
| lead_research | mis | Research targets, pain points | |
| qualify | preem | Score and prioritize leads | |
| creative_messaging | magnifico | Craft email sequences, LinkedIn messages | |
| human_approve | seldon | Human reviews messaging | Human action gate |
| execute_outreach | preem | Execute campaign, track responses | |

### Security Audit

Automated security review (no human approval required to start).

```
scan (hardin) ─► analyze (demerzel) ─► report (hardin) ─► notify (seldon)
```

| Step | Agent | Description |
|------|-------|-------------|
| scan | hardin | Vulnerability scans, credential audit |
| analyze | demerzel | Synthesize with threat intel |
| report | hardin | Generate findings and recommendations |
| notify | seldon | Post to Discord security channel + Telegram |

### Market Intel

Competitive analysis and market research (no human approval required).

```
scan (mis) ─┬─► quantify (amaryl) ──┬─► brief (seldon)
            └─► synthesize (demerzel)┘
```

| Step | Agent | Description | Notes |
|------|-------|-------------|-------|
| scan | mis | Competitors, social signals, trends | |
| quantify | amaryl | Market sizing, trend modeling | Parallel with synthesize |
| synthesize | demerzel | Strategic implications | Parallel with quantify |
| brief | seldon | Post intel brief to Discord | |

## Step Types

### dispatch

Dispatches a subtask to an agent. Creates a task record in the database linked to the workflow.

### gate

Pauses the workflow and notifies the human via Discord. The workflow resumes when the human responds with "done", "skip", or "fail" via `POST /seldon/workflow/:id/gate`.

### alert

Posts a notification to Discord channels and marks the step as complete immediately.

### preflight

The initial intake step. Handled before the workflow engine starts — marked as completed automatically when the pre-flight is approved.

## Step Dependencies

Steps declare dependencies via `depends_on` (array of step names). A step only executes when all its dependencies are completed or skipped.

Steps can run in parallel when they share the same dependencies. The `parallel_with` field documents this but is not enforced — parallelism is automatic based on dependency resolution.

## Critic Chains in Workflows

Steps can specify a `critic_chain` and `can_veto: true`. When a step's subtask completes, the critic chain validates the output:

1. If approved, the step is marked complete and the workflow advances
2. If vetoed, the work is returned to the agent for revision (up to 3 retries)
3. After max retries, the step fails and the workflow may escalate to human

See [Critic Chains](critic-chains.md) for the full validation pipeline.

## Gates

Two types of gates:

| Type | Description | Timeout |
|------|-------------|---------|
| `human_approval` | Approve, stop, or modify | 24 hours |
| `human_action` | Action required (e.g., merge PR) | 48 hours |

Gates notify via Discord and Telegram. A reminder is sent after 4 hours. If the timeout expires, the gate is re-escalated with increased priority.

## Workflow State

Workflow state is tracked both in-memory (for active execution) and in PostgreSQL (for persistence):

- `workflows` table stores the workflow record, steps, and status
- `tasks` table stores individual step subtasks
- Each step subtask has `metadata.workflow_id` and `metadata.workflow_step` linking it back

When a subtask completes (`POST /seldon/complete`), the workflow engine checks if it belongs to a workflow and advances accordingly.

## Pre-flight Format

The pre-flight plan posted to Discord follows this structure:

```
Intent:        One-line summary of what will be done
Plan:          Bullet list of steps
Verification:  How success will be verified
Risks:         What could go wrong
Agents:        Which agents will be involved
Workflow:      Which template will execute
```

The human responds with "Go" to approve, "Stop" to cancel, or "Modify: ..." to adjust the plan.

## Creating Custom Workflows

Add new templates to `config/workflows.json` following the existing structure:

```json
{
  "workflow_templates": {
    "my_workflow": {
      "name": "My Custom Workflow",
      "description": "Description of what this workflow does",
      "trigger": "When to use this workflow",
      "requires_approval": true,
      "steps": [
        {
          "step": 1,
          "name": "intake",
          "action": "preflight",
          "agent": "seldon",
          "gate": "human_approval"
        },
        {
          "step": 2,
          "name": "do_work",
          "action": "dispatch",
          "agent": "daneel",
          "description": "Execute the work",
          "depends_on": ["intake"]
        }
      ]
    }
  }
}
```

Each step must have a unique `name`, an `action` type, and an `agent`. Use `depends_on` to define execution order.
