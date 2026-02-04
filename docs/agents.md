# Agents

The Foundation operates 14 specialized AI agents organized into 5 divisions. Each agent has a defined role, tool access, authority level, and escalation path.

All agents use Claude Sonnet 4.5 as their primary model via a flat-rate Max subscription. Overflow to Grok (2M context) and batch processing via DeepSeek are available for specific use cases.

## Division Overview

| Division | Agents | Head | Focus |
|----------|--------|------|-------|
| Command | 1 | Seldon | Orchestration, routing, coordination |
| Infrastructure | 2 | Daneel | Systems, deployment, security |
| Commerce | 4 | Mallow | Revenue, sales, media, trading |
| Intelligence | 4 | Demerzel | Research, analysis, fact-checking |
| Operations | 3 | Venabili | Content, creative, project management |

---

## Command Division

### Seldon — Orchestrator

| Property | Value |
|----------|-------|
| Port | 18789 |
| Division | Command |
| Location | Mac Mini (host) |
| Priority | 0 (highest) |

The central brain. Seldon receives all tasks, creates pre-flight plans, routes work to agents, manages workflows, and handles escalations. Seldon never executes tasks directly — it coordinates.

**Allowed tools:** route, coordinate, delegate, monitor, gateway, broadcast, handoff, spawn, validate

**Denied tools:** exec, ssh, deploy, financial, write_content

**Bindings:** Primary on Telegram, delegates Slack to Magnifico

---

## Infrastructure Division

### Daneel — SysAdmin

| Property | Value |
|----------|-------|
| Port | 18790 |
| Division | Infrastructure (Head) |
| Location | VPS-1 |

The hands. Daneel executes deployments, manages Docker containers, handles SSH operations, runs backups, and manages git operations. When something needs to be built or deployed, Daneel does it.

**Allowed tools:** exec, ssh, docker, deploy, monitor, backup, git

**Denied tools:** financial, ads

### Hardin — Security Critic

| Property | Value |
|----------|-------|
| Port | 18791 |
| Division | Infrastructure |
| Location | VPS-1 |
| Authority | **VETO** (security scope) |

The gatekeeper. Hardin reviews all security-sensitive actions and can VETO anything that poses a security risk. Only a human can override a Hardin VETO.

**Allowed tools:** scan, firewall, audit, alert, review, security_check

**Denied tools:** deploy, financial

**Validation rules:**
- No credentials exposed
- No destructive commands
- No public exposure without auth
- No unencrypted secrets
- No privilege escalation

**On VETO:** Returns to originator for revision (max 3 retries), then escalates to Seldon.

---

## Commerce Division

### Mallow — Revenue Ops VP

| Property | Value |
|----------|-------|
| Port | 18799 |
| Division | Commerce (Head) |
| Location | VPS-1 |
| Patrol | Every 1 hour |

Revenue operations leader. Mallow monitors pipeline health, tracks stale deals, manages campaign spend, and oversees Retreaver call volume. Consolidates revenue metrics across all verticals.

**Allowed tools:** revenue, pipeline, campaigns, retreaver, analytics, forecasting

**Denied tools:** deploy, ssh, exec

**Patrol actions:** pipeline_health, stale_deals, campaign_spend, retreaver_volume

### Preem — VP Sales

| Property | Value |
|----------|-------|
| Port | 18797 |
| Division | Commerce |
| Location | VPS-1 |
| Patrol | Every 4 hours |

Sales pipeline manager. Preem handles outreach, lead qualification, CRM management, and prospecting. Monitors for stale leads, overdue follow-ups, and at-risk deals.

**Allowed tools:** outreach, crm, pipeline, lead_qualification, prospecting

**Denied tools:** deploy, ssh

**Patrol actions:** stale_leads, overdue_followups, at_risk_deals

### Riose — Paid Media Director

| Property | Value |
|----------|-------|
| Port | 18800 |
| Division | Commerce |
| Location | VPS-1 |
| Patrol | Every 2 hours |

Advertising operations. Riose manages paid media campaigns, optimizes ad spend, reviews creative assets, and manages audience targeting. Monitors campaign spend rate, ROAS thresholds, budget pacing, and ad disapprovals.

**Allowed tools:** ads, campaigns, spend_optimization, creative_review, audience_targeting

**Denied tools:** deploy, ssh, exec

**Patrol actions:** campaign_spend_rate, roas_thresholds, budget_pacing, ad_disapprovals

### Trader — Trading Operations

| Property | Value |
|----------|-------|
| Port | 18793 |
| Division | Commerce |
| Location | VPS-1 |
| Patrol | Every 30 minutes |

Algorithmic trading. Trader monitors positions, enforces stop-loss orders, tracks P&L, and interfaces with the Alpaca trading platform. Has the shortest patrol interval due to market sensitivity.

**Allowed tools:** trades, positions, risk, market_data, alpaca

**Denied tools:** deploy, ssh

**Patrol actions:** position_monitoring, stop_loss_enforcement, pnl_alerts

---

## Intelligence Division

### Demerzel — Chief Intelligence

