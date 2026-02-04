import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";
import pg from "pg";

const { Pool } = pg;

const pool = new Pool({
  connectionString:
    process.env.DATABASE_URL ||
    "postgresql://openclaw:CHANGE_ME_openclaw_db_password@localhost:5434/openclaw",
});

const server = new McpServer({
  name: "openclaw-memory",
  version: "0.1.0",
});

server.registerTool("memory_store", {
  description:
    "Store a preference, fact, or context entry in OpenClaw memory. " +
    "Type 'preference' stores to the preferences table, 'fact' stores to the facts table, " +
    "'context' stores to the conversations table as a context summary.",
  inputSchema: {
    type: z.enum(["preference", "fact", "context"]).describe(
      "Type of memory entry to store"
    ),
    category: z.string().describe("Category for grouping (e.g. 'ui', 'workflow', 'security')"),
    key: z.string().describe("Key or subject identifier for the memory entry"),
    value: z.string().describe("The value or content to store"),
    agent_id: z.string().optional().describe("Agent ID (defaults to 'shared')"),
  },
}, async ({ type, category, key, value, agent_id }) => {
  const agentId = agent_id || "shared";

  try {
    let result;

    if (type === "preference") {
      result = await pool.query(
        `INSERT INTO preferences (agent_id, category, key, value)
         VALUES ($1, $2, $3, $4::jsonb)
         ON CONFLICT (agent_id, category, key)
         DO UPDATE SET value = $4::jsonb, version = preferences.version + 1, updated_at = NOW()
         RETURNING id, agent_id, category, key, value, version`,
        [agentId, category, key, JSON.stringify(value)]
      );
    } else if (type === "fact") {
      result = await pool.query(
        `INSERT INTO facts (agent_id, category, subject, predicate, object)
         VALUES ($1, $2, $3, 'is', $4)
         RETURNING id, agent_id, category, subject, predicate, object, confidence`,
        [agentId, category, key, value]
      );
    } else {
      // context — store as a conversation context summary
      result = await pool.query(
        `INSERT INTO conversations (agent_id, title, context_summary, metadata)
         VALUES ($1, $2, $3, $4::jsonb)
         RETURNING id, agent_id, title, context_summary`,
        [agentId, key, value, JSON.stringify({ category })]
      );
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            { stored: true, type, entry: result.rows[0] },
            null,
            2
          ),
        },
      ],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text" as const, text: `Error storing memory: ${message}` }],
      isError: true,
    };
  }
});

server.registerTool("memory_retrieve", {
  description:
    "Retrieve memories from OpenClaw memory by type and category. " +
    "Type 'preference' queries the preferences table, 'fact' queries the facts table, " +
    "'context' queries the conversations table.",
  inputSchema: {
    type: z.enum(["preference", "fact", "context"]).describe(
      "Type of memory entry to retrieve"
    ),
    category: z.string().optional().describe("Category to filter by (optional)"),
    key: z.string().optional().describe("Specific key or subject to retrieve (optional)"),
    agent_id: z.string().optional().describe("Agent ID to filter by (defaults to 'shared')"),
    limit: z.number().optional().describe("Maximum number of results (defaults to 50)"),
  },
}, async ({ type, category, key, agent_id, limit }) => {
  const agentId = agent_id || "shared";
  const maxResults = limit || 50;

  try {
    let result;

    if (type === "preference") {
      const conditions: string[] = ["agent_id = $1"];
      const params: (string | number)[] = [agentId];
      let paramIdx = 2;

      if (category) {
        conditions.push(`category = $${paramIdx}`);
        params.push(category);
        paramIdx++;
      }
      if (key) {
        conditions.push(`key = $${paramIdx}`);
        params.push(key);
        paramIdx++;
      }
      params.push(maxResults);

      result = await pool.query(
        `SELECT id, agent_id, category, key, value, version, created_at, updated_at
         FROM preferences
         WHERE ${conditions.join(" AND ")}
         ORDER BY updated_at DESC
         LIMIT $${paramIdx}`,
        params
      );
    } else if (type === "fact") {
      const conditions: string[] = ["agent_id = $1"];
      const params: (string | number)[] = [agentId];
      let paramIdx = 2;

      if (category) {
        conditions.push(`category = $${paramIdx}`);
        params.push(category);
        paramIdx++;
      }
      if (key) {
        conditions.push(`subject = $${paramIdx}`);
        params.push(key);
        paramIdx++;
      }
      params.push(maxResults);

      result = await pool.query(
        `SELECT id, agent_id, category, subject, predicate, object, confidence, source, valid_from, valid_until, created_at
         FROM facts
         WHERE ${conditions.join(" AND ")}
         ORDER BY created_at DESC
         LIMIT $${paramIdx}`,
        params
      );
    } else {
      // context — query conversations
      const conditions: string[] = ["agent_id = $1"];
      const params: (string | number)[] = [agentId];
      let paramIdx = 2;

      if (category) {
        conditions.push(`metadata->>'category' = $${paramIdx}`);
        params.push(category);
        paramIdx++;
      }
      if (key) {
        conditions.push(`title = $${paramIdx}`);
        params.push(key);
        paramIdx++;
      }
      params.push(maxResults);

      result = await pool.query(
        `SELECT id, agent_id, title, context_summary, status, started_at, last_activity_at, metadata
         FROM conversations
         WHERE ${conditions.join(" AND ")}
         ORDER BY last_activity_at DESC
         LIMIT $${paramIdx}`,
        params
      );
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            { type, count: result.rows.length, entries: result.rows },
            null,
            2
          ),
        },
      ],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text" as const, text: `Error retrieving memory: ${message}` }],
      isError: true,
    };
  }
});

