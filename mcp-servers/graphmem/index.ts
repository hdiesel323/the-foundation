import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";
import Database from "better-sqlite3";

// ============================================================
// GraphMem MCP Server
//
// Provides graph-based knowledge memory with entity extraction,
// relationship tracking, and memory evolution (decay, consolidation).
// ============================================================

const DB_PATH =
  process.env.GRAPHMEM_DB_PATH || "/opt/openclaw/data/clawd_brain.db";

const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

const server = new McpServer({
  name: "openclaw-graphmem",
  version: "0.1.0",
});

// ============================================================
// Tool: graphmem_ingest
// Ingest text into the knowledge graph, extracting entities
// and relationships.
// ============================================================
server.registerTool("graphmem_ingest", {
  description:
    "Ingest a piece of text into the knowledge graph. Extracts entities " +
    "and relationships from the content and stores them as graph nodes/edges. " +
    "Use this to build the agent's long-term knowledge.",
  inputSchema: {
    content: z.string().describe("Text content to ingest into the knowledge graph"),
    source: z.string().optional().describe("Source of the content (e.g. 'conversation', 'document', 'observation')"),
    agent_id: z.string().optional().describe("Agent ID that produced this content"),
    entities: z.array(z.object({
      name: z.string().describe("Entity name"),
      type: z.string().describe("Entity type (person, project, concept, tool, etc.)"),
      description: z.string().optional().describe("Brief description"),
    })).optional().describe("Pre-extracted entities (if known). If omitted, server stores raw memory."),
    relationships: z.array(z.object({
      from: z.string().describe("Source entity name"),
      to: z.string().describe("Target entity name"),
      type: z.string().describe("Relationship type (uses, manages, depends_on, etc.)"),
      weight: z.number().optional().describe("Relationship strength 0-1"),
    })).optional().describe("Pre-extracted relationships between entities"),
  },
}, async ({ content, source, agent_id, entities, relationships }) => {
  const agentId = agent_id || "shared";
  const src = source || "agent";

  const insertEntity = db.prepare(
    `INSERT INTO entities (name, entity_type, description)
     VALUES (?, ?, ?)
     ON CONFLICT(name) DO UPDATE SET
       description = COALESCE(excluded.description, entities.description),
       updated_at = CURRENT_TIMESTAMP
     RETURNING id, name, entity_type`
  );

  const insertRelationship = db.prepare(
    `INSERT INTO relationships (from_entity_id, to_entity_id, relationship_type, weight)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(from_entity_id, to_entity_id, relationship_type)
     DO UPDATE SET weight = MAX(relationships.weight, excluded.weight)
     RETURNING id`
  );

  const insertMemory = db.prepare(
    `INSERT INTO memories (content, source, agent_id, entity_ids)
     VALUES (?, ?, ?, ?)
     RETURNING id`
  );

  const entityIds: number[] = [];

  const txn = db.transaction(() => {
    // Insert entities if provided
    if (entities && entities.length > 0) {
      for (const entity of entities) {
        const row = insertEntity.get(
          entity.name,
          entity.type,
          entity.description || null
        ) as { id: number; name: string; entity_type: string };
        entityIds.push(row.id);
      }
    }

    // Insert relationships if provided
    if (relationships && relationships.length > 0) {
      for (const rel of relationships) {
        const fromEntity = db.prepare(
          "SELECT id FROM entities WHERE name = ?"
        ).get(rel.from) as { id: number } | undefined;
        const toEntity = db.prepare(
          "SELECT id FROM entities WHERE name = ?"
        ).get(rel.to) as { id: number } | undefined;

        if (fromEntity && toEntity) {
          insertRelationship.run(
            fromEntity.id,
            toEntity.id,
            rel.type,
            rel.weight ?? 1.0
          );
        }
      }
    }

    // Store raw memory
    const memoryRow = insertMemory.get(
      content,
      src,
      agentId,
      JSON.stringify(entityIds)
    ) as { id: number };

    return memoryRow.id;
  });

  const memoryId = txn();

  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          success: true,
          memory_id: memoryId,
          entities_stored: entityIds.length,
          relationships_stored: relationships?.length || 0,
        }),
      },
    ],
  };
});

