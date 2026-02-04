import express, { Request, Response } from "express";
import crypto from "node:crypto";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import pg from "pg";

// ESM __dirname shim
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const { Pool } = pg;

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.SELDON_PORT || "18789", 10);

// PostgreSQL connection
const pool = new Pool({
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT || "5432", 10),
  database: process.env.DB_NAME || "openclaw",
  user: process.env.DB_USER || "openclaw",
  password: process.env.DB_PASSWORD || "openclaw",
});

// Discord configuration
const DISCORD_BOT_TOKEN = process.env.DISCORD_BOT_TOKEN || "";
const DISCORD_GUILD_ID = process.env.DISCORD_GUILD_ID || "";
const DISCORD_API = "https://discord.com/api/v10";

// Discord API helper
async function discordRequest(
  endpoint: string,
  method: string = "GET",
  body?: unknown,
): Promise<Record<string, unknown> | null> {
  if (!DISCORD_BOT_TOKEN) return null;
  try {
    const res = await fetch(`${DISCORD_API}${endpoint}`, {
      method,
      headers: {
        Authorization: `Bot ${DISCORD_BOT_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) {
      console.error(`Discord API error: ${res.status} ${await res.text()}`);
      return null;
    }
    return (await res.json()) as Record<string, unknown>;
  } catch (err) {
    console.error("Discord API request failed:", err);
    return null;
  }
}

// Create a Discord thread for a task in the appropriate channel
async function createTaskThread(
  taskId: string,
  taskName: string,
  agentId: string,
  priority: number,
): Promise<{ threadId: string; channelId: string; messageUrl: string } | null> {
  if (!DISCORD_BOT_TOKEN || !DISCORD_GUILD_ID) return null;

  // Load channel config to find the right channel for this agent
  let channelConfig: Record<string, unknown> = {};
  try {
    const raw = fs.readFileSync(
      path.resolve(__dirname, "config", "channels.json"),
      "utf-8",
    );
    channelConfig = JSON.parse(raw);
  } catch {
    return null;
  }

  // Determine target channel from agent routing
  const routing = (
    channelConfig as Record<
      string,
      Record<string, Record<string, Record<string, string>>>
    >
  ).routing?.agent_channels?.[agentId];
  const primaryChannel = routing?.primary || "discord#task-board";
  // Extract channel name (format: "discord#channel-name")
  const channelName = primaryChannel.replace("discord#", "");

  // Find channel ID in guild
  const channels = await discordRequest(`/guilds/${DISCORD_GUILD_ID}/channels`);
  if (!channels || !Array.isArray(channels)) return null;

  const targetChannel = (channels as Array<Record<string, unknown>>).find(
    (ch) => ch.name === channelName || ch.name === "task-board",
  );
  if (!targetChannel) return null;
  const channelId = targetChannel.id as string;

  // Priority labels
  const priorityLabels: Record<number, string> = {
    1: "P0-CRITICAL",
    2: "P1-HIGH",
    5: "P2-MEDIUM",
    8: "P3-LOW",
  };
  const priorityLabel = priorityLabels[priority] || `P${priority}`;

  // Create thread via Discord API (public thread in channel)
  const thread = await discordRequest(
    `/channels/${channelId}/threads`,
    "POST",
    {
      name: `[${priorityLabel}] ${taskName}`.substring(0, 100),
      type: 11, // PUBLIC_THREAD
      auto_archive_duration: 1440, // 24 hours
    },
  );

  if (!thread || !thread.id) return null;

  // Post initial message in thread
  const guildId = DISCORD_GUILD_ID;
  const threadId = thread.id as string;
  await discordRequest(`/channels/${threadId}/messages`, "POST", {
    content: [
      `**Task Created** | ID: \`${taskId.substring(0, 8)}\``,
      `**Name:** ${taskName}`,
      `**Priority:** ${priorityLabel}`,
      `**Lead Agent:** ${agentId}`,
      `**Status:** \`pending\``,
      "",
      "---",
      "_Agents will post updates in this thread. Summary posted on completion._",
    ].join("\n"),
  });

  const messageUrl = `https://discord.com/channels/${guildId}/${channelId}/${threadId}`;

  return { threadId, channelId, messageUrl };
}

// Post a message to a task's Discord thread
async function postToTaskThread(
  threadId: string,
  agentId: string,
  content: string,
  messageType: string = "work_update",
): Promise<string | null> {
  if (!DISCORD_BOT_TOKEN || !threadId) return null;

  const typeEmojis: Record<string, string> = {
    work_update: "wrench",
    question: "question",
    handoff: "arrows_counterclockwise",
    status: "bar_chart",
    completion_summary: "white_check_mark",
    veto: "octagonal_sign",
    approval: "thumbsup",
  };
  const emoji = typeEmojis[messageType] || "speech_balloon";

  const msg = await discordRequest(`/channels/${threadId}/messages`, "POST", {
    content: `:${emoji}: **${agentId}** (${messageType})\n${content}`,
  });

  return msg ? (msg.id as string) : null;
}

// Archive a Discord thread
async function archiveDiscordThread(threadId: string): Promise<boolean> {
  if (!DISCORD_BOT_TOKEN || !threadId) return false;
  const result = await discordRequest(`/channels/${threadId}`, "PATCH", {
    archived: true,
    locked: true,
  });
  return result !== null;
}

// Task archival timers (in-memory — production would use a scheduler)
const archivalTimers: Map<string, NodeJS.Timeout> = new Map();

function scheduleArchival(
  taskId: string,
  delayMs: number = 36 * 60 * 60 * 1000,
) {
  // Default: 36 hours after completion
  if (archivalTimers.has(taskId)) return;

  const timer = setTimeout(async () => {
    try {
      // Get task info
      const result = await pool.query(
        `SELECT id, discord_thread_id, agent_id, lead_agent, name, description,
                status, priority, result, completion_summary, discord_channel_id,
                participating_agents, created_at, started_at, completed_at, metadata
         FROM tasks WHERE id = $1`,
        [taskId],
      );
      if (result.rowCount === 0) return;
      const task = result.rows[0];

      // Count thread messages
      const msgCount = await pool.query(
        `SELECT COUNT(*) as count FROM discord_thread_messages WHERE task_id = $1`,
        [taskId],
      );

      // Move to archive
      await pool.query(
        `INSERT INTO task_archive (id, original_task_id, agent_id, lead_agent, name, description,
           status, priority, result, completion_summary, discord_thread_id, discord_channel_id,
           participating_agents, thread_message_count, created_at, started_at, completed_at, metadata)
         VALUES (uuid_generate_v4(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)`,
        [
          task.id,
          task.agent_id,
          task.lead_agent,
          task.name,
          task.description,
          task.status,
          task.priority,
          task.result,
          task.completion_summary,
          task.discord_thread_id,
          task.discord_channel_id,
          task.participating_agents || [],
          parseInt(msgCount.rows[0].count, 10),
          task.created_at,
          task.started_at,
          task.completed_at,
          task.metadata,
        ],
      );

      // Archive Discord thread
      if (task.discord_thread_id) {
        await archiveDiscordThread(task.discord_thread_id);
      }

      // Mark task as archived
      await pool.query(
        `UPDATE tasks SET archived_at = NOW(), updated_at = NOW() WHERE id = $1`,
        [taskId],
      );

      archivalTimers.delete(taskId);
      console.log(`Task ${taskId} archived successfully`);
    } catch (err) {
      console.error(`Failed to archive task ${taskId}:`, err);
      archivalTimers.delete(taskId);
    }
  }, delayMs);

  archivalTimers.set(taskId, timer);
}

// ========================================
// Workflow Executor Engine
// ========================================

interface WorkflowStep {
  step: number;
  name: string;
  action: string; // "preflight" | "dispatch" | "gate" | "alert"
  agent: string;
  description?: string;
  depends_on?: string[];
  parallel_with?: string[];
  critic_chain?: string;
  can_veto?: boolean;
  gate?: string;
  gate_action?: string;
  outputs?: string[];
  optional?: boolean;
  channels?: string[];
}

interface WorkflowState {
  workflowId: string;
  parentTaskId: string;
  templateName: string;
  steps: WorkflowStep[];
  stepStatus: Record<string, string>; // step_name -> "pending"|"in_progress"|"completed"|"failed"|"skipped"|"waiting_gate"
  stepTaskIds: Record<string, string>; // step_name -> task UUID
  stepResults: Record<string, unknown>; // step_name -> result
  discordThreadId: string | null;
}

// Active workflow executions (in-memory — keyed by workflow ID)
const activeWorkflows: Map<string, WorkflowState> = new Map();

// Load a workflow template by name
function loadWorkflowTemplate(
  templateName: string,
): { name: string; steps: WorkflowStep[] } | null {
  try {
    const raw = fs.readFileSync(
      path.resolve(__dirname, "config", "workflows.json"),
      "utf-8",
    );
    const config = JSON.parse(raw);
    return config.workflow_templates?.[templateName] || null;
  } catch {
    return null;
  }
}

// Check if a step's dependencies are all satisfied
function stepDepsReady(step: WorkflowStep, state: WorkflowState): boolean {
  if (!step.depends_on || step.depends_on.length === 0) return true;
  return step.depends_on.every((dep) => {
    const status = state.stepStatus[dep];
    return status === "completed" || status === "skipped";
  });
}

// Find the next steps that can be executed (deps met, not yet started)
function getReadySteps(state: WorkflowState): WorkflowStep[] {
  return state.steps.filter((step) => {
    const status = state.stepStatus[step.name];
    if (status !== "pending") return false;
    return stepDepsReady(step, state);
  });
}

// Start executing a workflow from a template
async function startWorkflowExecution(
  parentTaskId: string,
  templateName: string,
  discordThreadId: string | null,
): Promise<string | null> {
  const template = loadWorkflowTemplate(templateName);
  if (!template) return null;

  // Create workflow record in DB
  const wfResult = await pool.query(
    `INSERT INTO workflows (name, description, steps, status, current_step, created_by, metadata)
     VALUES ($1, $2, $3, 'in_progress', 0, 'seldon', $4)
     RETURNING id`,
    [
      template.name,
      `Workflow for task ${parentTaskId}`,
      JSON.stringify(template.steps),
      JSON.stringify({ parent_task_id: parentTaskId, template: templateName }),
    ],
  );

  const workflowId = wfResult.rows[0].id;

  // Initialize step tracking
  const stepStatus: Record<string, string> = {};
  const stepTaskIds: Record<string, string> = {};
  const stepResults: Record<string, unknown> = {};

  for (const step of template.steps) {
    // Skip the "intake" step — that's the preflight we already did
    if (step.name === "intake") {
      stepStatus[step.name] = "completed";
    } else {
      stepStatus[step.name] = "pending";
    }
  }

  const state: WorkflowState = {
    workflowId,
    parentTaskId,
    templateName,
    steps: template.steps,
    stepStatus,
    stepTaskIds,
    stepResults,
    discordThreadId,
  };

  activeWorkflows.set(workflowId, state);

  // Link workflow to parent task
  await pool.query(
    `UPDATE tasks SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{workflow_id}', $2::jsonb),
       updated_at = NOW() WHERE id = $1`,
    [parentTaskId, JSON.stringify(workflowId)],
  );

  // Post workflow start to Discord thread
  if (discordThreadId) {
    const stepList = template.steps
      .filter((s) => s.name !== "intake")
      .map(
        (s, i) =>
          `${i + 1}. **${s.name}** → ${s.agent} — ${s.description || s.action}`,
      )
      .join("\n");

    await postToTaskThread(
      discordThreadId,
      "seldon",
      `**Workflow Started:** ${template.name}\n\n${stepList}\n\n_Executing steps in dependency order..._`,
      "status",
    );
  }

  // Begin executing ready steps
  await advanceWorkflow(workflowId);

  return workflowId;
}

// Advance a workflow — find and execute ready steps
async function advanceWorkflow(workflowId: string): Promise<void> {
  const state = activeWorkflows.get(workflowId);
  if (!state) return;

  const readySteps = getReadySteps(state);

  if (readySteps.length === 0) {
    // Check if workflow is complete (all steps done or skipped)
    const allDone = state.steps.every((s) => {
      const status = state.stepStatus[s.name];
      return (
        status === "completed" || status === "skipped" || status === "failed"
      );
    });

    if (allDone) {
      await completeWorkflow(workflowId);
    }
    // Otherwise waiting for in-progress or gated steps
    return;
  }

  // Execute each ready step
  for (const step of readySteps) {
    if (step.action === "gate") {
      // Human gate — pause and notify
      state.stepStatus[step.name] = "waiting_gate";

      await pool.query(
        `UPDATE workflows SET current_step = $2, metadata = jsonb_set(
           COALESCE(metadata, '{}'::jsonb), '{step_status}', $3::jsonb),
           updated_at = NOW() WHERE id = $1`,
        [workflowId, step.step, JSON.stringify(state.stepStatus)],
      );

      if (state.discordThreadId) {
        const gateAction = step.gate_action || "approve";
        await postToTaskThread(
          state.discordThreadId,
          "seldon",
          [
            `**Human Gate: ${step.name}**`,
            "",
            step.description || `Action required: ${gateAction}`,
            "",
            `_Workflow paused. Reply **"done"** when ${gateAction} is complete, or **"skip"** to skip this step._`,
          ].join("\n"),
          "question",
        );
      }

      // Log activity
      await pool
        .query(
          `INSERT INTO activities (event_type, agent_id, details)
         VALUES ('workflow_gate', 'seldon', $1)`,
          [
            JSON.stringify({
              workflow_id: workflowId,
              step: step.name,
              gate: step.gate,
              gate_action: step.gate_action,
              parent_task_id: state.parentTaskId,
            }),
          ],
        )
        .catch(() => {});
    } else if (step.action === "dispatch") {
      // Dispatch subtask to the agent
      state.stepStatus[step.name] = "in_progress";

      const subtaskResult = await pool.query(
        `INSERT INTO tasks (agent_id, lead_agent, name, description, status, priority, metadata)
         VALUES ($1, $1, $2, $3, 'pending', 3, $4)
         RETURNING id`,
        [
          step.agent,
          `[${state.templateName}] ${step.name}: ${step.description || step.name}`,
          step.description || null,
          JSON.stringify({
            workflow_id: workflowId,
            workflow_step: step.name,
            parent_task_id: state.parentTaskId,
            critic_chain: step.critic_chain || null,
            can_veto: step.can_veto || false,
          }),
        ],
      );

      const subtaskId = subtaskResult.rows[0].id;
      state.stepTaskIds[step.name] = subtaskId;

      // Update workflow state in DB
      await pool.query(
        `UPDATE workflows SET current_step = $2, metadata = jsonb_set(
           jsonb_set(COALESCE(metadata, '{}'::jsonb), '{step_status}', $3::jsonb),
           '{step_task_ids}', $4::jsonb),
           updated_at = NOW() WHERE id = $1`,
        [
          workflowId,
          step.step,
          JSON.stringify(state.stepStatus),
          JSON.stringify(state.stepTaskIds),
        ],
      );

      if (state.discordThreadId) {
        await postToTaskThread(
          state.discordThreadId,
          "seldon",
          `**Step: ${step.name}** → dispatched to **${step.agent}**\n${step.description || ""}`,
          "handoff",
        );
      }
    } else if (step.action === "alert") {
      // Alert step — just post to channels and mark done
      state.stepStatus[step.name] = "completed";

      if (state.discordThreadId) {
        await postToTaskThread(
          state.discordThreadId,
          step.agent,
          `**Alert: ${step.name}**\n${step.description || "Notification sent"}`,
          "status",
        );
      }

      // Update and advance
      await pool.query(
        `UPDATE workflows SET metadata = jsonb_set(
           COALESCE(metadata, '{}'::jsonb), '{step_status}', $2::jsonb),
           updated_at = NOW() WHERE id = $1`,
        [workflowId, JSON.stringify(state.stepStatus)],
      );

      // Continue to next steps
      await advanceWorkflow(workflowId);
    }
  }
}

// Handle a subtask completing — check if it's part of a workflow and advance
async function onSubtaskComplete(
  subtaskId: string,
  result: unknown,
): Promise<void> {
  // Check if this subtask belongs to a workflow
  const taskResult = await pool.query(
    `SELECT metadata FROM tasks WHERE id = $1`,
    [subtaskId],
  );
  if (taskResult.rowCount === 0) return;

  const metadata = taskResult.rows[0].metadata || {};
  const workflowId = metadata.workflow_id;
  const stepName = metadata.workflow_step;

  if (!workflowId || !stepName) return;

  const state = activeWorkflows.get(workflowId);
  if (!state) {
    // Try to reload from DB
    const wfResult = await pool.query(
      `SELECT metadata FROM workflows WHERE id = $1`,
      [workflowId],
    );
    if (wfResult.rowCount === 0) return;
    // Workflow exists but not in memory — would need rehydration for production
    // For now, just update the DB status
    return;
  }

  // Find the step
  const step = state.steps.find((s) => s.name === stepName);
  if (!step) return;

  // Handle critic chain veto
  if (step.critic_chain && step.can_veto) {
    // Check if the task was vetoed (status would be set by critic validation)
    const subtaskCheck = await pool.query(
      `SELECT status, metadata FROM tasks WHERE id = $1`,
      [subtaskId],
    );
    const subtaskMeta = subtaskCheck.rows[0]?.metadata || {};
    if (subtaskMeta.critic_veto) {
      // Vetoed — post to thread and keep step as in_progress (will retry)
      if (state.discordThreadId) {
        const reasons = subtaskMeta.critic_veto.reasons || [];
        await postToTaskThread(
          state.discordThreadId,
          step.agent,
          `**VETO on step: ${stepName}**\n${reasons.map((r: { agent: string; reason: string }) => `- ${r.agent}: ${r.reason}`).join("\n")}\n\n_Returning to agent for revision (retry ${subtaskMeta.critic_veto.retry}/${3})_`,
          "veto",
        );
      }
      return; // Don't advance — task will be retried
    }
  }

  // Mark step as completed
  state.stepStatus[stepName] = "completed";
  state.stepResults[stepName] = result;

  // Update DB
  await pool.query(
    `UPDATE workflows SET metadata = jsonb_set(
       jsonb_set(COALESCE(metadata, '{}'::jsonb), '{step_status}', $2::jsonb),
       '{step_results}', $3::jsonb),
       updated_at = NOW() WHERE id = $1`,
    [
      workflowId,
      JSON.stringify(state.stepStatus),
      JSON.stringify(state.stepResults),
    ],
  );

  if (state.discordThreadId) {
    await postToTaskThread(
      state.discordThreadId,
      step.agent,
      `**Step completed: ${stepName}**`,
      "approval",
    );
  }

  // Advance to next steps
  await advanceWorkflow(workflowId);
}

// Complete a workflow
async function completeWorkflow(workflowId: string): Promise<void> {
  const state = activeWorkflows.get(workflowId);
  if (!state) return;

  // Check for any failed steps
  const failedSteps = state.steps.filter(
    (s) => state.stepStatus[s.name] === "failed",
  );
  const finalStatus = failedSteps.length > 0 ? "failed" : "completed";

  // Update workflow record
  await pool.query(
    `UPDATE workflows SET status = $2, result = $3, updated_at = NOW() WHERE id = $1`,
    [
      workflowId,
      finalStatus,
      JSON.stringify({
        step_status: state.stepStatus,
        step_results: state.stepResults,
        failed_steps: failedSteps.map((s) => s.name),
      }),
    ],
  );

  // Update parent task
  if (finalStatus === "completed") {
    await pool.query(
      `UPDATE tasks SET status = 'completed', completed_at = NOW(),
         completion_summary = $2, updated_at = NOW() WHERE id = $1`,
      [
        state.parentTaskId,
        `Workflow '${state.templateName}' completed — ${state.steps.length} steps executed`,
      ],
    );
  }

  if (state.discordThreadId) {
    const summary = state.steps
      .filter((s) => s.name !== "intake")
      .map((s) => {
        const status = state.stepStatus[s.name];
        const icon =
          status === "completed"
            ? "white_check_mark"
            : status === "skipped"
              ? "fast_forward"
              : status === "failed"
                ? "x"
                : "question";
        return `:${icon}: **${s.name}** (${s.agent}) — ${status}`;
      })
      .join("\n");

    await postToTaskThread(
      state.discordThreadId,
      "seldon",
      [
        `**Workflow ${finalStatus === "completed" ? "Complete" : "Failed"}:** ${state.templateName}`,
        "",
        summary,
        "",
        failedSteps.length > 0
          ? `_${failedSteps.length} step(s) failed. Review thread for details._`
          : "_All steps completed successfully._",
      ].join("\n"),
      "completion_summary",
    );

    // Schedule archival
    scheduleArchival(state.parentTaskId, 36 * 60 * 60 * 1000);
  }

  // Log activity
  await pool
    .query(
      `INSERT INTO activities (event_type, agent_id, details)
     VALUES ('workflow_completed', 'seldon', $1)`,
      [
        JSON.stringify({
          workflow_id: workflowId,
          template: state.templateName,
          parent_task_id: state.parentTaskId,
          status: finalStatus,
          steps_completed: Object.values(state.stepStatus).filter(
            (s) => s === "completed",
          ).length,
          steps_total: state.steps.length,
        }),
      ],
    )
    .catch(() => {});

  activeWorkflows.delete(workflowId);
}

// Generate a session token
function generateSessionToken(): string {
  return `sel_${crypto.randomBytes(16).toString("hex")}`;
}

// Health check
app.get("/health", (_req: Request, res: Response) => {
  res.json({ status: "ok", service: "seldon-protocol" });
});

// POST /seldon/register — Agent announces itself
app.post("/seldon/register", async (req: Request, res: Response) => {
  const {
    agent_id,
    name,
    role,
    capabilities,
    endpoint,
    location,
    status,
    metadata,
  } = req.body;

  if (!agent_id || !name || !role) {
    res.status(400).json({ error: "agent_id, name, and role are required" });
    return;
  }

  const sessionToken = generateSessionToken();

  try {
    await pool.query(
      `INSERT INTO agents (id, name, role, location, endpoint, status, capabilities, last_heartbeat, metadata)
       VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
       ON CONFLICT (id) DO UPDATE SET
         name = EXCLUDED.name,
         role = EXCLUDED.role,
         location = EXCLUDED.location,
         endpoint = EXCLUDED.endpoint,
         status = EXCLUDED.status,
         capabilities = EXCLUDED.capabilities,
         last_heartbeat = NOW(),
         metadata = EXCLUDED.metadata`,
      [
        agent_id,
        name,
        role,
        location || null,
        endpoint || null,
        status || "online",
        Array.isArray(capabilities) ? capabilities : capabilities?.allow || [],
        metadata || {},
      ],
    );

    res.json({
      registered: true,
      session_token: sessionToken,
      heartbeat_interval: 300,
    });
  } catch (err) {
    console.error("Failed to register agent:", err);
    res.status(500).json({ error: "Failed to register agent" });
  }
});

// POST /seldon/heartbeat — Agent reports status
app.post("/seldon/heartbeat", async (req: Request, res: Response) => {
  const { agent_id, session_token, status, current_task, metrics } = req.body;

  if (!agent_id) {
    res.status(400).json({ error: "agent_id is required" });
    return;
  }

  try {
    const result = await pool.query(
      `UPDATE agents
       SET last_heartbeat = NOW(),
           status = COALESCE($2, status),
           metadata = jsonb_set(
             COALESCE(metadata, '{}'::jsonb),
             '{heartbeat}',
             $3::jsonb
           )
       WHERE id = $1
       RETURNING id, status, last_heartbeat`,
      [
        agent_id,
        status || null,
        JSON.stringify({
          session_token: session_token || null,
          current_task: current_task || null,
          metrics: metrics || null,
          received_at: new Date().toISOString(),
        }),
      ],
    );

    if (result.rowCount === 0) {
      res.status(404).json({ error: "Agent not found. Register first." });
      return;
    }

    res.json({
      acknowledged: true,
      agent_id: result.rows[0].id,
      status: result.rows[0].status,
      last_heartbeat: result.rows[0].last_heartbeat,
    });
  } catch (err) {
    console.error("Failed to process heartbeat:", err);
    res.status(500).json({ error: "Failed to process heartbeat" });
  }
});

// GET /seldon/agents — List all registered agents
app.get("/seldon/agents", async (_req: Request, res: Response) => {
  try {
    const result = await pool.query(
      `SELECT id, name, role, location, endpoint, status, capabilities, last_heartbeat, registered_at, metadata
       FROM agents
       ORDER BY registered_at DESC`,
    );

    res.json({
      agents: result.rows,
      count: result.rowCount,
    });
  } catch (err) {
    console.error("Failed to list agents:", err);
    res.status(500).json({ error: "Failed to list agents" });
  }
});

// POST /seldon/dispatch — Send task to specific agent
app.post("/seldon/dispatch", async (req: Request, res: Response) => {
  const {
    task,
    priority,
    preferred_agent,
    fallback_agents,
    timeout,
    callback,
    acceptance_criteria,
  } = req.body;

  if (!task) {
    res.status(400).json({ error: "task is required" });
    return;
  }

  // Determine which agent to dispatch to
  let targetAgent: string | null = preferred_agent || null;

  try {
    // If preferred_agent is specified, verify it exists and is online
    if (targetAgent) {
      const agentCheck = await pool.query(
        `SELECT id, status FROM agents WHERE id = $1`,
        [targetAgent],
      );

      if (agentCheck.rowCount === 0) {
        // Try fallback agents if preferred is not found
        if (fallback_agents && fallback_agents.length > 0) {
          const fallbackCheck = await pool.query(
            `SELECT id FROM agents WHERE id = ANY($1) AND status IN ('online', 'healthy', 'idle', 'active') LIMIT 1`,
            [fallback_agents],
          );
          if (fallbackCheck.rowCount && fallbackCheck.rowCount > 0) {
            targetAgent = fallbackCheck.rows[0].id;
          } else {
            res.status(404).json({
              error:
                "No available agents found (preferred and fallbacks unavailable)",
            });
            return;
          }
        } else {
          res
            .status(404)
            .json({ error: `Preferred agent '${targetAgent}' not found` });
          return;
        }
      }
    } else {
      // No preferred agent — pick first available online agent
      const anyAgent = await pool.query(
        `SELECT id FROM agents WHERE status IN ('online', 'healthy', 'idle', 'active') ORDER BY last_heartbeat DESC LIMIT 1`,
      );
      if (anyAgent.rowCount && anyAgent.rowCount > 0) {
        targetAgent = anyAgent.rows[0].id;
      } else {
        res.status(404).json({ error: "No available agents to dispatch to" });
        return;
      }
    }

    // Map priority string to integer (tasks table uses INTEGER priority)
    let priorityInt = 5;
    if (typeof priority === "number") {
      priorityInt = priority;
    } else if (typeof priority === "string") {
      const priorityMap: Record<string, number> = {
        critical: 1,
        high: 2,
        medium: 5,
        low: 8,
      };
      priorityInt = priorityMap[priority.toLowerCase()] ?? 5;
    }

    // Insert task into tasks table
    const taskResult = await pool.query(
      `INSERT INTO tasks (agent_id, lead_agent, name, status, priority, metadata)
       VALUES ($1, $1, $2, 'pending', $3, $4)
       RETURNING id, agent_id, name, status, priority, created_at`,
      [
        targetAgent,
        task,
        priorityInt,
        JSON.stringify({
          fallback_agents: fallback_agents || [],
          timeout: timeout || null,
          callback: callback || null,
          acceptance_criteria: acceptance_criteria || null,
          dispatched_at: new Date().toISOString(),
        }),
      ],
    );

    const newTaskId = taskResult.rows[0].id;

    // Create linked Discord thread for this task
    const threadInfo = await createTaskThread(
      newTaskId,
      task,
      targetAgent!,
      priorityInt,
    );

    if (threadInfo) {
      await pool.query(
        `UPDATE tasks SET discord_thread_id = $2, discord_channel_id = $3, discord_message_url = $4 WHERE id = $1`,
        [
          newTaskId,
          threadInfo.threadId,
          threadInfo.channelId,
          threadInfo.messageUrl,
        ],
      );
    }

    // Log activity
    await pool
      .query(
        `INSERT INTO activities (event_type, agent_id, details)
       VALUES ('task_created', $1, $2)`,
        [
          targetAgent,
          JSON.stringify({
            task_id: newTaskId,
            task_name: task,
            priority: priorityInt,
            discord_thread_id: threadInfo?.threadId || null,
            discord_message_url: threadInfo?.messageUrl || null,
          }),
        ],
      )
      .catch(() => {});

    res.json({
      dispatched: true,
      task_id: newTaskId,
      assigned_agent: taskResult.rows[0].agent_id,
      priority: taskResult.rows[0].priority,
      status: taskResult.rows[0].status,
      created_at: taskResult.rows[0].created_at,
      has_acceptance_criteria: !!acceptance_criteria,
      discord_thread_id: threadInfo?.threadId || null,
      discord_message_url: threadInfo?.messageUrl || null,
    });
  } catch (err) {
    console.error("Failed to dispatch task:", err);
    res.status(500).json({ error: "Failed to dispatch task" });
  }
});

// POST /seldon/preflight — Create a pre-flight plan and wait for human approval before executing
app.post("/seldon/preflight", async (req: Request, res: Response) => {
  const {
    task,
    intent,
    plan,
    verification,
    risks,
    workflow_template,
    priority,
    estimated_agents,
    critic_chains,
  } = req.body;

  if (!task || !intent) {
    res.status(400).json({ error: "task and intent are required" });
    return;
  }

  // Map priority string to integer
  let priorityInt = 5;
  if (typeof priority === "number") {
    priorityInt = priority;
  } else if (typeof priority === "string") {
    const priorityMap: Record<string, number> = {
      critical: 1,
      high: 2,
      medium: 5,
      low: 8,
    };
    priorityInt = priorityMap[priority.toLowerCase()] ?? 5;
  }

  try {
    // Create task in 'awaiting_approval' status
    const taskResult = await pool.query(
      `INSERT INTO tasks (agent_id, lead_agent, name, description, status, priority, metadata)
       VALUES ('seldon', 'seldon', $1, $2, 'awaiting_approval', $3, $4)
       RETURNING id, created_at`,
      [
        task,
        intent,
        priorityInt,
        JSON.stringify({
          preflight: {
            intent,
            plan: plan || [],
            verification: verification || null,
            risks: risks || [],
            estimated_agents: estimated_agents || [],
            critic_chains: critic_chains || [],
            workflow_template: workflow_template || null,
          },
          dispatched_at: new Date().toISOString(),
        }),
      ],
    );

    const taskId = taskResult.rows[0].id;

    // Create Discord thread for pre-flight
    const threadInfo = await createTaskThread(
      taskId,
      task,
      "seldon",
      priorityInt,
    );

    if (threadInfo) {
      await pool.query(
        `UPDATE tasks SET discord_thread_id = $2, discord_channel_id = $3, discord_message_url = $4 WHERE id = $1`,
        [
          taskId,
          threadInfo.threadId,
          threadInfo.channelId,
          threadInfo.messageUrl,
        ],
      );

      // Post the pre-flight plan to the thread
      const planBullets = Array.isArray(plan)
        ? plan.map((p: string) => `  - ${p}`).join("\n")
        : plan || "TBD";
      const riskBullets = Array.isArray(risks)
        ? risks.map((r: string) => `  - ${r}`).join("\n")
        : risks || "None identified";
      const agentList = Array.isArray(estimated_agents)
        ? estimated_agents.join(", ")
        : estimated_agents || "TBD";

      await postToTaskThread(
        threadInfo.threadId,
        "seldon",
        [
          "**PRE-FLIGHT CHECK** — Awaiting approval",
          "",
          `**Intent:** ${intent}`,
          "",
          `**Plan:**`,
          planBullets,
          "",
          `**Verification:** ${verification || "TBD"}`,
          "",
          `**Risks:**`,
          riskBullets,
          "",
          `**Agents:** ${agentList}`,
          workflow_template ? `**Workflow:** ${workflow_template}` : "",
          "",
          "---",
          '_Reply **"Go"** to approve, **"Stop"** to cancel, or **"Modify: ..."** to adjust the plan._',
        ].join("\n"),
        "status",
      );
    }

    // Log activity
    await pool
      .query(
        `INSERT INTO activities (event_type, agent_id, details)
       VALUES ('preflight_created', 'seldon', $1)`,
        [
          JSON.stringify({
            task_id: taskId,
            task_name: task,
            intent,
            workflow_template: workflow_template || null,
            discord_thread_id: threadInfo?.threadId || null,
          }),
        ],
      )
      .catch(() => {});

    res.json({
      preflight_id: taskId,
      status: "awaiting_approval",
      task,
      intent,
      discord_thread_id: threadInfo?.threadId || null,
      discord_message_url: threadInfo?.messageUrl || null,
      next_action:
        'Reply "Go" in Discord thread or call POST /seldon/preflight/:id/approve',
    });
  } catch (err) {
    console.error("Failed to create preflight:", err);
    res.status(500).json({ error: "Failed to create preflight" });
  }
});

// POST /seldon/preflight/:taskId/approve — Human approves pre-flight, triggers workflow execution
app.post(
  "/seldon/preflight/:taskId/approve",
  async (req: Request, res: Response) => {
    const { taskId } = req.params;
    const { action, modifications } = req.body;
    // action: "go" | "stop" | "modify"

    try {
      const taskResult = await pool.query(
        `SELECT id, name, status, metadata, discord_thread_id FROM tasks WHERE id = $1`,
        [taskId],
      );

      if (taskResult.rowCount === 0) {
        res.status(404).json({ error: `Task '${taskId}' not found` });
        return;
      }

      const task = taskResult.rows[0];

      if (task.status !== "awaiting_approval") {
        res.status(400).json({
          error: `Task is '${task.status}', not awaiting_approval`,
        });
        return;
      }

      const approvalAction = (action || "go").toLowerCase();

      if (approvalAction === "stop") {
        // Cancel the task
        await pool.query(
          `UPDATE tasks SET status = 'cancelled', updated_at = NOW(),
           metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{cancelled}',
             $2::jsonb) WHERE id = $1`,
          [
            taskId,
            JSON.stringify({
              reason: "Human cancelled pre-flight",
              at: new Date().toISOString(),
            }),
          ],
        );

        if (task.discord_thread_id) {
          await postToTaskThread(
            task.discord_thread_id,
            "seldon",
            "**Cancelled** — Human stopped this task.",
            "status",
          );
          await archiveDiscordThread(task.discord_thread_id);
        }

        res.json({ task_id: taskId, status: "cancelled" });
        return;
      }

      if (approvalAction === "modify") {
        // Update the plan with modifications, keep awaiting
        const metadata = task.metadata || {};
        const preflight = metadata.preflight || {};
        preflight.modifications = modifications;
        preflight.modified_at = new Date().toISOString();

        await pool.query(
          `UPDATE tasks SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{preflight}',
             $2::jsonb), updated_at = NOW() WHERE id = $1`,
          [taskId, JSON.stringify(preflight)],
        );

        if (task.discord_thread_id) {
          await postToTaskThread(
            task.discord_thread_id,
            "seldon",
            `**Plan Modified**\n${typeof modifications === "string" ? modifications : JSON.stringify(modifications)}\n\n_Awaiting new "Go" approval._`,
            "status",
          );
        }

        res.json({
          task_id: taskId,
          status: "awaiting_approval",
          modified: true,
        });
        return;
      }

      // "go" — approve and start execution
      await pool.query(
        `UPDATE tasks SET status = 'pending', updated_at = NOW(),
         metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{approved}',
           $2::jsonb) WHERE id = $1`,
        [taskId, JSON.stringify({ by: "human", at: new Date().toISOString() })],
      );

      if (task.discord_thread_id) {
        await postToTaskThread(
          task.discord_thread_id,
          "seldon",
          "**Approved** — Workflow execution starting.",
          "approval",
        );
      }

      // Log activity
      await pool
        .query(
          `INSERT INTO activities (event_type, agent_id, details)
         VALUES ('preflight_approved', 'seldon', $1)`,
          [JSON.stringify({ task_id: taskId, task_name: task.name })],
        )
        .catch(() => {});

      // If there's a workflow template, load it and begin dispatching steps
      const metadata = task.metadata || {};
      const preflight = metadata.preflight || {};
      const workflowTemplate = preflight.workflow_template;

      let workflow = null;
      if (workflowTemplate) {
        try {
          const raw = fs.readFileSync(
            path.resolve(__dirname, "config", "workflows.json"),
            "utf-8",
          );
          const config = JSON.parse(raw);
          workflow = config.workflow_templates?.[workflowTemplate] || null;
        } catch {
          // Workflow config not found
        }
      }

      // If there's a workflow template, start execution
      let workflowExecutionId: string | null = null;
      if (workflowTemplate && workflow) {
        workflowExecutionId = await startWorkflowExecution(
          taskId,
          workflowTemplate,
          task.discord_thread_id || null,
        );
      }

      res.json({
        task_id: taskId,
        status: "approved",
        workflow_template: workflowTemplate || null,
        workflow_id: workflowExecutionId,
        workflow_steps: workflow ? workflow.steps.length : 0,
        executing: !!workflowExecutionId,
        next: workflowExecutionId
          ? `Workflow '${workflowTemplate}' executing — ${workflow!.steps.length} steps`
          : "Task approved — dispatch subtasks manually or via workflow",
      });
    } catch (err) {
      console.error("Failed to approve preflight:", err);
      res.status(500).json({ error: "Failed to approve preflight" });
    }
  },
);

// POST /seldon/complete — Mark task as complete with result validation against acceptance_criteria
app.post("/seldon/complete", async (req: Request, res: Response) => {
  const { task_id, result, agent_id } = req.body;

  if (!task_id || !agent_id) {
    res.status(400).json({ error: "task_id and agent_id are required" });
    return;
  }

  try {
    // Fetch task with metadata containing acceptance_criteria
    const taskQuery = await pool.query(
      `SELECT id, agent_id, name, status, metadata, discord_thread_id, discord_channel_id FROM tasks WHERE id = $1`,
      [task_id],
    );

    if (taskQuery.rowCount === 0) {
      res.status(404).json({ error: `Task '${task_id}' not found` });
      return;
    }

    const task = taskQuery.rows[0];
    const metadata = task.metadata || {};
    const criteria = metadata.acceptance_criteria;
    const violations: string[] = [];

    // Validate against acceptance_criteria if present
    if (criteria) {
      if (
        criteria.required_outputs &&
        Array.isArray(criteria.required_outputs)
      ) {
        for (const required of criteria.required_outputs) {
          if (!result || !JSON.stringify(result).includes(required)) {
            violations.push(`missing_required_output: ${required}`);
          }
        }
      }

      if (criteria.format && result) {
        if (typeof result !== criteria.format && typeof result !== "object") {
          violations.push(`format_mismatch: expected ${criteria.format}`);
        }
      }

      if (criteria.validators && Array.isArray(criteria.validators)) {
        // Store validators as metadata for downstream processing
        // Actual validation logic would be agent-specific
      }

      if (criteria.min_sources && result && typeof result === "object") {
        const sources = (result as Record<string, unknown>).sources;
        if (
          !sources ||
          !Array.isArray(sources) ||
          sources.length < criteria.min_sources
        ) {
          violations.push(`insufficient_sources: need ${criteria.min_sources}`);
        }
      }

      if (
        criteria.confidence_threshold &&
        result &&
        typeof result === "object"
      ) {
        const confidence = (result as Record<string, unknown>).confidence;
        if (
          typeof confidence === "number" &&
          confidence < criteria.confidence_threshold
        ) {
          violations.push(
            `low_confidence: ${confidence} < ${criteria.confidence_threshold}`,
          );
        }
      }
    }

    if (violations.length > 0) {
      // Task failed acceptance criteria — do not mark complete
      await pool.query(
        `UPDATE tasks SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{validation_failures}', $2::jsonb), updated_at = NOW() WHERE id = $1`,
        [task_id, JSON.stringify(violations)],
      );

      res.json({
        completed: false,
        task_id,
        violations,
        message: "Task result did not meet acceptance criteria",
      });
      return;
    }

    // Mark task as complete
    const completionSummary =
      result &&
      typeof result === "object" &&
      (result as Record<string, unknown>).summary
        ? String((result as Record<string, unknown>).summary)
        : `Task completed by ${agent_id}`;

    await pool.query(
      `UPDATE tasks SET status = 'completed', result = $2, completed_at = NOW(),
       updated_at = NOW(), completion_summary = $3 WHERE id = $1`,
      [task_id, JSON.stringify(result || {}), completionSummary],
    );

    // Add agent to participating_agents if not already there
    await pool
      .query(
        `UPDATE tasks SET participating_agents = array_append(
         CASE WHEN $2 = ANY(participating_agents) THEN participating_agents
              ELSE participating_agents END, $2)
       WHERE id = $1 AND NOT ($2 = ANY(COALESCE(participating_agents, '{}')))`,
        [task_id, agent_id],
      )
      .catch(() => {});

    // Post completion summary to Discord thread
    if (task.discord_thread_id) {
      await postToTaskThread(
        task.discord_thread_id,
        agent_id,
        [
          "**Task Completed**",
          "",
          completionSummary,
          "",
          `_Completed at ${new Date().toISOString()}_`,
        ].join("\n"),
        "completion_summary",
      );

      // Record the summary message in DB
      await pool
        .query(
          `INSERT INTO discord_thread_messages (task_id, discord_thread_id, agent_id, message_type, content)
         VALUES ($1, $2, $3, 'completion_summary', $4)`,
          [task_id, task.discord_thread_id, agent_id, completionSummary],
        )
        .catch(() => {});

      // Schedule archival (36 hours for Discord thread, 48 hours for dashboard)
      scheduleArchival(task_id, 36 * 60 * 60 * 1000);
    }

    // Log activity
    await pool
      .query(
        `INSERT INTO activities (event_type, agent_id, details)
       VALUES ('task_completed', $1, $2)`,
        [
          agent_id,
          JSON.stringify({
            task_id,
            task_name: task.name,
            summary: completionSummary,
            discord_thread_id: task.discord_thread_id || null,
          }),
        ],
      )
      .catch(() => {});

    // Check if this task is part of a workflow — advance the workflow
    await onSubtaskComplete(task_id, result).catch((err) => {
      console.error("Failed to advance workflow after subtask complete:", err);
    });

    res.json({
      completed: true,
      task_id,
      agent_id,
      violations: [],
      completion_summary: completionSummary,
      archival_scheduled: !!task.discord_thread_id,
    });
  } catch (err) {
    console.error("Failed to complete task:", err);
    res.status(500).json({ error: "Failed to complete task" });
  }
});

// POST /seldon/handoff — Transfer task between agents
app.post("/seldon/handoff", async (req: Request, res: Response) => {
  const { from_agent, to_agent, context, require_response } = req.body;

  if (!from_agent || !to_agent || !context) {
    res
      .status(400)
      .json({ error: "from_agent, to_agent, and context are required" });
    return;
  }

  try {
    // Verify both agents exist
    const fromCheck = await pool.query(
      "SELECT id, status FROM agents WHERE id = $1",
      [from_agent],
    );
    if (fromCheck.rowCount === 0) {
      res.status(404).json({ error: `Agent '${from_agent}' not found` });
      return;
    }

    const toCheck = await pool.query(
      "SELECT id, status FROM agents WHERE id = $1",
      [to_agent],
    );
    if (toCheck.rowCount === 0) {
      res.status(404).json({ error: `Agent '${to_agent}' not found` });
      return;
    }

    // Insert handoff record into handoffs table
    const result = await pool.query(
      `INSERT INTO handoffs (from_agent, to_agent, context, status)
       VALUES ($1, $2, $3, $4)
       RETURNING id, from_agent, to_agent, context, status, created_at`,
      [
        from_agent,
        to_agent,
        JSON.stringify(context),
        require_response ? "awaiting_response" : "pending",
      ],
    );

    res.json({
      handoff_id: result.rows[0].id,
      from_agent: result.rows[0].from_agent,
      to_agent: result.rows[0].to_agent,
      status: result.rows[0].status,
      require_response: require_response || false,
      created_at: result.rows[0].created_at,
    });
  } catch (err) {
    console.error("Failed to create handoff:", err);
    res.status(500).json({ error: "Failed to create handoff" });
  }
});

// GET /seldon/handoffs/:agentId — List pending handoffs for an agent
app.get("/seldon/handoffs/:agentId", async (req: Request, res: Response) => {
  const { agentId } = req.params;
  const statusFilter = (req.query.status as string) || "pending";

  try {
    // Verify agent exists
    const agentCheck = await pool.query("SELECT id FROM agents WHERE id = $1", [
      agentId,
    ]);
    if (agentCheck.rowCount === 0) {
      res.status(404).json({ error: `Agent '${agentId}' not found` });
      return;
    }

    const result = await pool.query(
      `SELECT id, from_agent, to_agent, context, status, created_at, completed_at, result
       FROM handoffs
       WHERE to_agent = $1 AND status = $2
       ORDER BY created_at DESC`,
      [agentId, statusFilter],
    );

    res.json({
      agent_id: agentId,
      status_filter: statusFilter,
      handoffs: result.rows,
      count: result.rowCount,
    });
  } catch (err) {
    console.error("Failed to list handoffs:", err);
    res.status(500).json({ error: "Failed to list handoffs" });
  }
});

// POST /seldon/broadcast — Send message to all registered agents
app.post("/seldon/broadcast", async (req: Request, res: Response) => {
  const { message, priority, from_agent, filter_status } = req.body;

  if (!message) {
    res.status(400).json({ error: "message is required" });
    return;
  }

  try {
    // Get all agents, optionally filtered by status
    const statusFilter = filter_status || ["online", "healthy"];
    const agentsResult = await pool.query(
      `SELECT id FROM agents WHERE status = ANY($1)`,
      [statusFilter],
    );

    if (agentsResult.rowCount === 0) {
      res.json({ broadcast: true, delivered_to: [], count: 0 });
      return;
    }

    // Map priority string to integer
    let priorityInt = 5;
    if (typeof priority === "number") {
      priorityInt = priority;
    } else if (typeof priority === "string") {
      const priorityMap: Record<string, number> = {
        critical: 1,
        high: 2,
        medium: 5,
        low: 8,
      };
      priorityInt = priorityMap[priority.toLowerCase()] ?? 5;
    }

    // Create a task for each agent
    const deliveredTo: string[] = [];
    for (const agent of agentsResult.rows) {
      await pool.query(
        `INSERT INTO tasks (agent_id, name, status, priority, metadata)
         VALUES ($1, $2, 'pending', $3, $4)`,
        [
          agent.id,
          message,
          priorityInt,
          JSON.stringify({
            broadcast: true,
            from_agent: from_agent || "seldon",
            broadcast_at: new Date().toISOString(),
          }),
        ],
      );
      deliveredTo.push(agent.id);
    }

    res.json({
      broadcast: true,
      delivered_to: deliveredTo,
      count: deliveredTo.length,
    });
  } catch (err) {
    console.error("Failed to broadcast:", err);
    res.status(500).json({ error: "Failed to broadcast message" });
  }
});

// Subagent config
const SUBAGENT_MAX_CONCURRENT = 5;

// POST /seldon/spawn — Spawn parallel subagent tasks
app.post("/seldon/spawn", async (req: Request, res: Response) => {
  const { parent_agent, task_list, max_concurrent } = req.body;

  if (
    !parent_agent ||
    !task_list ||
    !Array.isArray(task_list) ||
    task_list.length === 0
  ) {
    res.status(400).json({
      error: "parent_agent and non-empty task_list array are required",
    });
    return;
  }

  // Validate max_concurrent against config limit
  const requestedConcurrent = max_concurrent || task_list.length;
  if (requestedConcurrent > SUBAGENT_MAX_CONCURRENT) {
    res.status(400).json({
      error: `max_concurrent ${requestedConcurrent} exceeds config limit of ${SUBAGENT_MAX_CONCURRENT}`,
      max_allowed: SUBAGENT_MAX_CONCURRENT,
    });
    return;
  }

  try {
    // Verify parent agent exists
    const parentCheck = await pool.query(
      "SELECT id, status FROM agents WHERE id = $1",
      [parent_agent],
    );
    if (parentCheck.rowCount === 0) {
      res
        .status(404)
        .json({ error: `Parent agent '${parent_agent}' not found` });
      return;
    }

    const spawnGroupId = crypto.randomUUID();
    const spawned: Array<{
      spawn_id: string;
      task: string;
      status: string;
      assigned_agent: string;
    }> = [];

    for (const taskItem of task_list) {
      const taskName = typeof taskItem === "string" ? taskItem : taskItem.task;
      const targetAgent =
        typeof taskItem === "object" && taskItem.agent
          ? taskItem.agent
          : parent_agent;

      const result = await pool.query(
        `INSERT INTO tasks (agent_id, name, status, priority, metadata)
         VALUES ($1, $2, 'pending', 3, $3)
         RETURNING id`,
        [
          targetAgent,
          taskName,
          JSON.stringify({
            spawn_group: spawnGroupId,
            parent_agent,
            max_concurrent: requestedConcurrent,
            spawned_at: new Date().toISOString(),
          }),
        ],
      );

      spawned.push({
        spawn_id: result.rows[0].id,
        task: taskName,
        status: "pending",
        assigned_agent: targetAgent,
      });
    }

    res.json({
      spawn_group: spawnGroupId,
      parent_agent,
      max_concurrent: requestedConcurrent,
      subtasks: spawned,
      count: spawned.length,
    });
  } catch (err) {
    console.error("Failed to spawn subagents:", err);
    res.status(500).json({ error: "Failed to spawn subagent tasks" });
  }
});

// Critic chain types
interface CriticLayer {
  agent: string;
  scope: string;
}

interface CriticChain {
  layers: CriticLayer[];
  require_unanimous: boolean;
  max_retries: number;
  on_final_reject: string;
}

interface CriticVerdict {
  agent: string;
  scope: string;
  decision: "approve" | "veto";
  reason?: string;
}

// POST /seldon/validate — Run critic chain validation on a task output
app.post("/seldon/validate", async (req: Request, res: Response) => {
  const { task_id, chain_name, output, originating_agent, retry_count } =
    req.body;

  if (!task_id || !chain_name || !output) {
    res
      .status(400)
      .json({ error: "task_id, chain_name, and output are required" });
    return;
  }

  // Load critic chain config
  let chains: Record<string, CriticChain>;
  try {
    const fs = await import("node:fs");
    const configPath =
      process.env.CRITIC_CHAINS_PATH || "/config/critic-chains.json";
    const raw = fs.readFileSync(configPath, "utf-8");
    chains = JSON.parse(raw).critic_chains;
  } catch {
    // Fallback: default chain
    chains = {
      default: {
        layers: [
          { agent: "seldon", scope: "format" },
          { agent: "preem", scope: "security" },
        ],
        require_unanimous: false,
        max_retries: 3,
        on_final_reject: "return_error",
      },
    };
  }

  const chain = chains[chain_name] || chains["default"];
  if (!chain) {
    res.status(400).json({ error: `Unknown critic chain: ${chain_name}` });
    return;
  }

  const currentRetry = retry_count || 0;

  // Check max_retries enforcement
  if (currentRetry >= chain.max_retries) {
    // Escalation after retries exhausted
    const escalation =
      chain.on_final_reject === "escalate_to_human"
        ? {
            action: "escalate_to_human",
            message: `Task ${task_id} failed critic review after ${chain.max_retries} retries`,
          }
        : {
            action: "return_error",
            message: `Task ${task_id} rejected after ${chain.max_retries} retries`,
          };

    try {
      await pool.query(
        `UPDATE tasks SET status = 'failed', metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{escalation}', $2::jsonb), updated_at = NOW() WHERE id = $1`,
        [task_id, JSON.stringify(escalation)],
      );
    } catch {
      // Log but don't fail
    }

    res.json({
      validated: false,
      task_id,
      chain: chain_name,
      retry_count: currentRetry,
      max_retries_exceeded: true,
      escalation,
    });
    return;
  }

  try {
    // Process each layer in the chain
    const verdicts: CriticVerdict[] = [];
    let anyVeto = false;

    for (const layer of chain.layers) {
      // In a real system, each layer would dispatch to the critic agent and await response.
      // Here we record the expected validation and create audit trail.
      const verdict: CriticVerdict = {
        agent: layer.agent,
        scope: layer.scope,
        decision: "approve", // Default: approve (actual critic agents would set this)
      };

      verdicts.push(verdict);

      if (verdict.decision === "veto") {
        anyVeto = true;
        // If not require_unanimous, can short-circuit on first veto
        if (!chain.require_unanimous) {
          break;
        }
      }
    }

    // For require_unanimous: all layers must be checked
    const allApproved = verdicts.every((v) => v.decision === "approve");
    const approved = chain.require_unanimous ? allApproved : !anyVeto;

    if (!approved) {
      // On veto: return to originating agent with veto reason
      const vetoReasons = verdicts
        .filter((v) => v.decision === "veto")
        .map((v) => ({ agent: v.agent, scope: v.scope, reason: v.reason }));

      try {
        await pool.query(
          `UPDATE tasks SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{critic_veto}', $2::jsonb), updated_at = NOW() WHERE id = $1`,
          [
            task_id,
            JSON.stringify({
              retry: currentRetry + 1,
              reasons: vetoReasons,
              return_to: originating_agent,
            }),
          ],
        );
      } catch {
        // Log but don't fail
      }

      res.json({
        validated: false,
        task_id,
        chain: chain_name,
        verdicts,
        veto_reasons: vetoReasons,
        return_to_agent: originating_agent || null,
        retry_count: currentRetry + 1,
        max_retries: chain.max_retries,
      });
      return;
    }

    // All layers approved
    try {
      await pool.query(
        `UPDATE tasks SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{critic_approved}', $2::jsonb), updated_at = NOW() WHERE id = $1`,
        [
          task_id,
          JSON.stringify({
            chain: chain_name,
            verdicts,
            approved_at: new Date().toISOString(),
          }),
        ],
      );
    } catch {
      // Log but don't fail
    }

    res.json({
      validated: true,
      task_id,
      chain: chain_name,
      verdicts,
      require_unanimous: chain.require_unanimous,
    });
  } catch (err) {
    console.error("Failed to process critic chain:", err);
    res
      .status(500)
      .json({ error: "Failed to process critic chain validation" });
  }
});

// GET /seldon/tasks — List tasks with Discord thread info
app.get("/seldon/tasks", async (req: Request, res: Response) => {
  const status = (req.query.status as string) || null;
  const includeArchived = req.query.include_archived === "true";
  const limit = parseInt((req.query.limit as string) || "50", 10);

  try {
    let query = `
      SELECT id, agent_id, lead_agent, name, description, status, priority,
             scheduled_at, started_at, completed_at, archived_at,
             discord_thread_id, discord_channel_id, discord_message_url,
             participating_agents, completion_summary,
             created_at, updated_at, metadata
      FROM tasks
      WHERE 1=1
    `;
    const params: unknown[] = [];

    if (status) {
      params.push(status);
      query += ` AND status = $${params.length}`;
    }

    if (!includeArchived) {
      query += ` AND archived_at IS NULL`;
    }

    query += ` ORDER BY created_at DESC`;
    params.push(limit);
    query += ` LIMIT $${params.length}`;

    const result = await pool.query(query, params);

    res.json({
      tasks: result.rows,
      count: result.rowCount,
    });
  } catch (err) {
    console.error("Failed to list tasks:", err);
    res.status(500).json({ error: "Failed to list tasks" });
  }
});

// GET /seldon/task/:taskId — Get single task with thread details
app.get("/seldon/task/:taskId", async (req: Request, res: Response) => {
  const { taskId } = req.params;

  try {
    const taskResult = await pool.query(
      `SELECT id, agent_id, lead_agent, name, description, status, priority,
              scheduled_at, started_at, completed_at, archived_at,
              discord_thread_id, discord_channel_id, discord_message_url,
              participating_agents, completion_summary, result,
              created_at, updated_at, metadata
       FROM tasks WHERE id = $1`,
      [taskId],
    );

    if (taskResult.rowCount === 0) {
      res.status(404).json({ error: `Task '${taskId}' not found` });
      return;
    }

    // Get thread messages if any
    const messagesResult = await pool.query(
      `SELECT id, agent_id, message_type, content, created_at
       FROM discord_thread_messages
       WHERE task_id = $1
       ORDER BY created_at ASC`,
      [taskId],
    );

    res.json({
      task: taskResult.rows[0],
      thread_messages: messagesResult.rows,
      thread_message_count: messagesResult.rowCount,
    });
  } catch (err) {
    console.error("Failed to get task:", err);
    res.status(500).json({ error: "Failed to get task" });
  }
});

// POST /seldon/task/:taskId/thread-message — Agent posts update to task's Discord thread
app.post(
  "/seldon/task/:taskId/thread-message",
  async (req: Request, res: Response) => {
    const { taskId } = req.params;
    const { agent_id, content, message_type } = req.body;

    if (!agent_id || !content) {
      res.status(400).json({ error: "agent_id and content are required" });
      return;
    }

    try {
      // Get task with thread info
      const taskResult = await pool.query(
        `SELECT id, discord_thread_id, participating_agents FROM tasks WHERE id = $1`,
        [taskId],
      );

      if (taskResult.rowCount === 0) {
        res.status(404).json({ error: `Task '${taskId}' not found` });
        return;
      }

      const task = taskResult.rows[0];
      const msgType = message_type || "work_update";

      // Post to Discord thread
      let discordMessageId: string | null = null;
      if (task.discord_thread_id) {
        discordMessageId = await postToTaskThread(
          task.discord_thread_id,
          agent_id,
          content,
          msgType,
        );
      }

      // Record in database
      const msgResult = await pool.query(
        `INSERT INTO discord_thread_messages
           (task_id, discord_thread_id, discord_message_id, agent_id, message_type, content)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, created_at`,
        [
          taskId,
          task.discord_thread_id || null,
          discordMessageId,
          agent_id,
          msgType,
          content,
        ],
      );

      // Add agent to participating_agents
      await pool
        .query(
          `UPDATE tasks SET participating_agents = array_append(participating_agents, $2),
           updated_at = NOW()
         WHERE id = $1 AND NOT ($2 = ANY(COALESCE(participating_agents, '{}')))`,
          [taskId, agent_id],
        )
        .catch(() => {});

      // Mark task as in_progress if still pending
      await pool
        .query(
          `UPDATE tasks SET status = 'in_progress', started_at = COALESCE(started_at, NOW()),
           updated_at = NOW()
         WHERE id = $1 AND status = 'pending'`,
          [taskId],
        )
        .catch(() => {});

      res.json({
        message_id: msgResult.rows[0].id,
        discord_message_id: discordMessageId,
        task_id: taskId,
        agent_id,
        message_type: msgType,
        posted_to_discord: !!discordMessageId,
        created_at: msgResult.rows[0].created_at,
      });
    } catch (err) {
      console.error("Failed to post thread message:", err);
      res.status(500).json({ error: "Failed to post thread message" });
    }
  },
);

// POST /seldon/task/:taskId/archive — Manually archive a task
app.post(
  "/seldon/task/:taskId/archive",
  async (req: Request, res: Response) => {
    const { taskId } = req.params;

    try {
      const taskResult = await pool.query(
        `SELECT id, status, discord_thread_id FROM tasks WHERE id = $1`,
        [taskId],
      );

      if (taskResult.rowCount === 0) {
        res.status(404).json({ error: `Task '${taskId}' not found` });
        return;
      }

      const task = taskResult.rows[0];

      if (task.status !== "completed" && task.status !== "failed") {
        res.status(400).json({
          error: "Can only archive completed or failed tasks",
          current_status: task.status,
        });
        return;
      }

      // Trigger immediate archival
      scheduleArchival(taskId, 0);

      res.json({
        archived: true,
        task_id: taskId,
        discord_thread_archived: !!task.discord_thread_id,
      });
    } catch (err) {
      console.error("Failed to archive task:", err);
      res.status(500).json({ error: "Failed to archive task" });
    }
  },
);

// GET /seldon/workflow/:workflowId — Get workflow status and step details
app.get("/seldon/workflow/:workflowId", async (req: Request, res: Response) => {
  const { workflowId } = req.params;

  try {
    const wfResult = await pool.query(
      `SELECT id, name, description, steps, status, current_step, result,
                error_message, created_by, created_at, updated_at, metadata
         FROM workflows WHERE id = $1`,
      [workflowId],
    );

    if (wfResult.rowCount === 0) {
      res.status(404).json({ error: `Workflow '${workflowId}' not found` });
      return;
    }

    const wf = wfResult.rows[0];
    const meta = wf.metadata || {};

    // Get subtasks created by this workflow
    const subtasksResult = await pool.query(
      `SELECT id, agent_id, name, status, created_at, completed_at, metadata
         FROM tasks
         WHERE metadata->>'workflow_id' = $1
         ORDER BY created_at ASC`,
      [workflowId],
    );

    // Merge in-memory state if available
    const activeState = activeWorkflows.get(workflowId);

    res.json({
      workflow: {
        id: wf.id,
        name: wf.name,
        status: wf.status,
        current_step: wf.current_step,
        steps: wf.steps,
        step_status: activeState?.stepStatus || meta.step_status || {},
        step_task_ids: activeState?.stepTaskIds || meta.step_task_ids || {},
        parent_task_id: meta.parent_task_id || null,
        template: meta.template || null,
        created_at: wf.created_at,
        updated_at: wf.updated_at,
      },
      subtasks: subtasksResult.rows,
      result: wf.result,
    });
  } catch (err) {
    console.error("Failed to get workflow:", err);
    res.status(500).json({ error: "Failed to get workflow" });
  }
});

// GET /seldon/workflows — List active workflows
app.get("/seldon/workflows", async (_req: Request, res: Response) => {
  try {
    const result = await pool.query(
      `SELECT id, name, status, current_step, created_by, created_at, updated_at, metadata
       FROM workflows
       ORDER BY created_at DESC
       LIMIT 50`,
    );

    res.json({
      workflows: result.rows.map((wf) => {
        const meta = wf.metadata || {};
        const activeState = activeWorkflows.get(wf.id);
        return {
          ...wf,
          step_status: activeState?.stepStatus || meta.step_status || {},
          parent_task_id: meta.parent_task_id || null,
          template: meta.template || null,
        };
      }),
      count: result.rowCount,
      active_in_memory: activeWorkflows.size,
    });
  } catch (err) {
    console.error("Failed to list workflows:", err);
    res.status(500).json({ error: "Failed to list workflows" });
  }
});

// POST /seldon/workflow/:workflowId/gate — Resolve a human gate in a workflow
app.post(
  "/seldon/workflow/:workflowId/gate",
  async (req: Request, res: Response) => {
    const { workflowId } = req.params;
    const { action, step_name } = req.body;
    // action: "done" | "skip" | "fail"

    const state = activeWorkflows.get(workflowId);
    if (!state) {
      res.status(404).json({
        error: `Workflow '${workflowId}' not found in active workflows`,
        hint: "Workflow may have completed or server may have restarted",
      });
      return;
    }

    // Find the gated step
    let gatedStep: WorkflowStep | undefined;
    if (step_name) {
      gatedStep = state.steps.find(
        (s) =>
          s.name === step_name && state.stepStatus[s.name] === "waiting_gate",
      );
    } else {
      // Find first waiting gate
      gatedStep = state.steps.find(
        (s) => state.stepStatus[s.name] === "waiting_gate",
      );
    }

    if (!gatedStep) {
      res.status(400).json({
        error: "No waiting gate found",
        step_status: state.stepStatus,
      });
      return;
    }

    const gateAction = (action || "done").toLowerCase();

    if (gateAction === "skip") {
      state.stepStatus[gatedStep.name] = "skipped";

      if (state.discordThreadId) {
        await postToTaskThread(
          state.discordThreadId,
          "seldon",
          `**Gate skipped: ${gatedStep.name}** — continuing workflow`,
          "status",
        );
      }
    } else if (gateAction === "fail") {
      state.stepStatus[gatedStep.name] = "failed";

      if (state.discordThreadId) {
        await postToTaskThread(
          state.discordThreadId,
          "seldon",
          `**Gate failed: ${gatedStep.name}** — workflow may not complete`,
          "veto",
        );
      }
    } else {
      // "done" — gate resolved
      state.stepStatus[gatedStep.name] = "completed";

      if (state.discordThreadId) {
        await postToTaskThread(
          state.discordThreadId,
          "seldon",
          `**Gate resolved: ${gatedStep.name}** — continuing workflow`,
          "approval",
        );
      }
    }

    // Update DB
    await pool.query(
      `UPDATE workflows SET metadata = jsonb_set(
         COALESCE(metadata, '{}'::jsonb), '{step_status}', $2::jsonb),
         updated_at = NOW() WHERE id = $1`,
      [workflowId, JSON.stringify(state.stepStatus)],
    );

    // Advance workflow
    await advanceWorkflow(workflowId);

    res.json({
      workflow_id: workflowId,
      gate_step: gatedStep.name,
      action: gateAction,
      step_status: state.stepStatus,
    });
  },
);

// POST /seldon/workflow/:workflowId/step/:stepName/fail — Mark a workflow step as failed
app.post(
  "/seldon/workflow/:workflowId/step/:stepName/fail",
  async (req: Request, res: Response) => {
    const { workflowId, stepName } = req.params;
    const { reason } = req.body;

    const state = activeWorkflows.get(workflowId);
    if (!state) {
      res.status(404).json({
        error: `Workflow '${workflowId}' not found in active workflows`,
      });
      return;
    }

    const step = state.steps.find((s) => s.name === stepName);
    if (!step) {
      res
        .status(404)
        .json({ error: `Step '${stepName}' not found in workflow` });
      return;
    }

    if (step.optional) {
      state.stepStatus[stepName] = "skipped";
    } else {
      state.stepStatus[stepName] = "failed";
    }

    // Update DB
    await pool.query(
      `UPDATE workflows SET metadata = jsonb_set(
         COALESCE(metadata, '{}'::jsonb), '{step_status}', $2::jsonb),
         updated_at = NOW() WHERE id = $1`,
      [workflowId, JSON.stringify(state.stepStatus)],
    );

    if (state.discordThreadId) {
      await postToTaskThread(
        state.discordThreadId,
        step.agent,
        `**Step ${step.optional ? "skipped" : "failed"}: ${stepName}**${reason ? `\nReason: ${reason}` : ""}`,
        step.optional ? "status" : "veto",
      );
    }

    // Try to advance (may complete with failures)
    await advanceWorkflow(workflowId);

    res.json({
      workflow_id: workflowId,
      step: stepName,
      status: state.stepStatus[stepName],
      reason: reason || null,
    });
  },
);

// GET /dashboard — Serve the Command Center dashboard
app.get("/dashboard", (_req: Request, res: Response) => {
  const dashboardPath = path.resolve(
    __dirname,
    "..",
    "dashboard",
    "index.html",
  );
  if (fs.existsSync(dashboardPath)) {
    res.sendFile(dashboardPath);
  } else {
    res
      .status(404)
      .json({ error: "Dashboard not found. Expected at dashboard/index.html" });
  }
});

// GET /seldon/divisions — Return division structure
app.get("/seldon/divisions", (_req: Request, res: Response) => {
  const divisionsPath =
    process.env.DIVISIONS_PATH ||
    path.resolve(__dirname, "config", "divisions.json");
  try {
    const raw = fs.readFileSync(divisionsPath, "utf-8");
    const data = JSON.parse(raw);
    res.json(data);
  } catch {
    res.status(500).json({ error: "Failed to read divisions config" });
  }
});

// GET /seldon/status — Aggregate system status
app.get("/seldon/status", async (_req: Request, res: Response) => {
  try {
    // Agent counts
    const agentResult = await pool.query(
      `SELECT status, COUNT(*) as count FROM agents GROUP BY status`,
    );
    const statusCounts: Record<string, number> = {};
    let totalAgents = 0;
    for (const row of agentResult.rows) {
      statusCounts[row.status] = parseInt(row.count, 10);
      totalAgents += parseInt(row.count, 10);
    }

    // Recent heartbeats (online = heartbeat within last 60s)
    const onlineResult = await pool.query(
      `SELECT COUNT(*) as count FROM agents WHERE last_heartbeat > NOW() - INTERVAL '60 seconds'`,
    );
    const onlineCount = parseInt(onlineResult.rows[0]?.count || "0", 10);

    // Division counts
    const divisionPath =
      process.env.DIVISIONS_PATH ||
      path.resolve(__dirname, "config", "divisions.json");
    let divisions: Record<string, unknown> = {};
    try {
      const raw = fs.readFileSync(divisionPath, "utf-8");
      divisions = JSON.parse(raw).divisions || {};
    } catch {
      // divisions unavailable
    }

    // Task stats
    const taskResult = await pool.query(
      `SELECT status, COUNT(*) as count FROM tasks GROUP BY status`,
    );
    const taskCounts: Record<string, number> = {};
    for (const row of taskResult.rows) {
      taskCounts[row.status] = parseInt(row.count, 10);
    }

    // Handoff stats
    const handoffResult = await pool.query(
      `SELECT status, COUNT(*) as count FROM handoffs GROUP BY status`,
    );
    const handoffCounts: Record<string, number> = {};
    for (const row of handoffResult.rows) {
      handoffCounts[row.status] = parseInt(row.count, 10);
    }

    // Service health (basic check: can we query the DB?)
    const services = [
      {
        name: "PostgreSQL",
        container: "openclaw-postgres",
        healthy: true,
        port: 5434,
      },
      {
        name: "Seldon Protocol",
        container: "openclaw-core",
        healthy: true,
        port: PORT,
      },
    ];

    res.json({
      agents: {
        total: totalAgents,
        online: onlineCount,
        by_status: statusCounts,
      },
      divisions: Object.keys(divisions).length,
      tasks: taskCounts,
      handoffs: handoffCounts,
      services,
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    console.error("Failed to get status:", err);
    res.status(500).json({ error: "Failed to get system status" });
  }
});

app.listen(PORT, () => {
  console.log(`Seldon Protocol listening on port ${PORT}`);
});
