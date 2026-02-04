# Self-Improving Agent Skill

## Purpose
Captures learnings from agent operations, detects errors and patterns,
extracts reusable skills, and promotes insights to project-level knowledge.

## Learning Log Format

Each learning entry follows this structure:

```yaml
- id: LEARN-{YYYYMMDD}-{NNN}
  category: error_recovery | optimization | pattern_discovery | workflow_improvement | tool_usage
  priority: critical | high | medium | low
  area: infrastructure | commerce | intelligence | operations | command | cross-cutting
  summary: "One-line description of the learning"
  detail: "Full explanation of what was learned"
  source:
    agent: "{agent_id}"
    trigger: "What event triggered this learning"
    timestamp: "{ISO-8601}"
  suggested_action:
    type: promote_to_claude_md | promote_to_agents_md | create_skill | update_config | no_action
    target: "File or system to update"
    content: "Suggested content to add/change"
  status: captured | reviewed | promoted | dismissed
```

## Trigger Events

1. **Command failure** — Any non-zero exit code triggers error-detector.sh
2. **Pattern repetition** — Same error/fix pattern seen 3+ times
3. **Performance anomaly** — Response time 2x above baseline
4. **New tool usage** — First use of an MCP tool or command pattern
5. **Successful workaround** — Agent finds alternative approach after failure

## Promotion Pipeline

```
Capture → Review → Classify → Promote
                                ├── CLAUDE.md (project-wide facts)
                                ├── AGENTS.md (workflow updates)
                                ├── config/*.json (configuration)
                                └── skills/ (new reusable skill)
```

## File Locations

- `.learnings/LEARNINGS.md` — Active learning log
- `.learnings/archive/` — Promoted/dismissed learnings
- `scripts/error-detector.sh` — Error capture trigger
- `scripts/extract-skill.sh` — Skill extraction utility
