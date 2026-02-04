# API Reference

The Seldon Protocol API is the central interface for The Foundation. All agent coordination, task management, and workflow execution goes through this API.

**Base URL:** `http://localhost:18789`

---

## Health & Status

### GET /health

Health check endpoint.

**Response:**

```json
{ "status": "ok", "service": "seldon-protocol" }
```

### GET /seldon/status

System status including agent count, active tasks, and service health.

### GET /dashboard

Dashboard metadata.

---

## Agent Management

### POST /seldon/register

Register a new agent or update an existing registration.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Unique agent identifier |
| `name` | string | yes | Display name |
| `role` | string | yes | Agent role (e.g., "Orchestrator") |
| `capabilities` | string[] | no | List of capabilities |
| `endpoint` | string | no | Agent's callback URL |
| `location` | string | no | Where the agent runs |
| `status` | string | no | Initial status (default: "online") |
| `metadata` | object | no | Additional metadata |

**Response:**

```json
{
  "registered": true,
  "session_token": "sel_a1b2c3d4...",
  "heartbeat_interval": 300
}
```

Uses `ON CONFLICT DO UPDATE` — calling register for an existing agent updates its record.

### POST /seldon/heartbeat

Agent heartbeat to report status and metrics.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Agent identifier |
| `session_token` | string | no | Session token from registration |
| `status` | string | no | Current status |
| `current_task` | string | no | Task currently being worked on |
| `metrics` | object | no | Performance metrics |

**Response:**

```json
{
  "acknowledged": true,
  "agent_id": "daneel",
  "status": "online",
  "last_heartbeat": "2026-02-03T12:00:00Z"
}
```

### GET /seldon/agents

List all registered agents.

**Response:**

```json
{
  "agents": [
    {
      "id": "seldon",
      "name": "Seldon",
      "role": "Orchestrator",
      "location": "mac-mini",
      "status": "online",
      "capabilities": ["route", "coordinate", "delegate"],
      "last_heartbeat": "2026-02-03T12:00:00Z",
      "registered_at": "2026-02-01T00:00:00Z"
    }
  ],
  "count": 14
}
```

---

## Task Dispatch

### POST /seldon/dispatch

Dispatch a task to a specific agent or the best available agent.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task` | string | yes | Task name/description |
| `priority` | string\|number | no | "critical" (1), "high" (2), "medium" (5), "low" (8), or integer |
| `preferred_agent` | string | no | Agent to assign to |
| `fallback_agents` | string[] | no | Fallback agents if preferred is unavailable |
| `timeout` | number | no | Task timeout in ms |
| `callback` | string | no | Callback URL for completion |
| `acceptance_criteria` | object | no | Criteria the result must meet |

**Acceptance criteria fields:**

| Field | Type | Description |
|-------|------|-------------|
| `required_outputs` | string[] | Strings that must appear in the result |
| `format` | string | Expected result type |
| `min_sources` | number | Minimum number of sources required |
| `confidence_threshold` | number | Minimum confidence score |
| `validators` | string[] | Custom validator names |

**Response:**

```json
{
  "dispatched": true,
  "task_id": "uuid",
  "assigned_agent": "daneel",
  "priority": 5,
  "status": "pending",
  "created_at": "2026-02-03T12:00:00Z",
  "has_acceptance_criteria": false,
  "discord_thread_id": "123456789",
  "discord_message_url": "https://discord.com/channels/..."
}
```

If a Discord bot is configured, a linked thread is automatically created in the appropriate channel.

### GET /seldon/tasks

List all tasks.

**Response:**

```json
{
  "tasks": [...],
  "count": 42
}
```

### GET /seldon/task/:taskId

Get task details including Discord thread messages.

### POST /seldon/task/:taskId/archive

Manually archive a completed task (normally happens automatically after 36 hours).

### POST /seldon/complete

Mark a task as complete with result validation.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task_id` | string | yes | Task UUID |
| `agent_id` | string | yes | Agent completing the task |
| `result` | object | no | Task result (validated against acceptance criteria) |

**Response (success):**

