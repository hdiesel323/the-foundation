#!/usr/bin/env bash
# cartographer.sh — Scans the OpenClaw v2 codebase and generates docs/CODEBASE_MAP.md
# Usage: scripts/cartographer.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$REPO_ROOT/docs/CODEBASE_MAP.md"

mkdir -p "$REPO_ROOT/docs"

{
  echo "# OpenClaw v2 — Codebase Map"
  echo ""
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo ""

  # ── Directory Tree ──────────────────────────────────────────────
  echo "## Directory Tree"
  echo ""
  echo '```'
  # Show top two levels, skip .git, node_modules, .beads internal
  if command -v tree &>/dev/null; then
    tree -L 2 -d --noreport -I '.git|node_modules|.claude*' "$REPO_ROOT" 2>/dev/null \
      | sed "s|$REPO_ROOT|.|"
  else
    # Fallback: manual directory listing
    find "$REPO_ROOT" -maxdepth 2 -type d \
      ! -path '*/.git*' \
      ! -path '*/node_modules*' \
      ! -path '*/.claude*' \
      -print 2>/dev/null \
      | sed "s|$REPO_ROOT|.|" \
      | sort
  fi
  echo '```'
  echo ""

  # ── File Counts by Category ────────────────────────────────────
  echo "## File Counts by Category"
  echo ""
  echo "| Category | Pattern | Count |"
  echo "|----------|---------|-------|"

  count_files() {
    local label="$1" pattern="$2"
    local n
    n=$(find "$REPO_ROOT" -name "$pattern" ! -path '*/.git/*' ! -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
    echo "| $label | \`$pattern\` | $n |"
  }

  count_files "Docker"          "Dockerfile*"
  count_files "Compose"         "docker-compose*.yml"
  count_files "Shell scripts"   "*.sh"
  count_files "TypeScript"      "*.ts"
  count_files "JSON configs"    "*.json"
  count_files "YAML configs"    "*.yml"
  count_files "YAML configs"    "*.yaml"
  count_files "Markdown docs"   "*.md"
  count_files "SQL migrations"  "*.sql"
  count_files "SOUL.md files"   "SOUL.md"
  echo ""

  # ── Key Files: Agents ──────────────────────────────────────────
  echo "## Agents (SOUL.md files)"
  echo ""
  echo "| Agent | Division | SOUL.md |"
  echo "|-------|----------|---------|"
  for agent_dir in "$REPO_ROOT"/agents/*/; do
    agent=$(basename "$agent_dir")
    soul="agents/$agent/SOUL.md"
    if [ -f "$REPO_ROOT/$soul" ]; then
      # Try to extract division from SOUL.md first line or fallback
      division=$(grep -i 'division' "$REPO_ROOT/$soul" 2>/dev/null | head -1 | sed 's/.*: *//' || echo "—")
      [ -z "$division" ] && division="—"
      echo "| $agent | $division | \`$soul\` |"
    fi
  done
  echo ""

  # ── Key Files: Config ──────────────────────────────────────────
  echo "## Configuration Files"
  echo ""
  echo "| File | Lines |"
  echo "|------|-------|"
  for f in "$REPO_ROOT"/config/*.json "$REPO_ROOT"/config/*.yml "$REPO_ROOT"/config/*.yaml; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    rel=$(echo "$f" | sed "s|$REPO_ROOT/||")
    echo "| \`$rel\` | $lines |"
  done
  echo ""

  # ── Key Files: Scripts ─────────────────────────────────────────
  echo "## Scripts"
  echo ""
  echo "| Script | Lines | Description |"
  echo "|--------|-------|-------------|"
  for f in "$REPO_ROOT"/scripts/*.sh; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    name=$(basename "$f")
    # Extract description from first comment line after shebang
    desc=$(sed -n '2s/^# *//p' "$f" 2>/dev/null || echo "—")
    [ -z "$desc" ] && desc="—"
    echo "| \`scripts/$name\` | $lines | $desc |"
  done
  echo ""

  # ── Key Files: MCP Servers ─────────────────────────────────────
  echo "## MCP Servers"
  echo ""
  echo "| Server | Path | Key Files |"
  echo "|--------|------|-----------|"
  for mcp_dir in "$REPO_ROOT"/mcp-servers/*/; do
    [ -d "$mcp_dir" ] || continue
    server=$(basename "$mcp_dir")
    key_files=$(find "$mcp_dir" -maxdepth 1 -type f -name '*.ts' -o -name '*.json' -o -name 'Dockerfile' 2>/dev/null \
      | xargs -I{} basename {} | sort | tr '\n' ', ' | sed 's/,$//')
    [ -z "$key_files" ] && key_files="—"
    echo "| $server | \`mcp-servers/$server/\` | $key_files |"
  done
  echo ""

  # ── Key Files: Tests ───────────────────────────────────────────
  echo "## Tests"
  echo ""
  echo "| Test | Type | Lines |"
  echo "|------|------|-------|"
  for f in "$REPO_ROOT"/tests/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    lines=$(wc -l < "$f" | tr -d ' ')
    case "$name" in
      *.sh) type="Shell" ;;
      *.ts) type="TypeScript" ;;
      *.json) type="Config" ;;
      *) type="Other" ;;
    esac
    echo "| \`tests/$name\` | $type | $lines |"
  done
  echo ""

  # ── Dependency Graph ───────────────────────────────────────────
  echo "## Dependency Graph"
  echo ""
  echo "Cross-references: which configs reference which agents and services."
  echo ""
  echo "| Config File | References |"
  echo "|-------------|------------|"

  # Scan config files for agent name or service references
  AGENTS="seldon daneel hardin mallow preem riose trader gaal demerzel mis amaryl magnifico venabili arkady"
  SERVICES="postgres grafana prometheus loki promtail openclaw cloudflared mcp-gateway"

  for f in "$REPO_ROOT"/config/*.json "$REPO_ROOT"/config/*.yml "$REPO_ROOT"/config/*.yaml; do
    [ -f "$f" ] || continue
    rel=$(echo "$f" | sed "s|$REPO_ROOT/||")
    refs=""
    for name in $AGENTS $SERVICES; do
      if grep -qi "$name" "$f" 2>/dev/null; then
        refs="$refs $name"
      fi
    done
    refs=$(echo "$refs" | xargs | tr ' ' ', ')
    [ -z "$refs" ] && refs="—"
    echo "| \`$rel\` | $refs |"
  done
  echo ""

  # ── Docker Compose Services ────────────────────────────────────
  echo "## Docker Compose Services"
  echo ""
  if [ -f "$REPO_ROOT/docker-compose.yml" ]; then
    echo "| Service | Image/Build | Ports |"
    echo "|---------|-------------|-------|"
    # Parse service names from compose file
    python3 -c "
import yaml, sys
with open('$REPO_ROOT/docker-compose.yml') as f:
    data = yaml.safe_load(f)
services = data.get('services', {})
for name, svc in sorted(services.items()):
    image = svc.get('image', svc.get('build', '—'))
    if isinstance(image, dict):
        image = image.get('context', '—')
    ports = ', '.join(svc.get('ports', [])) or '—'
    print(f'| \`{name}\` | \`{image}\` | {ports} |')
" 2>/dev/null || echo "*(could not parse docker-compose.yml)*"
  else
    echo "*(no docker-compose.yml found)*"
  fi
  echo ""

  # ── Summary ────────────────────────────────────────────────────
  echo "## Summary"
  echo ""
  total_files=$(find "$REPO_ROOT" -type f ! -path '*/.git/*' ! -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
  total_lines=$(find "$REPO_ROOT" -type f \( -name '*.sh' -o -name '*.ts' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o -name '*.sql' -o -name '*.md' \) ! -path '*/.git/*' ! -path '*/node_modules/*' -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
  agent_count=$(find "$REPO_ROOT/agents" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  script_count=$(find "$REPO_ROOT/scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
  config_count=$(find "$REPO_ROOT/config" -type f 2>/dev/null | wc -l | tr -d ' ')
  test_count=$(find "$REPO_ROOT/tests" -type f 2>/dev/null | wc -l | tr -d ' ')

  echo "- **Total files**: $total_files"
  echo "- **Total lines** (code + config + docs): $total_lines"
  echo "- **Agents**: $agent_count"
  echo "- **Scripts**: $script_count"
  echo "- **Config files**: $config_count"
  echo "- **Test files**: $test_count"

} > "$OUTPUT"

echo "✓ Codebase map generated: $OUTPUT"
echo "  $(wc -l < "$OUTPUT" | tr -d ' ') lines written"
