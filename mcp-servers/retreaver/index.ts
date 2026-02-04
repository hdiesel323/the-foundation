import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";

// ============================================================
// Retreaver MCP Server
//
// Provides call tracking and lead gen tools via the Retreaver API.
// Used by preem and mallow agents for campaign performance tracking.
// ============================================================

const API_KEY = process.env.RETREAVER_API_KEY || "";
const ENDPOINT =
  process.env.RETREAVER_ENDPOINT || "https://api.retreaver.com/v1";

const headers = {
  Authorization: `Bearer ${API_KEY}`,
  "Content-Type": "application/json",
};

async function retreaver(
  method: string,
  path: string,
  body?: unknown
): Promise<unknown> {
  const opts: RequestInit = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${ENDPOINT}${path}`, opts);
  if (!res.ok)
    throw new Error(`Retreaver API error: ${res.status} ${await res.text()}`);
  return res.json();
}

const server = new McpServer({
  name: "openclaw-retreaver",
  version: "0.1.0",
});

// ============================================================
// Tool: get_campaigns
// ============================================================
server.registerTool("get_campaigns", {
  description:
    "List Retreaver campaigns with performance metrics. Returns campaign " +
    "name, status, number pool, and routing rules.",
  inputSchema: {
    status: z
      .enum(["active", "paused", "all"])
      .optional()
      .describe("Filter by status (default: active)"),
    limit: z.number().optional().describe("Max results (default: 50)"),
  },
  annotations: { readOnlyHint: true },
}, async ({ status, limit }) => {
  const params = new URLSearchParams();
  if (status && status !== "all") params.set("status", status);
  params.set("limit", String(limit || 50));
  const data = await retreaver("GET", `/campaigns?${params}`);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Tool: get_buyers
// ============================================================
server.registerTool("get_buyers", {
  description:
    "List buyer accounts with bid settings, call caps, and routing priority. " +
    "Buyers are the entities purchasing leads/calls.",
  inputSchema: {
    campaign_id: z.string().optional().describe("Filter by campaign ID"),
    active_only: z.boolean().optional().describe("Only active buyers (default: true)"),
  },
  annotations: { readOnlyHint: true },
}, async ({ campaign_id, active_only }) => {
  const params = new URLSearchParams();
  if (campaign_id) params.set("campaign_id", campaign_id);
  if (active_only !== false) params.set("active", "true");
  const data = await retreaver("GET", `/buyers?${params}`);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Tool: get_call_log
// ============================================================
server.registerTool("get_call_log", {
  description:
    "Query call tracking logs with filtering by date range, campaign, " +
    "buyer, duration, and disposition. Returns call details with revenue.",
  inputSchema: {
    campaign_id: z.string().optional().describe("Filter by campaign ID"),
    buyer_id: z.string().optional().describe("Filter by buyer ID"),
    start_date: z.string().optional().describe("Start date (YYYY-MM-DD)"),
    end_date: z.string().optional().describe("End date (YYYY-MM-DD)"),
    min_duration: z.number().optional().describe("Minimum call duration in seconds"),
    limit: z.number().optional().describe("Max results (default: 100)"),
  },
  annotations: { readOnlyHint: true },
}, async ({ campaign_id, buyer_id, start_date, end_date, min_duration, limit }) => {
  const params = new URLSearchParams();
  if (campaign_id) params.set("campaign_id", campaign_id);
  if (buyer_id) params.set("buyer_id", buyer_id);
  if (start_date) params.set("start_date", start_date);
  if (end_date) params.set("end_date", end_date);
  if (min_duration) params.set("min_duration", String(min_duration));
  params.set("limit", String(limit || 100));
  const data = await retreaver("GET", `/calls?${params}`);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Tool: get_revenue
// ============================================================
server.registerTool("get_revenue", {
  description:
    "Get revenue attribution and performance metrics. Aggregates revenue " +
    "by campaign, buyer, time period, or source with trend analysis.",
  inputSchema: {
    group_by: z
      .enum(["campaign", "buyer", "source", "day", "week", "month"])
      .optional()
      .describe("Group revenue by dimension (default: campaign)"),
    campaign_id: z.string().optional().describe("Filter by campaign ID"),
    start_date: z.string().optional().describe("Start date (YYYY-MM-DD)"),
    end_date: z.string().optional().describe("End date (YYYY-MM-DD)"),
  },
  annotations: { readOnlyHint: true },
}, async ({ group_by, campaign_id, start_date, end_date }) => {
  const params = new URLSearchParams();
  params.set("group_by", group_by || "campaign");
  if (campaign_id) params.set("campaign_id", campaign_id);
  if (start_date) params.set("start_date", start_date);
  if (end_date) params.set("end_date", end_date);
  const data = await retreaver("GET", `/reports/revenue?${params}`);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Start server
// ============================================================
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
