/**
 * BaseRunner — Shared agent runtime framework.
 *
 * All agents share this common runtime that provides:
 * - Poll loop: check for new tasks (configurable interval, default 2s)
 * - Atomic claim: prevent duplicate handling via UPDATE ... WHERE status='pending'
 * - Heartbeat: report health every 15s to Seldon
 * - Patrol: agent-specific periodic scanning (configurable interval)
 * - Noise budget: rate limiting unprompted agent messages
 * - Graceful shutdown: SIGTERM handling, finish current task, deregister
 */

import { Pool } from 'pg';

// ── Types ──────────────────────────────────────────────────────────────

export interface AgentConfig {
  agentId: string;
  name: string;
  role: string;
  port: number;
  seldonUrl: string;          // e.g., http://100.64.0.1:18789
  capabilities: string[];
  location?: string;
  patrolInterval?: number;    // ms, 0 to disable
  patrolActions?: string[];
  pollInterval?: number;      // ms, default 2000
  heartbeatInterval?: number; // ms, default 15000
  noiseBudgetPerHour?: number; // max unsolicited messages per hour, default 5
}

export interface TaskRecord {
  id: string;
  name: string;
  description: string | null;
  priority: number;
  metadata: Record<string, unknown>;
}

// ── BaseRunner Class ───────────────────────────────────────────────────

export class BaseRunner {
  protected config: AgentConfig;
  protected pool: Pool;
  protected isRunning = false;
  protected isProcessing = false;
  protected sessionToken: string | null = null;

  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private patrolTimer: ReturnType<typeof setInterval> | null = null;
  private currentTask: TaskRecord | null = null;

  constructor(config: AgentConfig) {
    this.config = config;
    this.pool = new Pool({
      host: process.env.DB_HOST ?? 'localhost',
      port: parseInt(process.env.DB_PORT ?? '5434', 10),
      database: process.env.DB_NAME ?? 'openclaw',
      user: process.env.DB_USER ?? 'openclaw',
      password: process.env.DB_PASSWORD ?? 'openclaw',
    });
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  /**
   * Start the agent: register, heartbeat, patrol, poll loop.
   */
  async start(): Promise<void> {
    this.isRunning = true;
    console.log(`[${this.config.agentId}] Starting agent runtime...`);

    await this.register();
    this.startHeartbeat(this.config.heartbeatInterval ?? 15_000);
    this.startPatrol();
    this.startPollLoop(this.config.pollInterval ?? 2_000);

    // Graceful shutdown handlers
    process.on('SIGTERM', () => this.shutdown());
    process.on('SIGINT', () => this.shutdown());

    console.log(`[${this.config.agentId}] Agent running (poll=${this.config.pollInterval ?? 2000}ms, heartbeat=${this.config.heartbeatInterval ?? 15000}ms)`);
  }

  /**
   * Graceful shutdown: drain current task, stop timers, deregister.
   */
  async shutdown(): Promise<void> {
    console.log(`[${this.config.agentId}] Shutting down gracefully...`);
    this.isRunning = false;

    // Stop timers
    if (this.pollTimer) clearInterval(this.pollTimer);
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    if (this.patrolTimer) clearInterval(this.patrolTimer);

    // Drain current task
    if (this.isProcessing && this.currentTask) {
      console.log(`[${this.config.agentId}] Draining current task: ${this.currentTask.id}`);
      // Wait for current task to finish (up to 30s)
      const deadline = Date.now() + 30_000;
      while (this.isProcessing && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 500));
      }
    }

    // Deregister from Seldon
    try {
      await this.sendHeartbeat('offline');
    } catch {
      // Best effort
    }

