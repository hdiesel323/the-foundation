/**
 * Foundation Router — 5-Signal Scoring Engine
 *
 * Automatically assigns incoming messages to the best agent using:
 *   1. Keyword scoring   (40% weight) — TF-IDF style per-keyword weights
 *   2. Intent matching    (30% weight) — Jaccard similarity against agent intents
 *   3. Direct mention     (20% weight) — Agent name/alias detection
 *   4. Division affinity  (10% weight) — Route to owning division
 *   5. Negative keywords  (penalty)    — Subtract for keywords agent should NOT handle
 *
 * Formula:
 *   score = (keywordScore * 0.4) + (intentScore * 0.3) + (mentionScore * 0.2) + (divisionScore * 0.1) - negativePenalty
 *   finalScore = score * outcomeMultiplier  // 0.7x to 1.3x from Outcome Tracker
 */

// ── Types ──────────────────────────────────────────────────────────────

export interface AgentProfile {
  id: string;
  name: string;
  aliases: string[];
  role: string;
  division: string;
  keywords: KeywordEntry[];
  intents: string[];
  negativeKeywords: string[];
  outcomeMultiplier: number; // 0.7–1.3, default 1.0
}

export interface KeywordEntry {
  word: string;
  weight: number; // TF-IDF style weight, 0.0–1.0
}

export interface RoutingMessage {
  text: string;
  intents?: string[];       // Pre-classified intents (if available)
  division?: string;        // Explicit division hint (if available)
  context?: Record<string, unknown>;
}

export interface ScoredAgent {
  agentId: string;
  keywordScore: number;
  intentScore: number;
  mentionScore: number;
  divisionScore: number;
  negativePenalty: number;
  rawScore: number;
  finalScore: number;
  outcomeMultiplier: number;
}

export interface RoutingResult {
  bestAgent: ScoredAgent | null;
  allScores: ScoredAgent[];
  message: string;
}

// ── Signal Weights ─────────────────────────────────────────────────────

const KEYWORD_WEIGHT = 0.4;
const INTENT_WEIGHT = 0.3;
const MENTION_WEIGHT = 0.2;
const DIVISION_WEIGHT = 0.1;

// ── Signal 1: Keyword Scoring (40%) ────────────────────────────────────

/**
 * TF-IDF style keyword scoring. Each agent registers keywords with weights.
 * Score = sum of matched keyword weights / sum of all keyword weights.
 * Normalized to 0.0–1.0.
 */
function computeKeywordScore(message: string, agent: AgentProfile): number {
  if (agent.keywords.length === 0) return 0;

  const messageLower = message.toLowerCase();
  const words = messageLower.split(/\s+/);

  let matchedWeight = 0;
  let totalWeight = 0;

  for (const entry of agent.keywords) {
    totalWeight += entry.weight;
    // Check for word presence (supports multi-word keywords)
    if (messageLower.includes(entry.word.toLowerCase())) {
      matchedWeight += entry.weight;
    }
  }

  if (totalWeight === 0) return 0;
  return matchedWeight / totalWeight;
}

// ── Signal 2: Intent Matching (30%) ────────────────────────────────────

/**
 * Jaccard similarity between message intents and agent intents.
 * |intersection| / |union|
 * Returns 0.0–1.0.
 */
function computeIntentScore(messageIntents: string[], agent: AgentProfile): number {
  if (messageIntents.length === 0 || agent.intents.length === 0) return 0;

  const messageSet = new Set(messageIntents.map(i => i.toLowerCase()));
  const agentSet = new Set(agent.intents.map(i => i.toLowerCase()));

  let intersection = 0;
  for (const intent of messageSet) {
    if (agentSet.has(intent)) {
      intersection++;
    }
  }

  const union = new Set([...messageSet, ...agentSet]).size;
  if (union === 0) return 0;

  return intersection / union;
}

// ── Signal 3: Direct Mention Detection (20%) ───────────────────────────

/**
 * Checks if the message explicitly mentions an agent by name or alias.
 * Returns 1.0 if mentioned, 0.0 otherwise.
 */
function computeMentionScore(message: string, agent: AgentProfile): number {
  const messageLower = message.toLowerCase();
  const namesToCheck = [agent.id, agent.name, ...agent.aliases].map(n => n.toLowerCase());

  for (const name of namesToCheck) {
    // Word boundary check: the name must appear as a distinct word
    const regex = new RegExp(`\\b${escapeRegex(name)}\\b`, 'i');
    if (regex.test(message)) {
      return 1.0;
    }
  }

  return 0.0;
}

/**
 * Escape special regex characters in a string.
 */
function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// ── Signal 4: Division Affinity (10%) ──────────────────────────────────

/**
 * Returns 1.0 if the message's division hint matches the agent's division.
 * Returns 0.0 otherwise.
 */
function computeDivisionScore(messageDivision: string | undefined, agent: AgentProfile): number {
  if (!messageDivision) return 0;
  return messageDivision.toLowerCase() === agent.division.toLowerCase() ? 1.0 : 0.0;
}

// ── Signal 5: Negative Keyword Penalty ─────────────────────────────────

/**
 * Checks for negative keywords — topics the agent should NOT handle.
 * Returns a penalty value (0.0–1.0) that is subtracted from the score.
 * Each matched negative keyword adds 0.2 penalty, capped at 1.0.
 */
function computeNegativePenalty(message: string, agent: AgentProfile): number {
  if (agent.negativeKeywords.length === 0) return 0;

  const messageLower = message.toLowerCase();
  let penalty = 0;

  for (const negWord of agent.negativeKeywords) {
    if (messageLower.includes(negWord.toLowerCase())) {
      penalty += 0.2;
    }
  }

  return Math.min(penalty, 1.0);
}

// ── Main Scoring Engine ────────────────────────────────────────────────

/**
 * Score a single agent against a message.
 * Returns a ScoredAgent with all signal breakdowns.
 */
export function scoreAgent(message: RoutingMessage, agent: AgentProfile): ScoredAgent {
  const keywordScore = computeKeywordScore(message.text, agent);
  const intentScore = computeIntentScore(message.intents ?? [], agent);
  const mentionScore = computeMentionScore(message.text, agent);
  const divisionScore = computeDivisionScore(message.division, agent);
  const negativePenalty = computeNegativePenalty(message.text, agent);

  const rawScore =
    (keywordScore * KEYWORD_WEIGHT) +
    (intentScore * INTENT_WEIGHT) +
    (mentionScore * MENTION_WEIGHT) +
    (divisionScore * DIVISION_WEIGHT) -
    negativePenalty;

  const multiplier = Math.max(0.7, Math.min(1.3, agent.outcomeMultiplier));
  const finalScore = rawScore * multiplier;

  return {
    agentId: agent.id,
    keywordScore,
    intentScore,
    mentionScore,
    divisionScore,
    negativePenalty,
    rawScore,
    finalScore,
    outcomeMultiplier: multiplier,
  };
}

/**
 * Route a message to the best agent from a pool.
 * Returns all scores sorted descending, with the best agent highlighted.
 */
export function routeMessage(message: RoutingMessage, agents: AgentProfile[]): RoutingResult {
  const allScores = agents
    .map(agent => scoreAgent(message, agent))
    .sort((a, b) => b.finalScore - a.finalScore);

  const bestAgent = allScores.length > 0 && allScores[0].finalScore > 0
    ? allScores[0]
    : null;

  return {
    bestAgent,
    allScores,
    message: message.text,
  };
}
