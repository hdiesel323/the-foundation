#!/usr/bin/env node
// Command Center dashboard server
// Serves the dashboard HTML and proxies API requests to PostgreSQL
// Usage: node dashboard/serve.mjs
// Port: DASHBOARD_PORT env var (default 18810)

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = parseInt(process.env.DASHBOARD_PORT || "18810", 10);
const DASHBOARD_PATH = path.join(__dirname, "index.html");

const server = http.createServer(async (req, res) => {
  // CORS headers
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET");

  if (req.url === "/" || req.url === "/index.html") {
    // Serve dashboard
    try {
      const html = fs.readFileSync(DASHBOARD_PATH, "utf-8");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(html);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Dashboard not found");
    }
    return;
  }

  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({ status: "ok", service: "command-center", port: PORT }),
    );
    return;
  }

  // Proxy /seldon/* API requests to Seldon service
  if (req.url.startsWith("/seldon/")) {
    const seldonUrl = `http://${process.env.SELDON_HOST || "localhost"}:${process.env.SELDON_PORT || "18789"}${req.url}`;
    try {
      // Collect request body for POST/PUT/PATCH
      let reqBody;
      if (req.method !== "GET" && req.method !== "HEAD") {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        reqBody = Buffer.concat(chunks).toString();
      }
      const fetchOpts = {
        method: req.method,
        headers: { "Content-Type": "application/json" },
      };
      if (reqBody) fetchOpts.body = reqBody;
      const proxyRes = await fetch(seldonUrl, fetchOpts);
      const body = await proxyRes.text();
      res.writeHead(proxyRes.status, {
        "Content-Type":
          proxyRes.headers.get("content-type") || "application/json",
      });
      res.end(body);
    } catch {
      res.writeHead(502, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Seldon API unavailable" }));
    }
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Command Center dashboard: http://localhost:${PORT}`);
});