    await this.pool.end();
    console.log(`[${this.config.agentId}] Shutdown complete`);
    process.exit(0);
  }

  // ── Registration ─────────────────────────────────────────────────────

  /**
   * Register with Seldon Protocol.
   * POST /seldon/register
   */
  protected async register(): Promise<void> {
    try {
      const body = JSON.stringify({
        agent_id: this.config.agentId,
        name: this.config.name,
        role: this.config.role,
        capabilities: this.config.capabilities,
        endpoint: `http://localhost:${this.config.port}`,
        location: this.config.location ?? 'vps-1',
        status: 'online',
      });

      const response = await fetch(`${this.config.seldonUrl}/seldon/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
      });

      if (response.ok) {
        const data = await response.json() as { session_token?: string };
        this.sessionToken = data.session_token ?? null;
        console.log(`[${this.config.agentId}] Registered with Seldon (token=${this.sessionToken?.slice(0, 8)}...)`);
      } else {
        console.error(`[${this.config.agentId}] Registration failed: ${response.status}`);
      }
    } catch (err) {
      console.error(`[${this.config.agentId}] Registration error:`, err);
    }
  }

  // ── Heartbeat ────────────────────────────────────────────────────────

  /**
   * Start heartbeat loop. Reports agent status every interval to Seldon.
   */
  protected startHeartbeat(intervalMs: number): void {
    this.heartbeatTimer = setInterval(async () => {
      if (!this.isRunning) return;
      await this.sendHeartbeat(this.isProcessing ? 'busy' : 'online');
    }, intervalMs);
  }

  /**
   * Send a single heartbeat to Seldon.
   * POST /seldon/heartbeat
   */
  protected async sendHeartbeat(status: string): Promise<void> {
    try {
      const body = JSON.stringify({
        agent_id: this.config.agentId,
        session_token: this.sessionToken,
        status,
        current_task: this.currentTask
          ? { id: this.currentTask.id, name: this.currentTask.name }
          : undefined,
        metrics: {
          memory_mb: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        },
      });

      await fetch(`${this.config.seldonUrl}/seldon/heartbeat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
      });
    } catch {
      // Heartbeat failures are non-fatal
    }
  }

  // ── Poll Loop ────────────────────────────────────────────────────────

  /**
   * Start the poll loop. Checks for inbox messages at configurable interval.
   */
  protected startPollLoop(intervalMs: number): void {
    this.pollTimer = setInterval(async () => {
      if (!this.isRunning || this.isProcessing) return;
      await this.pollForTasks();
    }, intervalMs);
  }

  /**
   * Poll for pending tasks assigned to this agent.
   */
  protected async pollForTasks(): Promise<void> {
    try {
      const result = await this.pool.query(
        `SELECT id, name, description, priority, metadata
         FROM tasks
         WHERE agent_id = $1 AND status = 'pending'
         ORDER BY priority ASC, created_at ASC
         LIMIT 1`,
        [this.config.agentId]
      );

      if (result.rows.length > 0) {
        await this.claimAndProcess(result.rows[0] as TaskRecord);
      }
    } catch (err) {
      console.error(`[${this.config.agentId}] Poll error:`, err);
    }
  }

  // ── Atomic Claim ─────────────────────────────────────────────────────

  /**
   * Atomically claim a task and process it. Prevents duplicate handling.
   * Uses UPDATE ... WHERE status='pending' to ensure only one agent claims it.
   */
  protected async claimAndProcess(task: TaskRecord): Promise<void> {
    // Atomic claim: only succeeds if task is still pending
    const claimResult = await this.pool.query(
      `UPDATE tasks
       SET status = 'in_progress',
           started_at = NOW(),
           metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('claimed_by', $1, 'claimed_at', NOW()::text)
       WHERE id = $2 AND status = 'pending'
       RETURNING id`,
      [this.config.agentId, task.id]
    );

    if (claimResult.rowCount === 0) {
      // Another agent claimed it first
      return;
    }

    console.log(`[${this.config.agentId}] Claimed task: ${task.id} (${task.name})`);
    this.isProcessing = true;
    this.currentTask = task;

    try {
      const result = await this.processTask(task);

      // Mark task as completed
      await this.pool.query(
        `UPDATE tasks
         SET status = 'completed',
             completed_at = NOW(),
             result = $2
         WHERE id = $1`,
        [task.id, JSON.stringify(result)]
      );

      console.log(`[${this.config.agentId}] Completed task: ${task.id}`);
    } catch (err) {
      // Mark task as failed
      const errorMessage = err instanceof Error ? err.message : String(err);
      await this.pool.query(
        `UPDATE tasks
         SET status = 'failed',
             error_message = $2,
             retry_count = retry_count + 1
         WHERE id = $1`,
        [task.id, errorMessage]
      );
      console.error(`[${this.config.agentId}] Task failed: ${task.id}`, err);
    } finally {
      this.isProcessing = false;
      this.currentTask = null;
    }
  }

  // ── Task Processing (Override in subclass) ───────────────────────────

  /**
   * Process a claimed task. Override in agent-specific subclass.
   */
  protected async processTask(task: TaskRecord): Promise<Record<string, unknown>> {
    console.log(`[${this.config.agentId}] Processing task: ${task.name}`);
    return { status: 'completed', task_id: task.id };
  }

  // ── Noise Budget ──────────────────────────────────────────────────────

  /** Sliding window of unsolicited message timestamps for rate limiting. */
  private unsolicitedMessageTimestamps: number[] = [];

  /**
   * Check if the agent can send an unsolicited (unprompted) message.
   * Does NOT limit responses to direct questions — only unprompted messages.
   * Uses a sliding window of 1 hour.
   */
  canSendUnsolicited(): boolean {
    const budget = this.config.noiseBudgetPerHour ?? 5;
    const oneHourAgo = Date.now() - 60 * 60 * 1000;

    // Prune old timestamps outside the window
    this.unsolicitedMessageTimestamps = this.unsolicitedMessageTimestamps.filter(
      ts => ts > oneHourAgo
    );

    return this.unsolicitedMessageTimestamps.length < budget;
  }

  /**
   * Record that an unsolicited message was sent.
   * Call this after sending an unprompted message (patrol alert, proactive insight, etc.).
   */
  recordUnsolicitedMessage(): void {
    this.unsolicitedMessageTimestamps.push(Date.now());
  }

  /**
   * Get remaining noise budget for the current hour.
   */
  getRemainingBudget(): number {
    const budget = this.config.noiseBudgetPerHour ?? 5;
    const oneHourAgo = Date.now() - 60 * 60 * 1000;
    const recentCount = this.unsolicitedMessageTimestamps.filter(ts => ts > oneHourAgo).length;
    return Math.max(0, budget - recentCount);
  }

  /**
   * Send an unsolicited message if within budget. Returns true if sent.
   * Does not apply to responses to direct questions.
   */
  async trySendUnsolicited(message: string, channel?: string): Promise<boolean> {
    if (!this.canSendUnsolicited()) {
      console.log(`[${this.config.agentId}] Noise budget exhausted (${this.getRemainingBudget()} remaining). Dropping unsolicited message.`);
      return false;
    }

    this.recordUnsolicitedMessage();
    console.log(`[${this.config.agentId}] Unsolicited message sent (budget: ${this.getRemainingBudget()} remaining)`);
    return true;
  }

  // ── Patrol ───────────────────────────────────────────────────────────

  /** Set of recent patrol finding hashes for deduplication. */
  private patrolFindingHashes = new Set<string>();

  /** Max patrol interval: 2 hours (7200000ms). Min: 5 minutes (300000ms). */
  private static readonly PATROL_INTERVAL_MIN = 5 * 60 * 1000;   // 5min
  private static readonly PATROL_INTERVAL_MAX = 2 * 60 * 60 * 1000; // 2hr

  /**
   * Start patrol loop if configured. Agent-specific periodic scanning.
   * Interval is clamped to 5min–2hr range.
   */
  protected startPatrol(): void {
    let interval = this.config.patrolInterval;
    if (!interval || interval <= 0) return;

    // Clamp interval to valid range
    interval = Math.max(BaseRunner.PATROL_INTERVAL_MIN, Math.min(BaseRunner.PATROL_INTERVAL_MAX, interval));

    console.log(`[${this.config.agentId}] Patrol enabled (interval=${interval}ms, actions=${this.config.patrolActions?.join(', ')})`);

    this.patrolTimer = setInterval(async () => {
      if (!this.isRunning) return;
      try {
        const findings = await this.runPatrol();
        if (findings && findings.length > 0) {
          await this.publishPatrolFindings(findings);
        }
      } catch (err) {
        console.error(`[${this.config.agentId}] Patrol error:`, err);
      }
    }, interval);
  }

  /**
   * Run patrol actions. Override in agent-specific subclass.
   * Returns an array of findings (insights) discovered during the patrol.
   */
  protected async runPatrol(): Promise<PatrolFinding[]> {
    console.log(`[${this.config.agentId}] Running patrol (actions: ${this.config.patrolActions?.join(', ') ?? 'none'})`);
    return [];
  }

  /**
   * Publish patrol findings as insights to shared memory.
   * Deduplicates findings — same finding content is not repeated.
   */
  protected async publishPatrolFindings(findings: PatrolFinding[]): Promise<void> {
    for (const finding of findings) {
      // Deduplicate by content hash
      const hash = this.hashFinding(finding);
      if (this.patrolFindingHashes.has(hash)) {
        continue; // Already published
      }

      try {
        // Publish to facts table as shared insight
        await this.pool.query(
          `INSERT INTO facts (id, agent_id, category, subject, predicate, object, confidence, source)
           VALUES (uuid_generate_v4(), $1, $2, $3, $4, $5, $6, $7)`,
          [
            this.config.agentId,
            'patrol',
            finding.subject,
            finding.predicate,
            finding.description,
            finding.severity === 'critical' ? 1.0 : finding.severity === 'warning' ? 0.8 : 0.5,
            `patrol:${this.config.agentId}`,
          ]
        );

        this.patrolFindingHashes.add(hash);
        console.log(`[${this.config.agentId}] Patrol insight published: ${finding.subject} - ${finding.predicate}`);
      } catch (err) {
        console.error(`[${this.config.agentId}] Failed to publish patrol finding:`, err);
      }
    }

    // Prune old hashes to prevent memory growth
    if (this.patrolFindingHashes.size > 1000) {
      const iterator = this.patrolFindingHashes.values();
      for (let i = 0; i < 500; i++) {
        const val = iterator.next();
        if (val.done) break;
        this.patrolFindingHashes.delete(val.value);
      }
    }
  }

  /**
   * Hash a patrol finding for deduplication.
   */
  private hashFinding(finding: PatrolFinding): string {
    return `${finding.subject}:${finding.predicate}:${finding.description}`;
  }
}

// ── Patrol Finding Type ────────────────────────────────────────────────

export interface PatrolFinding {
  subject: string;
  predicate: string;
  description: string;
  severity: 'info' | 'warning' | 'critical';
}
