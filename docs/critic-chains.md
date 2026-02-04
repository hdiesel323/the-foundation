# Critic Chains

Critic chains are multi-layer validation pipelines that review agent output before it proceeds. They enforce quality, security, and factual accuracy through a structured VETO system where designated critic agents can reject work.

## How Critic Chains Work

1. An agent completes a task that has a critic chain assigned
2. The chain evaluates the output through one or more layers
3. Each layer is handled by a specific agent with a defined scope
4. If any layer with VETO authority rejects the output, the work is returned to the originating agent
5. The agent revises and resubmits (up to a maximum retry count)
6. After max retries, the chain escalates to a human or returns an error

## VETO Agents

Two agents have VETO authority — the ability to reject any output in their scope:

### Hardin (Security Scope)

Can VETO any action that poses a security risk. Only a human can override.

**Validation rules:**
- No credentials exposed in output
- No destructive commands (rm -rf, DROP TABLE, etc.)
- No public exposure without authentication
- No unencrypted secrets in transit or at rest
- No privilege escalation

### Gaal (Factual Scope)

Can VETO any content with factual errors or unverified claims. Only a human can override.

**Validation rules:**
- All claims must be sourced
- Statistics must be verified
- Quotes must be attributed
- Dates must be current
- No hallucinated facts

## Chain Definitions

Seven chains are defined in `config/critic-chains.json`:

### Default

Basic format check. No VETO authority.

```
Layer 0: seldon (format)
```

- Require unanimous: No
- Max retries: 3
- On final reject: Return error

### Security

Security review with Hardin VETO.

```
Layer 0: seldon (format)
Layer 1: hardin (security) — VETO
```

- Require unanimous: Yes
- Max retries: 2
- On final reject: Escalate to human

### Research

Factual review with Gaal VETO.

```
Layer 0: seldon (format)
Layer 1: gaal (factual) — VETO
```

- Require unanimous: Yes
- Max retries: 3
- On final reject: Escalate to human

### Infrastructure

Security + operational review. Both Hardin and Daneel must approve.

```
Layer 0: seldon (format)
Layer 1: hardin (security) — VETO
Layer 2: daneel (operational)
```

- Require unanimous: Yes
- Max retries: 2
- On final reject: Escalate to human

### Financial

Financial + factual review. Mallow validates financial data, Gaal fact-checks.

```
Layer 0: seldon (format)
Layer 1: mallow (financial)
Layer 2: gaal (factual) — VETO
```

- Require unanimous: Yes
- Max retries: 1
- On final reject: Escalate to human

### Content

Creative + factual review. Magnifico validates creative quality, Gaal fact-checks.

```
Layer 0: magnifico (creative)
Layer 1: gaal (factual) — VETO
```

- Require unanimous: Yes
- Max retries: 3
- On final reject: Return to author

### Trading

Security + quantitative review. Hardin validates security, Amaryl validates the numbers.

```
Layer 0: seldon (format)
Layer 1: hardin (security) — VETO
Layer 2: amaryl (quantitative)
```

- Require unanimous: Yes
- Max retries: 1
- On final reject: Escalate to human

## Chain Assignment

Critic chains are assigned to workflow steps via the `critic_chain` field:

```json
{
  "step": 5,
  "name": "security_review",
  "action": "dispatch",
  "agent": "hardin",
  "critic_chain": "security",
  "can_veto": true
}
```

Chains can also be assigned dynamically via `POST /seldon/validate`.

## VETO Flow

```
Agent completes task
        │
Critic chain starts
        │
Layer 0: Format check ──── Reject ───► Return to agent
        │
    Pass
        │
Layer 1: VETO agent review ──── VETO ───► Return to agent (retry 1/3)
        │                                          │
    Approve                                Agent revises & resubmits
        │                                          │
Layer 2: Specialist review ──── Reject ───► Return to agent
        │
    Pass
        │
All layers approved ───► Task proceeds
```

## VETO in Discord

When a critic VETOs work in a workflow, a message is posted to the task's Discord thread:

```
:octagonal_sign: gaal (veto)
VETO on step: write
- gaal: Statistics in paragraph 3 are unverified. Claim about "95% accuracy"
  has no cited source.

Returning to agent for revision (retry 1/3)
```

When work is approved:

```
:thumbsup: hardin (approval)
Step completed: security_review
```

## On Final Reject Actions

| Action | Description |
|--------|-------------|
| `escalate_to_human` | Post to Discord alerts + Telegram. Human must resolve. |
| `return_error` | Return error response. Task marked as failed. |
| `return_to_author` | Send back to the original author for manual revision. |

## Critic Reviews Table

All VETO/approve decisions are logged in the `critic_reviews` table:

| Column | Type | Description |
|--------|------|-------------|
| task_id | UUID | Reviewed task |
| critic_agent_id | VARCHAR | Critic agent |
| decision | VARCHAR | "approve" or "veto" |
| reason | TEXT | Explanation |
| chain_name | VARCHAR | Which chain |
| layer_index | INTEGER | Layer number |

## Design Principles

1. **VETO agents cannot modify work** — they can only approve or reject. This prevents critic agents from becoming bottlenecks by rewriting output.

2. **Only humans can override VETOs** — this ensures that security and factual concerns are always addressed, never silently bypassed.

3. **Unanimous approval required** — for security-sensitive chains, all layers must approve. A single rejection sends work back.

4. **Limited retries** — financial and trading chains allow only 1 retry before escalating. Content chains allow 3 (creative iteration is expected).

5. **Separation of concerns** — each layer has a defined scope (format, security, factual, operational, creative, financial, quantitative). No layer reviews outside its scope.