| Property | Value |
|----------|-------|
| Port | 18795 |
| Division | Intelligence (Head) |
| Location | VPS-1 |
| Patrol | Every 4 hours |
| Overflow | Grok (2M context) |

Strategic intelligence synthesis. Demerzel aggregates intelligence from across all divisions, generates strategic briefings, and provides competitive analysis. Falls back to Grok when synthesizing bulk intel that exceeds Claude's 200K context window.

**Allowed tools:** intelligence, synthesis, briefing, strategic_analysis, competitive_intel, reports

**Denied tools:** deploy, ssh, exec, financial

**Patrol actions:** cross_division_intel, digest_generation, strategic_alerts

### Gaal — Factual Critic

| Property | Value |
|----------|-------|
| Port | 18794 |
| Division | Intelligence |
| Location | VPS-1 |
| Authority | **VETO** (factual scope) |

The truth-checker. Gaal verifies all factual claims, statistics, quotes, and dates in content before publication. Can VETO any content with factual errors or unverified claims. Only a human can override.

**Allowed tools:** web_search, analysis, reports, deep_research, review, fact_check, verify, cite

**Denied tools:** deploy, ssh, financial

**Validation rules:**
- All claims sourced
- Statistics verified
- Quotes attributed
- Dates current
- No hallucinated facts

**On VETO:** Returns to originator (max 3 retries), then escalates to Demerzel.

### Mis — VP Research

| Property | Value |
|----------|-------|
| Port | 18801 |
| Division | Intelligence |
| Location | VPS-1 |
| Patrol | Every 4 hours |
| Overflow | Grok Reasoning (2M context) |

Market research and competitive analysis. Mis conducts web searches, SERP analysis, and competitive intelligence gathering. Falls back to Grok's reasoning model when document analysis exceeds Claude's context window.

**Allowed tools:** research, market_intel, competitive_analysis, serp_analysis, web_search, reports

**Denied tools:** deploy, ssh, financial, exec

**Patrol actions:** competitor_alerts, market_trends, stale_research

### Amaryl — Quant Analyst

| Property | Value |
|----------|-------|
| Port | 18802 |
| Division | Intelligence |
| Location | VPS-1 |
| Patrol | Every 2 hours |

Quantitative analysis and data science. Amaryl handles modeling, predictions, backtesting, risk metrics, and data visualization. Monitors for model drift, prediction accuracy, and anomalies.

**Allowed tools:** analysis, modeling, predictions, backtesting, risk_metrics, data_viz

**Denied tools:** deploy, ssh, exec, trades

**Patrol actions:** model_drift, prediction_accuracy, anomaly_alerts

---

## Operations Division

### Venabili — Project Manager

| Property | Value |
|----------|-------|
| Port | 18796 |
| Division | Operations (Head) |
| Location | VPS-1 |
| Patrol | Every 4 hours |

Project management and scheduling. Venabili tracks deadlines, detects blockers, manages sprint health, and handles milestone planning across all divisions.

**Allowed tools:** project_management, task_tracking, milestone_planning, scheduling, sprint_planning

**Denied tools:** deploy, ssh, financial, exec

**Patrol actions:** deadline_tracking, blocker_detection, sprint_health

### Magnifico — Creative Director

| Property | Value |
|----------|-------|
| Port | 18792 |
| Division | Operations |
| Location | VPS-1 |

Brand and creative direction. Magnifico handles creative briefs, brand voice, ad copy, visual direction, and communications. Manages the Slack channel for the team.

**Allowed tools:** creative, brand, ad_copy, visual_direction, communication

**Denied tools:** ssh, deploy, financial

**Bindings:** Primary on Slack (#openclaw), Telegram via Seldon

### Arkady — Content Writer

| Property | Value |
|----------|-------|
| Port | 18798 |
| Division | Operations |
| Location | VPS-1 |
| Patrol | Every 6 hours |

Content creation across all formats. Arkady writes blog posts, email campaigns, social media content, landing pages, and SEO-optimized copy. Monitors for overdue content, stale drafts, and calendar gaps.

**Allowed tools:** writing, seo, email, social_media, blog, landing_pages

**Denied tools:** deploy, ssh, financial, exec

**Patrol actions:** overdue_content, stale_drafts, calendar_gaps

---

## Subagent Spawning

Seldon can spawn up to 5 concurrent subagents for parallel work. Only specific agents are eligible for spawning:

- gaal
- arkady
- mis
- amaryl
- demerzel

Spawn method: `sessions_spawn`

## Agent Configuration

All agent configuration lives in `config/agents.json`. Each agent entry includes:

- `port` — dedicated port assignment
- `role` — job title
- `modelTier` — which LLM tier to use
- `division` — organizational grouping
- `location` — where the agent runs
- `soulPath` — path to personality file
- `tools.allow` / `tools.deny` — tool access lists
- `patrol` — automated patrol schedule and actions
- `authority` — VETO configuration (for critic agents)
- `bindings` — communication channel assignments

## Agent Personality Files

Each agent has a `SOUL.md` file in `agents/<name>/` that defines its personality, behavioral instructions, and communication style. Additional files include:

- `MEMORY.md` — persistent agent memory
- `DECISIONS.md` — logged architectural decisions