// ============================================================
// Tool: graphmem_query
// Query the knowledge graph for entities and relationships.
// ============================================================
server.registerTool("graphmem_query", {
  description:
    "Query the knowledge graph. Returns entities with their relationships " +
    "and confidence scores. Supports entity lookup, relationship traversal, " +
    "and free-text search across stored memories.",
  inputSchema: {
    query: z.string().describe("Search query or entity name to look up"),
    type: z.enum(["entity", "relationship", "memory", "graph"]).optional()
      .describe("Query type: entity (find entity), relationship (find connections), memory (search raw text), graph (full subgraph)"),
    entity_type: z.string().optional().describe("Filter by entity type"),
    limit: z.number().optional().describe("Max results (default 10)"),
  },
}, async ({ query, type, entity_type, limit }) => {
  const maxResults = limit || 10;
  const queryType = type || "entity";

  let results: unknown[] = [];

  if (queryType === "entity") {
    const stmt = entity_type
      ? db.prepare(
          `SELECT id, name, entity_type, description, created_at, updated_at
           FROM entities
           WHERE (name LIKE ? OR description LIKE ?) AND entity_type = ?
           ORDER BY updated_at DESC LIMIT ?`
        )
      : db.prepare(
          `SELECT id, name, entity_type, description, created_at, updated_at
           FROM entities
           WHERE name LIKE ? OR description LIKE ?
           ORDER BY updated_at DESC LIMIT ?`
        );

    const pattern = `%${query}%`;
    results = entity_type
      ? stmt.all(pattern, pattern, entity_type, maxResults)
      : stmt.all(pattern, pattern, maxResults);

  } else if (queryType === "relationship") {
    results = db.prepare(
      `SELECT r.id, r.relationship_type, r.weight,
              e1.name AS from_name, e1.entity_type AS from_type,
              e2.name AS to_name, e2.entity_type AS to_type
       FROM relationships r
       JOIN entities e1 ON r.from_entity_id = e1.id
       JOIN entities e2 ON r.to_entity_id = e2.id
       WHERE e1.name LIKE ? OR e2.name LIKE ?
       ORDER BY r.weight DESC LIMIT ?`
    ).all(`%${query}%`, `%${query}%`, maxResults);

  } else if (queryType === "memory") {
    results = db.prepare(
      `SELECT id, content, source, agent_id, entity_ids, created_at
       FROM memories
       WHERE content LIKE ?
       ORDER BY created_at DESC LIMIT ?`
    ).all(`%${query}%`, maxResults);

  } else if (queryType === "graph") {
    // Full subgraph: entity + all relationships
    const entity = db.prepare(
      "SELECT id, name, entity_type, description FROM entities WHERE name LIKE ? LIMIT 1"
    ).get(`%${query}%`) as { id: number; name: string; entity_type: string; description: string } | undefined;

    if (entity) {
      const rels = db.prepare(
        `SELECT r.relationship_type, r.weight,
                e.name AS connected_name, e.entity_type AS connected_type,
                CASE WHEN r.from_entity_id = ? THEN 'outgoing' ELSE 'incoming' END AS direction
         FROM relationships r
         JOIN entities e ON (
           CASE WHEN r.from_entity_id = ? THEN r.to_entity_id ELSE r.from_entity_id END = e.id
         )
         WHERE r.from_entity_id = ? OR r.to_entity_id = ?
         ORDER BY r.weight DESC LIMIT ?`
      ).all(entity.id, entity.id, entity.id, entity.id, maxResults);

      results = [{ entity, relationships: rels }];
    }
  }

  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          query,
          type: queryType,
          count: results.length,
          results,
        }, null, 2),
      },
    ],
  };
});

