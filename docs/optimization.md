# Token Optimization

> **Result:** 97% cost reduction ($1,500+/mo to $30-50/mo)

The Foundation uses intelligent model routing to minimize API costs while maintaining quality where it matters. The default model is Claude Haiku 4.5 for all routine work, with automatic escalation to Claude Sonnet 4.5 only for tasks that require advanced reasoning.

## Model Routing Strategy

| Tier | Model | Cost/1M tokens | Use Case |
|------|-------|----------------|----------|
| **Default** | Claude Haiku 4.5 | $0.80 in / $4.00 out | All routine agent work |
| **Escalation** | Claude Sonnet 4.5 | $3.00 in / $15.00 out | Architecture, security, complex reasoning |
| **Overflow** | Grok (2M context) | $0.20 in / $0.50 out | Documents exceeding 200K tokens |
| **Swarm** | DeepSeek v3/R1 | $0.28 in / $0.42 out | Batch pre-processing |
| **Heartbeat** | Ollama llama3.2:3b | $0 (local) | Status checks, simple queries |
| **Fallback** | Free models via OpenRouter | $0 | When rate-limited |

### When Haiku Escalates to Sonnet

Sonnet is used only for:

- Architecture decisions
- Production code review
- Security analysis (Hardin always uses Sonnet)
- Complex debugging/reasoning
- Strategic multi-project decisions
- Factual verification (Gaal always uses Sonnet)

**Rule:** When in doubt, try Haiku first.

### Agent Model Assignments

| Agent | Default Tier | Notes |
|-------|-------------|-------|
| Seldon | Haiku | Escalates to Sonnet for architecture/strategy |
| Daneel | Haiku | Escalates to Sonnet for code review/debugging |
| **Hardin** | **Sonnet** | Always Sonnet (security VETO requires top reasoning) |
| **Gaal** | **Sonnet** | Always Sonnet (factual VETO requires top reasoning) |
| Demerzel | Haiku | Escalates for strategy; overflows to Grok for 2M context |
| Mis | Haiku | Overflows to Grok Reasoning for large documents |
| Trader | Haiku | Escalates for complex financial decisions |
| All others | Haiku | Standard routing |

### Fallback Chain

```
Haiku -> Sonnet -> Free (Gemini/Llama via OpenRouter) -> OpenRouter auto
```

## Prompt Caching

Stable files are cached to reduce token costs on repeated reads:

**Cached (stable, rarely change):**
- SOUL.md
- USER.md
- TOOLS.md
- REFERENCE.md

**Never cached (change frequently):**
- MEMORY.md
- memory/*.md (daily notes)
- DECISIONS.md

Cache TTL: 5 minutes. Sonnet responses are always cached.

## Session Initialization

Each session loads only the minimum required context:

### Eager Load (every session)
1. `SOUL.md` — agent identity
2. `USER.md` — user preferences
3. `IDENTITY.md` — core identity

### Conditional Load
4. `memory/YYYY-MM-DD.md` — today's daily notes (if exists)

### Never Auto-Load
- MEMORY.md (full memory file)
- Session history
- Prior messages
- Previous tool outputs

### On-Demand Context
When an agent needs prior context, it uses `memory_search()` to find the relevant snippet, never loads the whole file.

### End of Session
Write to `memory/YYYY-MM-DD.md`:
- What was worked on
- Decisions made
- Leads generated
- Blockers
- Next steps

## Heartbeat Configuration

Agent heartbeats use a free local model instead of API calls:

```json
{
  "every": "1h",
  "model": "ollama/llama3.2:3b",
  "session": "main",
  "target": "slack",
  "prompt": "Check: Any blockers, opportunities, or progress updates needed?"
}
```

### Ollama Setup

```bash
# Install
curl -fsSL https://ollama.ai/install.sh | sh

# Pull the heartbeat model
ollama pull llama3.2:3b

# Start service
ollama serve

# Test
ollama run llama3.2:3b "respond with OK"
```

Heartbeat cost: $0/mo (was $5-15/mo with API calls).

## Rate Limits

| Limit | Value |
|-------|-------|
| Minimum between API calls | 5 seconds |
| Minimum between web searches | 10 seconds |
| Max searches per batch | 5, then 2-minute cooldown |
| On 429 error | Stop, wait 5 minutes, retry |
| Daily budget | $5 (warning at 75%) |
| Monthly budget | $200 (warning at 75%) |

**Batching rule:** One request for 10 leads, not 10 requests for 1 lead each.

## Cost Comparison

| Optimization | Before | After |
|--------------|--------|-------|
| Session initialization | $0.40/session | $0.05/session |
| Model routing (per 1K tokens) | $0.003 | $0.00025 |
| Heartbeat | $5-15/mo | $0/mo |
| **Daily total** | $2-3 | $0.10 |
| **Monthly total** | $70-90 | $3-5 |

With 14 agents running, the platform-wide savings are:

| Metric | Sonnet-Only | Optimized |
|--------|------------|-----------|
| Monthly cost (14 agents) | $1,500+ | $30-50 |
| Cost per agent per day | $3.50 | $0.10 |
| Heartbeat cost | $15/mo | $0/mo |

## Workspace File Structure

```
/workspace/
+-- SOUL.md            # Cached (stable)
+-- USER.md            # Cached (stable)
+-- TOOLS.md           # Cached (stable)
+-- memory/
|   +-- MEMORY.md      # Not cached (updates frequently)
|   +-- YYYY-MM-DD.md  # Not cached (daily notes)
+-- projects/
    +-- [PROJECT]/
        +-- REFERENCE.md   # Cached (stable docs)
```

## Verification

After applying optimizations, verify the configuration:

```bash
# Check model assignments
grep '"modelTier"' config/agents.json | sort | uniq -c

# Expected:
#  12 "modelTier": "haiku",
#   2 "modelTier": "claude",

# Check default model
grep '"model":' config/agents.json | head -1
# Expected: "model": "anthropic/claude-haiku-4-5"
```

## Configuration Reference

All optimization settings live in `config/agents.json` under `defaults`:

- `modelRouting` — Haiku/Sonnet escalation rules
- `cache` — Prompt caching settings
- `sessionInit` — Session initialization rules
- `rateLimits` — API call and budget limits
- `heartbeat` — Local heartbeat configuration
- `modelFallbackChain` — Fallback sequence
