import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";

// ============================================================
// Alpaca Trading MCP Server
//
// Provides trading tools for the Alpaca paper/live trading API.
// Used by trader agent for position management and order execution.
// ============================================================

const API_KEY = process.env.ALPACA_API_KEY || "";
const SECRET_KEY = process.env.ALPACA_SECRET_KEY || "";
const ENDPOINT =
  process.env.ALPACA_ENDPOINT || "https://paper-api.alpaca.markets/v2";

const headers = {
  "APCA-API-KEY-ID": API_KEY,
  "APCA-API-SECRET-KEY": SECRET_KEY,
  "Content-Type": "application/json",
};

async function alpacaGet(path: string): Promise<unknown> {
  const res = await fetch(`${ENDPOINT}${path}`, { headers });
  if (!res.ok) throw new Error(`Alpaca API error: ${res.status} ${await res.text()}`);
  return res.json();
}

async function alpacaPost(path: string, body: unknown): Promise<unknown> {
  const res = await fetch(`${ENDPOINT}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Alpaca API error: ${res.status} ${await res.text()}`);
  return res.json();
}

async function alpacaDelete(path: string): Promise<unknown> {
  const res = await fetch(`${ENDPOINT}${path}`, { method: "DELETE", headers });
  if (!res.ok && res.status !== 204) {
    throw new Error(`Alpaca API error: ${res.status} ${await res.text()}`);
  }
  return res.status === 204 ? { status: "cancelled" } : res.json();
}

const server = new McpServer({
  name: "openclaw-alpaca",
  version: "0.1.0",
});

// ============================================================
// Tool: get_positions
// ============================================================
server.registerTool("get_positions", {
  description:
    "Get current portfolio positions. Returns all open positions with " +
    "current market value, unrealized P&L, and quantity.",
  inputSchema: {
    symbol: z
      .string()
      .optional()
      .describe("Filter by symbol (e.g. 'AAPL'). Omit for all positions."),
  },
  annotations: { readOnlyHint: true },
}, async ({ symbol }) => {
  const path = symbol ? `/positions/${symbol}` : "/positions";
  const data = await alpacaGet(path);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Tool: place_order
// ============================================================
server.registerTool("place_order", {
  description:
    "Place a new order or cancel an existing order. Supports market, limit, " +
    "stop, and stop-limit order types. Use action 'cancel' to cancel an order.",
  inputSchema: {
    action: z.enum(["buy", "sell", "cancel"]).describe("Order action"),
    symbol: z.string().describe("Ticker symbol (e.g. 'AAPL')"),
    qty: z.number().optional().describe("Number of shares"),
    order_type: z
      .enum(["market", "limit", "stop", "stop_limit"])
      .optional()
      .describe("Order type (default: market)"),
    limit_price: z.number().optional().describe("Limit price for limit/stop-limit orders"),
    stop_price: z.number().optional().describe("Stop price for stop/stop-limit orders"),
    time_in_force: z
      .enum(["day", "gtc", "ioc", "fok"])
      .optional()
      .describe("Time in force (default: day)"),
    order_id: z.string().optional().describe("Order ID to cancel (required for cancel action)"),
  },
}, async ({ action, symbol, qty, order_type, limit_price, stop_price, time_in_force, order_id }) => {
  if (action === "cancel") {
    if (!order_id) throw new Error("order_id required for cancel action");
    const data = await alpacaDelete(`/orders/${order_id}`);
    return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
  }

  const body: Record<string, unknown> = {
    symbol,
    qty: qty || 1,
    side: action,
    type: order_type || "market",
    time_in_force: time_in_force || "day",
  };
  if (limit_price) body.limit_price = limit_price;
  if (stop_price) body.stop_price = stop_price;

  const data = await alpacaPost("/orders", body);
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
});

// ============================================================
// Tool: get_portfolio
// ============================================================
server.registerTool("get_portfolio", {
  description:
    "Get portfolio summary including total equity, buying power, cash, " +
    "and daily P&L. Also returns portfolio history if period specified.",
  inputSchema: {
    period: z
      .string()
      .optional()
      .describe("History period: '1D', '1W', '1M', '3M', '1A'. Omit for current snapshot."),
  },
  annotations: { readOnlyHint: true },
}, async ({ period }) => {
  const account = await alpacaGet("/account");

  if (period) {
    const history = await alpacaGet(
      `/account/portfolio/history?period=${period}&timeframe=1D`
    );
    return {
      content: [
        { type: "text" as const, text: JSON.stringify({ account, history }, null, 2) },
      ],
    };
  }

  return { content: [{ type: "text" as const, text: JSON.stringify(account, null, 2) }] };
});

// ============================================================
// Tool: get_account
// ============================================================
server.registerTool("get_account", {
  description:
    "Get Alpaca account details: status, buying power, equity, cash, " +
    "pattern day trader flag, and trading permissions.",
  inputSchema: {},
  annotations: { readOnlyHint: true },
}, async () => {
  const data = await alpacaGet("/account");
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