// ============================================================
// Tool: graphmem_evolve
// Run knowledge graph evolution: decay stale edges,
// consolidate duplicates, compute PageRank importance.
// ============================================================
server.registerTool("graphmem_evolve", {
  description:
    "Evolve the knowledge graph. Runs decay on stale relationships, " +
    "consolidates near-duplicate entities, and computes PageRank-style " +
    "importance scores. Call periodically to keep the graph healthy.",
  inputSchema: {
    decay_days: z.number().optional().describe("Decay relationships not updated in N days (default 30)"),
    decay_factor: z.number().optional().describe("Multiply stale weights by this factor 0-1 (default 0.9)"),
    consolidate: z.boolean().optional().describe("Merge near-duplicate entities (default true)"),
    pagerank: z.boolean().optional().describe("Recompute PageRank importance (default true)"),
  },
}, async ({ decay_days, decay_factor, consolidate, pagerank }) => {
  const days = decay_days ?? 30;
  const factor = decay_factor ?? 0.9;
  const doConsolidate = consolidate ?? true;
  const doPageRank = pagerank ?? true;

  const stats = {
    decayed_relationships: 0,
    consolidated_entities: 0,
    pagerank_computed: false,
  };

  const txn = db.transaction(() => {
    // Decay: reduce weight of stale relationships
    const decayResult = db.prepare(
      `UPDATE relationships
       SET weight = weight * ?
       WHERE created_at < datetime('now', '-' || ? || ' days')
       AND weight > 0.01`
    ).run(factor, days);
    stats.decayed_relationships = decayResult.changes;

    // Prune: remove near-zero relationships
    db.prepare("DELETE FROM relationships WHERE weight < 0.01").run();

    // Consolidation: merge entities with identical names (case-insensitive)
    if (doConsolidate) {
      const dupes = db.prepare(
        `SELECT LOWER(name) AS lname, GROUP_CONCAT(id) AS ids, COUNT(*) AS cnt
         FROM entities
         GROUP BY LOWER(name)
         HAVING COUNT(*) > 1`
      ).all() as Array<{ lname: string; ids: string; cnt: number }>;

      for (const dupe of dupes) {
        const idList = dupe.ids.split(",").map(Number);
        const keepId = idList[0];
        const removeIds = idList.slice(1);

        for (const removeId of removeIds) {
          // Re-point relationships
          db.prepare(
            "UPDATE relationships SET from_entity_id = ? WHERE from_entity_id = ?"
          ).run(keepId, removeId);
          db.prepare(
            "UPDATE relationships SET to_entity_id = ? WHERE to_entity_id = ?"
          ).run(keepId, removeId);
          // Delete duplicate entity
          db.prepare("DELETE FROM entities WHERE id = ?").run(removeId);
        }
        stats.consolidated_entities += removeIds.length;
      }
    }

    // PageRank: simplified iterative computation
    if (doPageRank) {
      const entities = db.prepare("SELECT id FROM entities").all() as Array<{ id: number }>;
      const entityCount = entities.length;

      if (entityCount > 0) {
        const dampingFactor = 0.85;
        const iterations = 10;
        const scores: Map<number, number> = new Map();

        // Initialize
        for (const e of entities) {
          scores.set(e.id, 1.0 / entityCount);
        }

        // Iterate
        for (let i = 0; i < iterations; i++) {
          const newScores: Map<number, number> = new Map();
          for (const e of entities) {
            newScores.set(e.id, (1 - dampingFactor) / entityCount);
          }

          const edges = db.prepare(
            "SELECT from_entity_id, to_entity_id, weight FROM relationships"
          ).all() as Array<{ from_entity_id: number; to_entity_id: number; weight: number }>;

          // Count outgoing edges per entity
          const outCount: Map<number, number> = new Map();
          for (const edge of edges) {
            outCount.set(edge.from_entity_id, (outCount.get(edge.from_entity_id) || 0) + 1);
          }

          for (const edge of edges) {
            const fromScore = scores.get(edge.from_entity_id) || 0;
            const outDegree = outCount.get(edge.from_entity_id) || 1;
            const contribution = dampingFactor * (fromScore / outDegree) * edge.weight;
            const current = newScores.get(edge.to_entity_id) || 0;
            newScores.set(edge.to_entity_id, current + contribution);
          }

          for (const [id, score] of newScores) {
            scores.set(id, score);
          }
        }

        // Store PageRank in entity attributes
        const updateStmt = db.prepare(
          `UPDATE entities SET attributes = json_set(
            COALESCE(attributes, '{}'), '$.pagerank', ?
          ) WHERE id = ?`
        );

        for (const [id, score] of scores) {
          updateStmt.run(score, id);
        }

        stats.pagerank_computed = true;
      }
    }
  });

  txn();

  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          success: true,
          ...stats,
        }),
      },
    ],
  };
});