server.registerTool("memory_search", {
  description:
    "Search across all memory types (preferences, facts, conversations) using keyword matching. " +
    "Searches values, subjects, objects, titles, and context summaries.",
  inputSchema: {
    query: z.string().describe("Search keyword or phrase to match against memory entries"),
    type: z.enum(["preference", "fact", "context", "all"]).optional().describe(
      "Limit search to a specific type, or 'all' to search everything (default: 'all')"
    ),
    agent_id: z.string().optional().describe("Agent ID to filter by (defaults to 'shared')"),
    limit: z.number().optional().describe("Maximum number of results per type (defaults to 20)"),
  },
}, async ({ query, type, agent_id, limit }) => {
  const agentId = agent_id || "shared";
  const searchType = type || "all";
  const maxResults = limit || 20;
  const searchPattern = `%${query}%`;

  try {
    const results: { type: string; entries: Record<string, unknown>[] }[] = [];

    if (searchType === "all" || searchType === "preference") {
      const prefResult = await pool.query(
        `SELECT id, agent_id, category, key, value, version, updated_at
         FROM preferences
         WHERE agent_id = $1
           AND (key ILIKE $2 OR value::text ILIKE $2 OR category ILIKE $2)
         ORDER BY updated_at DESC
         LIMIT $3`,
        [agentId, searchPattern, maxResults]
      );
      results.push({ type: "preference", entries: prefResult.rows });
    }

    if (searchType === "all" || searchType === "fact") {
      const factResult = await pool.query(
        `SELECT id, agent_id, category, subject, predicate, object, confidence, created_at
         FROM facts
         WHERE agent_id = $1
           AND (subject ILIKE $2 OR object ILIKE $2 OR category ILIKE $2)
         ORDER BY created_at DESC
         LIMIT $3`,
        [agentId, searchPattern, maxResults]
      );
      results.push({ type: "fact", entries: factResult.rows });
    }

    if (searchType === "all" || searchType === "context") {
      const ctxResult = await pool.query(
        `SELECT id, agent_id, title, context_summary, status, last_activity_at
         FROM conversations
         WHERE agent_id = $1
           AND (title ILIKE $2 OR context_summary ILIKE $2)
         ORDER BY last_activity_at DESC
         LIMIT $3`,
        [agentId, searchPattern, maxResults]
      );
      results.push({ type: "context", entries: ctxResult.rows });
    }

    const totalCount = results.reduce((sum, r) => sum + r.entries.length, 0);

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            { query, total_matches: totalCount, results },
            null,
            2
          ),
        },
      ],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text" as const, text: `Error searching memory: ${message}` }],
      isError: true,
    };
  }
});

server.registerTool("memory_delete", {
  description:
    "Delete a memory entry by its UUID. Specify the type (preference, fact, context) " +
    "and the entry's ID to remove it permanently.",
  inputSchema: {
    type: z.enum(["preference", "fact", "context"]).describe(
      "Type of memory entry to delete"
    ),
    id: z.string().describe("UUID of the entry to delete"),
  },
}, async ({ type, id }) => {
  try {
    const table =
      type === "preference" ? "preferences" :
      type === "fact" ? "facts" :
      "conversations";

    const result = await pool.query(
      `DELETE FROM ${table} WHERE id = $1 RETURNING id`,
      [id]
    );

    if (result.rowCount === 0) {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ deleted: false, reason: "Entry not found", type, id }),
          },
        ],
      };
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify({ deleted: true, type, id }, null, 2),
        },
      ],
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text" as const, text: `Error deleting memory: ${message}` }],
      isError: true,
    };
  }
});

