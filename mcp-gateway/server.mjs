import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';

const PORT = 3000;
const CONFIG_PATH = process.env.MCP_CONFIG_PATH || '/config/mcp-servers.json';

let mcpConfig = null;

function loadConfig() {
  try {
    const raw = readFileSync(CONFIG_PATH, 'utf8');
    mcpConfig = JSON.parse(raw);
    console.log(`[mcp-gateway] Loaded config from ${CONFIG_PATH}: ${Object.keys(mcpConfig.mcpServers || {}).length} servers defined`);
  } catch (err) {
    console.error(`[mcp-gateway] Failed to load config from ${CONFIG_PATH}: ${err.message}`);
    mcpConfig = null;
  }
}

loadConfig();

const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    const status = mcpConfig ? 'ok' : 'degraded';
    const servers = mcpConfig ? Object.keys(mcpConfig.mcpServers || {}) : [];
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status, servers, configPath: CONFIG_PATH }));
    return;
  }

  if (req.method === 'GET' && req.url === '/servers') {
    if (!mcpConfig) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Config not loaded' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(mcpConfig));
    return;
  }

  if (req.method === 'POST' && req.url === '/reload') {
    loadConfig();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ reloaded: true }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[mcp-gateway] Listening on port ${PORT}`);
});