```json
{
  "completed": true,
  "task_id": "uuid",
  "agent_id": "daneel",
  "violations": [],
  "completion_summary": "Task completed by daneel",
  "archival_scheduled": true
}
```

**Response (acceptance criteria failed):**

```json
{
  "completed": false,
  "task_id": "uuid",
  "violations": ["missing_required_output: deployment_url", "low_confidence: 0.6 < 0.8"],
  "message": "Task result did not meet acceptance criteria"
}
```

If the task is part of a workflow, completing it advances the workflow to the next step.

---

## Pre-flight Approval

### POST /seldon/preflight

Create a pre-flight approval request. The task is created in `awaiting_approval` status and a Discord thread is created with the plan for human review.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task` | string | yes | Task name |
| `intent` | string | yes | One-line summary of what will be done |
| `plan` | string[] | no | Step-by-step plan |
| `verification` | string | no | How success will be measured |
| `risks` | string[] | no | What could go wrong |
| `workflow_template` | string | no | Workflow template to execute on approval |
| `priority` | string\|number | no | Task priority |
| `estimated_agents` | string[] | no | Which agents will be involved |
| `critic_chains` | string[] | no | Which validation chains apply |

**Response:**

```json
{
  "preflight_id": "uuid",
  "status": "awaiting_approval",
  "task": "Write a blog post",
  "intent": "Create SEO-optimized content",
  "discord_thread_id": "123456789",
  "discord_message_url": "https://discord.com/channels/...",
  "next_action": "Reply \"Go\" in Discord thread or call POST /seldon/preflight/:id/approve"
}
```

### POST /seldon/preflight/:taskId/approve

Approve, modify, or cancel a pre-flight request.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | no | "go" (default), "stop", or "modify" |
| `modifications` | string\|object | no | Plan modifications (when action is "modify") |

**Response (approved with workflow):**

```json
{
  "task_id": "uuid",
  "status": "approved",
  "workflow_template": "content_publish",
  "workflow_id": "wf-uuid",
  "workflow_steps": 7,
  "executing": true,
  "next": "Workflow 'content_publish' executing — 7 steps"
}
```

---

## Workflow Orchestration

### GET /seldon/workflows

List active workflows (limit 50).

### GET /seldon/workflow/:workflowId

Get workflow status and step progress.

### POST /seldon/workflow/:workflowId/gate

Resolve a human gate in a workflow.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string | yes | "done", "skip", or "fail" |

---

## Agent Coordination

### POST /seldon/handoff

Transfer a task between agents.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `from_agent` | string | yes | Source agent |
| `to_agent` | string | yes | Target agent |
| `context` | object | yes | Handoff context and instructions |
| `require_response` | boolean | no | Whether to wait for target agent response |

**Response:**

```json
{
  "handoff_id": "uuid",
  "from_agent": "arkady",
  "to_agent": "gaal",
  "status": "pending",
  "require_response": false,
  "created_at": "2026-02-03T12:00:00Z"
}
```

### GET /seldon/handoffs/:agentId

Get pending handoffs for an agent.

**Query parameters:**

| Param | Default | Description |
|-------|---------|-------------|
| `status` | "pending" | Filter by handoff status |

### POST /seldon/broadcast

Send a fleet-wide announcement to all agents.

### POST /seldon/spawn

Spawn parallel subagents for concurrent work. Up to 5 concurrent subagents. Eligible agents: gaal, arkady, mis, amaryl, demerzel.

### POST /seldon/validate

Run critic chain validation on a task result. See [Critic Chains](critic-chains.md) for details on the validation pipeline.

---

## Metadata

### GET /seldon/divisions

Returns the division structure with agent assignments.

---

## Error Responses

All endpoints return errors in this format:

```json
{
  "error": "Description of what went wrong"
}
```

Common HTTP status codes:

| Code | Meaning |
|------|---------|
| 400 | Missing required fields |
| 404 | Agent or task not found |
| 500 | Internal server error |

## Priority Mapping

Priority can be specified as a string or integer:

| String | Integer | Label |
|--------|---------|-------|
| critical | 1 | P0-CRITICAL |
| high | 2 | P1-HIGH |
| medium | 5 | P2-MEDIUM |
| low | 8 | P3-LOW |
