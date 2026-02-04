// ============================================================
// Learning Review Patrol
//
// Runs periodically during agent heartbeat to review captured
// learnings, identify recurring patterns, and promote insights.
// ============================================================

import type { PatrolFinding } from "../base-runner.js";
import fs from "node:fs";
import path from "node:path";

const OPENCLAW_DIR = process.env.OPENCLAW_DIR || "/opt/openclaw";
const LEARNINGS_FILE = path.join(OPENCLAW_DIR, ".learnings", "LEARNINGS.md");
const CONFIG_FILE = path.join(OPENCLAW_DIR, "config", "learning-review.json");

interface LearningEntry {
  id: string;
  category: string;
  priority: string;
  area: string;
  summary: string;
  status: string;
  timestamp?: string;
}

interface ReviewConfig {
  review_interval_hours: number;
  pattern_detection: {
    recurring_threshold: number;
    lookback_days: number;
  };
}

function loadConfig(): ReviewConfig {
  const defaults: ReviewConfig = {
    review_interval_hours: 72,
    pattern_detection: {
      recurring_threshold: 2,
      lookback_days: 30,
    },
  };

  try {
    const raw = fs.readFileSync(CONFIG_FILE, "utf-8");
    const cfg = JSON.parse(raw);
    return { ...defaults, ...cfg.learning_review };
  } catch {
    return defaults;
  }
}

function parseLearnings(): LearningEntry[] {
  if (!fs.existsSync(LEARNINGS_FILE)) return [];

  const content = fs.readFileSync(LEARNINGS_FILE, "utf-8");
  const entries: LearningEntry[] = [];
  const blocks = content.split("---").filter((b) => b.includes("id:"));

  for (const block of blocks) {
    const idMatch = block.match(/id:\s*(\S+)/);
    const catMatch = block.match(/category:\s*(\S+)/);
    const prioMatch = block.match(/priority:\s*(\S+)/);
    const areaMatch = block.match(/area:\s*(\S+)/);
    const sumMatch = block.match(/summary:\s*"([^"]+)"/);
    const statMatch = block.match(/status:\s*(\S+)/);

    if (idMatch) {
      entries.push({
        id: idMatch[1],
        category: catMatch?.[1] || "unknown",
        priority: prioMatch?.[1] || "medium",
        area: areaMatch?.[1] || "cross-cutting",
        summary: sumMatch?.[1] || "No summary",
        status: statMatch?.[1] || "pending",
      });
    }
  }

  return entries;
}

/**
 * Identify recurring patterns in learnings.
 * Groups by command prefix and checks for threshold.
 */
function findRecurringPatterns(
  entries: LearningEntry[],
  threshold: number
): Map<string, LearningEntry[]> {
  const groups = new Map<string, LearningEntry[]>();

  for (const entry of entries) {
    // Extract command from summary (e.g., "Command failed: docker compose ...")
    const cmdMatch = entry.summary.match(/Command failed:\s*(\S+(?:\s+\S+)?)/);
    const key = cmdMatch ? cmdMatch[1] : entry.area;

    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(entry);
  }

  // Filter to recurring only
  const recurring = new Map<string, LearningEntry[]>();
  for (const [key, group] of groups) {
    if (group.length >= threshold) {
      recurring.set(key, group);
    }
  }

  return recurring;
}

/**
 * Review pending learnings and generate findings.
 */
export async function reviewLearnings(): Promise<PatrolFinding[]> {
  const config = loadConfig();
  const entries = parseLearnings();
  const findings: PatrolFinding[] = [];

  if (entries.length === 0) return findings;

  // Count by status
  const statusCounts = new Map<string, number>();
  for (const entry of entries) {
    statusCounts.set(entry.status, (statusCounts.get(entry.status) || 0) + 1);
  }

  const pendingCount = statusCounts.get("pending") || 0;
  const capturedCount = statusCounts.get("captured") || 0;

  // Finding: unreviewed learnings
  if (pendingCount + capturedCount > 5) {
    findings.push({
      subject: "learning_review",
      predicate: "has_unreviewed",
      description: `${pendingCount + capturedCount} unreviewed learnings need attention`,
      severity: "info",
      ttl: 86400,
    });
  }

  // Finding: critical pending items
  const criticalPending = entries.filter(
    (e) => e.priority === "critical" && (e.status === "pending" || e.status === "captured")
  );
  if (criticalPending.length > 0) {
    findings.push({
      subject: "learning_review",
      predicate: "has_critical_pending",
      description: `${criticalPending.length} critical learning(s) need immediate review: ${criticalPending.map((e) => e.id).join(", ")}`,
      severity: "warning",
      ttl: 3600,
    });
  }

  // Finding: recurring patterns
  const recurring = findRecurringPatterns(
    entries.filter((e) => e.category === "error_recovery"),
    config.pattern_detection.recurring_threshold
  );

  for (const [pattern, group] of recurring) {
    findings.push({
      subject: "learning_review",
      predicate: "recurring_pattern_detected",
      description: `Recurring failure pattern '${pattern}' (${group.length}x) — recommend skill extraction`,
      severity: "warning",
      ttl: 86400,
    });
  }

  return findings;
}

export default reviewLearnings;
