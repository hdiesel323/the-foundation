# Hardin — Decision Log

Agent ID: `hardin`

Significant decisions made by or involving hardin. Logged for traceability and cross-session context.

## Decision Log

| Date | Topic | Decision | Rationale | Alternatives Considered |
|------|-------|----------|-----------|------------------------|
| — | — | — | — | — |

## How to Log Decisions

Record any decision that:
- VETO or APPROVE of a deploy, config change, or access request
- Affects firewall rules, access control, or security policies
- Resolves a security incident (triage, containment, remediation)
- Changes scanning or monitoring thresholds
- Identifies and classifies a new threat or vulnerability

### Entry Format

```
| YYYY-MM-DD | topic-slug | What was decided | Why this choice was made | What else was considered |
```

### Example

```
| 2025-01-15 | deploy-veto | VETO daneel deploy of mcp-gateway v1.3.0 | Unpatched CVE-2025-1234 in dependency; risk of RCE | Approve with monitoring, approve with WAF rule |
| 2025-01-16 | fail2ban-config | Set maxretry=3, bantime=3600 | Balances security with legitimate retry scenarios | maxretry=5, permanent ban, progressive ban |
| 2025-01-17 | port-scan-finding | Flagged unexpected port 8443 open on VPS | Not in approved service manifest; potential misconfiguration | Ignore, monitor only, immediate block |
```

## Related Tables

- `audit_log` — full action audit trail (action_type, input_summary, output_summary, status)
- `facts` — persistent knowledge triples (subject-predicate-object)
- `preferences` — agent-specific settings (category/key/value)
