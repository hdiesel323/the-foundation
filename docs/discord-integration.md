# Discord Integration

Discord serves as the command center for The Foundation. Agents communicate through Discord threads, humans approve tasks via Discord messages, and the system posts status updates, alerts, and completion summaries to organized channels.

## Setup

### 1. Create a Discord Bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application
3. Go to the **Bot** tab and create a bot
4. Copy the bot token
5. Enable these **Privileged Gateway Intents**:
   - Message Content Intent
   - Server Members Intent

### 2. Invite the Bot

Generate an invite URL with these permissions:

- Send Messages
- Create Public Threads
- Send Messages in Threads
- Manage Threads
- Read Message History
- Embed Links

Use the OAuth2 URL generator in the Developer Portal with the `bot` scope and the permissions above.

### 3. Configure Environment

```bash
# In your .env file
DISCORD_BOT_TOKEN=your-bot-token
DISCORD_GUILD_ID=your-server-id
```

### 4. Create Channels

The Foundation expects a specific channel structure organized by division. Create these categories and channels in your Discord server:

## Channel Structure

### Command Center (Command Division)

| Channel | Purpose |
|---------|---------|
| `#mission-briefing` | Daily briefs, strategic decisions, Seldon dispatches |
| `#task-board` | Active tasks, handoffs, completions |
| `#agent-status` | Heartbeats, online/offline status, health checks |
| `#alerts` | P0 incidents, VETO triggers, escalations |

### Engineering (Infrastructure Division)

| Channel | Purpose |
|---------|---------|
| `#deployments` | Daneel deploy logs, Docker events |
| `#security` | Hardin patrol reports, vulnerability scans |
| `#architecture` | Infrastructure decisions, system design |
| `#bugs` | Issue tracking, error logs |

### Research (Intelligence Division)

| Channel | Purpose |
|---------|---------|
| `#market-intel` | Demerzel + Mis research findings |
| `#competitor-watch` | Competitive intel change alerts |
| `#reddit-digest` | Reddit/forum monitoring summaries |
| `#x-twitter-feed` | Social media intelligence |

### Content & Creative (Commerce/Operations)

| Channel | Purpose |
|---------|---------|
| `#content-pipeline` | Arkady content drafts, approvals |
| `#design-lab` | Magnifico creative briefs, brand assets |
| `#social-media` | Social post scheduling, engagement |
| `#ad-campaigns` | Riose ROAS reports, ad performance |

### Business (Commerce Division)

| Channel | Purpose |
|---------|---------|
| `#sales-pipeline` | Preem lead updates, deal tracking |
| `#revenue-ops` | Mallow revenue forecasts, pipeline health |
| `#trading` | Trader positions, P&L alerts, stop-loss triggers |
| `#weekly-reports` | Venabili weekly summaries, sprint reviews |

## Task-to-Thread Lifecycle

Every task in The Foundation gets a linked Discord thread. This is the primary space where agents collaborate, post updates, and communicate about the work.

### 1. Thread Creation

When a task is created (via dispatch or pre-flight), Seldon automatically:

1. Determines the appropriate channel based on the agent's routing config
2. Creates a public thread in that channel
3. Names the thread with priority label: `[P0-CRITICAL] Fix auth vulnerability`
4. Posts an initial message with task details

```
Task Created | ID: a1b2c3d4
Name: Fix auth vulnerability
Priority: P0-CRITICAL
Lead Agent: hardin
Status: pending

---
Agents will post updates in this thread. Summary posted on completion.
```

### 2. Agent Updates

As agents work on a task, they post updates to the thread with typed messages:

| Message Type | Emoji | Used For |
|-------------|-------|----------|
| `work_update` | wrench | Progress updates |
| `question` | question | Questions for human or other agents |
| `handoff` | arrows_counterclockwise | Transferring work to another agent |
| `status` | bar_chart | Status changes, workflow progress |
| `completion_summary` | white_check_mark | Final summary when task completes |
| `veto` | octagonal_sign | Critic chain rejection |
| `approval` | thumbsup | Critic chain approval |

### 3. Pre-flight Threads

Pre-flight requests get their own thread with the full plan:

```
PRE-FLIGHT CHECK — Awaiting approval

Intent: Create SEO-optimized blog post about AI orchestration

Plan:
  - Research competitor content and keywords
  - Draft 1500-word article with examples
  - Fact-check all claims
  - Publish to blog

Verification: Published URL returns 200, passes Lighthouse SEO

Risks:
  - Factual claims need verification
  - SEO keywords may be competitive

Agents: mis, magnifico, arkady, gaal
Workflow: content_publish

---
Reply "Go" to approve, "Stop" to cancel, or "Modify: ..." to adjust the plan.
```

### 4. Workflow Updates

As workflow steps execute, Seldon posts progress to the thread:

```
Workflow Started: Content Publish

1. research → mis — SEO research, competitor content analysis
2. creative_brief → magnifico — Creative direction
3. write → arkady — Write content per brief
4. fact_check → gaal — Verify all claims
5. human_approve → seldon — Human reviews final content
6. publish → arkady — Publish to target platform

Executing steps in dependency order...
```

### 5. Completion and Archival

When a task completes:

1. The lead agent posts a **completion summary** to the thread
2. The thread remains active for **36 hours** (configurable)
3. After the cooldown, the thread is **archived and locked**
4. The task record is moved to the `task_archive` table

```
Task Completed

Blog post published to /blog/ai-orchestration-guide
1,847 words, 12 sources cited, Lighthouse SEO score: 94

Completed at 2026-02-03T15:30:00Z
```

### 6. Workflow Completion

```
Workflow Complete: content_publish

:white_check_mark: research (mis) — completed
:white_check_mark: creative_brief (magnifico) — completed
:white_check_mark: write (arkady) — completed
:white_check_mark: fact_check (gaal) — completed
:white_check_mark: human_approve (seldon) — completed
:white_check_mark: publish (arkady) — completed

All steps completed successfully.
```

## Thread Message Tracking

All agent messages in Discord threads are tracked in the `discord_thread_messages` table:

| Column | Type | Description |
|--------|------|-------------|
| `task_id` | UUID | Parent task |
| `discord_thread_id` | VARCHAR | Discord thread ID |
| `discord_message_id` | VARCHAR | Discord message ID |
| `agent_id` | VARCHAR | Which agent posted |
| `message_type` | VARCHAR | Message type (work_update, veto, etc.) |
| `content` | TEXT | Message content |
| `created_at` | TIMESTAMPTZ | When posted |

## Agent Channel Routing

Each agent has a primary channel assignment defined in `config/channels.json`. When a task is dispatched to an agent, the thread is created in that agent's primary channel.

The routing config also supports secondary channels, DM channels for sensitive topics, and cross-posting rules.

## Archival Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Archival delay | 36 hours | Time after completion before thread is archived |
| Auto-archive duration | 24 hours | Discord's auto-archive setting for threads |
| Thread lock on archive | Yes | Threads are locked when archived |

The archival timer is in-memory. In production, use an external scheduler for reliability.

## Notifications

The Foundation sends notifications via Discord for:

- Pre-flight requests awaiting approval
- Workflow gate steps requiring human action
- P0 critical alerts
- VETO triggers from Hardin or Gaal
- Escalations to human
- Task completion summaries
- Agent status changes (online/offline)

Telegram notifications are also supported as a secondary channel, configured per division in `config/channels.json`.