// ============================================================
// Tool: graphmem_update
// Update an existing entity or relationship in the graph.
// ============================================================
server.registerTool("graphmem_update", {
  description:
    "Update an existing entity or relationship in the knowledge graph. " +
    "Use to correct information, update descriptions, or adjust relationship weights.",
  inputSchema: {
    target: z.enum(["entity", "relationship"]).describe("What to update"),
    entity_name: z.string().optional().describe("Entity name to update (for entity target)"),
    entity_type: z.string().optional().describe("New entity type"),
    description: z.string().optional().describe("New entity description"),
    from_entity: z.string().optional().describe("From entity name (for relationship target)"),
    to_entity: z.string().optional().describe("To entity name (for relationship target)"),
    relationship_type: z.string().optional().describe("Relationship type to update"),
    weight: z.number().optional().describe("New relationship weight"),
  },
}, async ({ target, entity_name, entity_type, description, from_entity, to_entity, relationship_type, weight }) => {
  if (target === "entity") {
    if (!entity_name) {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ error: "entity_name required" }) }],
      };
    }

    const updates: string[] = [];
    const params: unknown[] = [];

    if (entity_type) {
      updates.push("entity_type = ?");
      params.push(entity_type);
    }
    if (description) {
      updates.push("description = ?");
      params.push(description);
    }

    if (updates.length === 0) {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ error: "no updates specified" }) }],
      };
    }

    updates.push("updated_at = CURRENT_TIMESTAMP");
    params.push(entity_name);

    const result = db.prepare(
      `UPDATE entities SET ${updates.join(", ")} WHERE name = ?`
    ).run(...params);

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify({
            success: true,
            entity: entity_name,
            rows_updated: result.changes,
          }),
        },
      ],
    };
  } else {
    // relationship update
    if (!from_entity || !to_entity || !relationship_type) {
      return {
        content: [{
          type: "text" as const,
          text: JSON.stringify({ error: "from_entity, to_entity, and relationship_type required" }),
        }],
      };
    }

    const fromRow = db.prepare("SELECT id FROM entities WHERE name = ?").get(from_entity) as { id: number } | undefined;
    const toRow = db.prepare("SELECT id FROM entities WHERE name = ?").get(to_entity) as { id: number } | undefined;

    if (!fromRow || !toRow) {
      return {
        content: [{
          type: "text" as const,
          text: JSON.stringify({ error: "One or both entities not found" }),
        }],
      };
    }

    const newWeight = weight ?? 1.0;
    const result = db.prepare(
      `UPDATE relationships SET weight = ?
       WHERE from_entity_id = ? AND to_entity_id = ? AND relationship_type = ?`
    ).run(newWeight, fromRow.id, toRow.id, relationship_type);

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify({
            success: true,
            from: from_entity,
            to: to_entity,
            relationship_type,
            new_weight: newWeight,
            rows_updated: result.changes,
          }),
        },
      ],
    };
  }
});

// ============================================================
// Start server
// ============================================================
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("GraphMem MCP server error:", err);
  process.exit(1);
});