server.registerTool("memory_list", {
  description:
    "List memory entries grouped by category. Shows available categories and entry counts, " +
    "or lists entries within a specific category.",
  inputSchema: {
    type: z.enum(["preference", "fact", "context"]).describe(
      "Type of memory entries to list"
    ),
    category: z.string().optional().describe("Category to list entries from (omit to list all categories with counts)"),
    agent_id: z.string().optional().describe("Agent ID to filter by (defaults to 'shared')"),
    limit: z.number().optional().describe("Maximum number of results (defaults to 50)"),
  },
}, async ({ type, category, agent_id, limit }) => {
  const agentId = agent_id || "shared";
  const maxResults = limit || 50;

  try {
    if (type === "preference") {
      if (category) {
        const result = await pool.query(
          `SELECT id, agent_id, category, key, value, version, updated_at
           FROM preferences
           WHERE agent_id = $1 AND category = $2
           ORDER BY key ASC
           LIMIT $3`,
          [agentId, category, maxResults]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, category, count: result.rows.length, entries: result.rows }, null, 2),
          }],
        };
      } else {
        const result = await pool.query(
          `SELECT category, COUNT(*) as count
           FROM preferences
           WHERE agent_id = $1
           GROUP BY category
           ORDER BY category ASC`,
          [agentId]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, categories: result.rows }, null, 2),
          }],
        };
      }
    } else if (type === "fact") {
      if (category) {
        const result = await pool.query(
          `SELECT id, agent_id, category, subject, predicate, object, confidence, created_at
           FROM facts
           WHERE agent_id = $1 AND category = $2
           ORDER BY subject ASC
           LIMIT $3`,
          [agentId, category, maxResults]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, category, count: result.rows.length, entries: result.rows }, null, 2),
          }],
        };
      } else {
        const result = await pool.query(
          `SELECT category, COUNT(*) as count
           FROM facts
           WHERE agent_id = $1
           GROUP BY category
           ORDER BY category ASC`,
          [agentId]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, categories: result.rows }, null, 2),
          }],
        };
      }
    } else {
      // context — list conversations
      if (category) {
        const result = await pool.query(
          `SELECT id, agent_id, title, context_summary, status, last_activity_at, metadata
           FROM conversations
           WHERE agent_id = $1 AND metadata->>'category' = $2
           ORDER BY last_activity_at DESC
           LIMIT $3`,
          [agentId, category, maxResults]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, category, count: result.rows.length, entries: result.rows }, null, 2),
          }],
        };
      } else {
        const result = await pool.query(
          `SELECT COALESCE(metadata->>'category', 'uncategorized') as category, COUNT(*) as count
           FROM conversations
           WHERE agent_id = $1
           GROUP BY COALESCE(metadata->>'category', 'uncategorized')
           ORDER BY category ASC`,
          [agentId]
        );
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ type, categories: result.rows }, null, 2),
          }],
        };
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text" as const, text: `Error listing memory: ${message}` }],
      isError: true,
    };
  }
});

// ─── MCP Resources ──────────────────────────────────────────────────

// memory://preferences — returns all user preferences
server.registerResource(
  "preferences",
  "memory://preferences",
  { description: "All stored user preferences from the preferences table" },
  async () => {
    const result = await pool.query(
      `SELECT id, agent_id, category, key, value, version, created_at, updated_at
       FROM preferences
       ORDER BY category, key`
    );
    return {
      contents: [
        {
          uri: "memory://preferences",
          mimeType: "application/json",
          text: JSON.stringify({ type: "preferences", count: result.rows.length, entries: result.rows }, null, 2),
        },
      ],
    };
  }
);

// memory://context/current — returns active conversation context
server.registerResource(
  "context-current",
  "memory://context/current",
  { description: "Currently active conversation contexts" },
  async () => {
    const result = await pool.query(
      `SELECT id, agent_id, title, context_summary, status, started_at, last_activity_at, metadata
       FROM conversations
       WHERE status = 'active'
       ORDER BY last_activity_at DESC`
    );
    return {
      contents: [
        {
          uri: "memory://context/current",
          mimeType: "application/json",
          text: JSON.stringify({ type: "context", status: "active", count: result.rows.length, entries: result.rows }, null, 2),
        },
      ],
    };
  }
);

// memory://facts/{category} — returns facts filtered by category
server.registerResource(
  "facts-by-category",
  new ResourceTemplate("memory://facts/{category}", {
    list: async () => {
      const result = await pool.query(
        `SELECT DISTINCT category FROM facts ORDER BY category`
      );
      return {
        resources: result.rows.map((row: { category: string }) => ({
          uri: `memory://facts/${row.category}`,
          name: `Facts: ${row.category}`,
          description: `Facts in the ${row.category} category`,
          mimeType: "application/json",
        })),
      };
    },
  }),
  { description: "Facts filtered by category from the facts table" },
  async (uri, variables) => {
    const category = variables.category as string;
    const result = await pool.query(
      `SELECT id, agent_id, category, subject, predicate, object, confidence, source, valid_from, valid_until, created_at
       FROM facts
       WHERE category = $1
       ORDER BY subject`,
      [category]
    );
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify({ type: "facts", category, count: result.rows.length, entries: result.rows }, null, 2),
        },
      ],
    };
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("OpenClaw Memory MCP server running on stdio");
}

main().catch((err) => {
  console.error("Server error:", err);
  process.exit(1);
});
