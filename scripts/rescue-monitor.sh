#!/usr/bin/env bash
# rescue-monitor.sh — Rescue bot health check loop.
# Monitors the Main Gateway (port 18789) and alerts + attempts recovery on failure.
# Reads settings from config/rescue-monitor.yml.
# Designed to run as a systemd service (outputs structured logs to stdout).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${RESCUE_CONFIG:-$PROJECT_ROOT/config/rescue-monitor.yml}"

# ---------------------------------------------------------------------------
# Parse config from rescue-monitor.yml
# Uses python3+yaml since yq may not be installed. Falls back to defaults.
# ---------------------------------------------------------------------------
parse_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "[WARN] Config file not found: $CONFIG_FILE — using defaults" >&2
    fi

    HEALTH_URL=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    print(cfg['monitor']['target'])
except Exception:
    print('http://localhost:18789/health')
" 2>/dev/null || echo "http://localhost:18789/health")

    INTERVAL_RAW=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    print(cfg['monitor']['interval'])
except Exception:
    print('30s')
" 2>/dev/null || echo "30s")

    TIMEOUT_RAW=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    print(cfg['monitor']['timeout'])
except Exception:
    print('10s')
" 2>/dev/null || echo "10s")

    FAILURE_THRESHOLD=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    print(cfg['monitor']['failureThreshold'])
except Exception:
    print('3')
" 2>/dev/null || echo "3")

    ALERT_MESSAGE=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    actions = cfg['monitor']['onFailure']
    for a in actions:
        if 'alert' in a:
            print(a['alert']['message'])
            sys.exit(0)
    print('ALERT: Main gateway down. Rescue bot taking over.')
except Exception:
    print('ALERT: Main gateway down. Rescue bot taking over.')
" 2>/dev/null || echo "ALERT: Main gateway down. Rescue bot taking over.")

    RECOVERY_COMMAND=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    actions = cfg['monitor']['onFailure']
    for a in actions:
        if 'attempt_recovery' in a:
            print(a['attempt_recovery']['command'])
            sys.exit(0)
    print('systemctl restart openclaw-main')
except Exception:
    print('systemctl restart openclaw-main')
" 2>/dev/null || echo "systemctl restart openclaw-main")

    MAX_RECOVERY_ATTEMPTS=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG_FILE'))
    actions = cfg['monitor']['onFailure']
    for a in actions:
        if 'attempt_recovery' in a:
            print(a['attempt_recovery']['maxAttempts'])
            sys.exit(0)
    print('3')
except Exception:
    print('3')
" 2>/dev/null || echo "3")

    # Convert interval/timeout from "30s" format to seconds
    INTERVAL=$(echo "$INTERVAL_RAW" | sed 's/s$//')
    TIMEOUT=$(echo "$TIMEOUT_RAW" | sed 's/s$//')
}

# ---------------------------------------------------------------------------
# Logging helpers (structured for journalctl / systemd)
# ---------------------------------------------------------------------------
log_info()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"; }
log_warn()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*"; }
log_error() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*"; }

# ---------------------------------------------------------------------------
# Send Slack alert via webhook (if SLACK_WEBHOOK_URL is set)
# ---------------------------------------------------------------------------
send_alert() {
    local message="$1"
    log_warn "$message"

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\": \"$message\"}" \
            >/dev/null 2>&1 || log_warn "Failed to send Slack alert"
    else
        log_warn "SLACK_WEBHOOK_URL not set — alert logged only"
    fi
}

# ---------------------------------------------------------------------------
# Attempt recovery (restart the main service)
# ---------------------------------------------------------------------------
attempt_recovery() {
    local attempt=$1
    log_info "Recovery attempt $attempt/$MAX_RECOVERY_ATTEMPTS: $RECOVERY_COMMAND"

    if eval "$RECOVERY_COMMAND" 2>&1; then
        log_info "Recovery command succeeded"
        return 0
    else
        log_error "Recovery command failed (attempt $attempt)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Health check — curl the target endpoint
# ---------------------------------------------------------------------------
check_health() {
    if curl -sf --max-time "$TIMEOUT" "$HEALTH_URL" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main monitoring loop
# ---------------------------------------------------------------------------
main() {
    parse_config

    log_info "Rescue monitor starting"
    log_info "  Target:    $HEALTH_URL"
    log_info "  Interval:  ${INTERVAL}s"
    log_info "  Timeout:   ${TIMEOUT}s"
    log_info "  Threshold: $FAILURE_THRESHOLD consecutive failures"
    log_info "  Recovery:  $RECOVERY_COMMAND (max $MAX_RECOVERY_ATTEMPTS attempts)"

    local consecutive_failures=0
    local recovery_attempts=0
    local in_failure_state=false

    # Handle SIGTERM/SIGINT gracefully (systemd sends SIGTERM on stop)
    trap 'log_info "Rescue monitor stopping (signal received)"; exit 0' SIGTERM SIGINT

    while true; do
        if check_health; then
            if [[ "$in_failure_state" == "true" ]]; then
                log_info "Main gateway recovered — returning to normal monitoring"
                send_alert "RECOVERED: Main gateway is back online."
                in_failure_state=false
                recovery_attempts=0
            fi
            consecutive_failures=0
            # Normal heartbeat (only log every 10th check to reduce noise)
            if (( RANDOM % 10 == 0 )); then
                log_info "Health check OK — $HEALTH_URL"
            fi
        else
            consecutive_failures=$((consecutive_failures + 1))
            log_warn "Health check FAILED ($consecutive_failures/$FAILURE_THRESHOLD) — $HEALTH_URL"

            if (( consecutive_failures >= FAILURE_THRESHOLD )) && [[ "$in_failure_state" == "false" ]]; then
                in_failure_state=true
                log_error "Failure threshold reached ($FAILURE_THRESHOLD consecutive failures)"
                send_alert "$ALERT_MESSAGE"
            fi

            # Attempt recovery if in failure state and haven't exhausted attempts
            if [[ "$in_failure_state" == "true" ]] && (( recovery_attempts < MAX_RECOVERY_ATTEMPTS )); then
                recovery_attempts=$((recovery_attempts + 1))
                attempt_recovery "$recovery_attempts" || true
                # Wait a bit longer after recovery attempt to let service start
                sleep "$INTERVAL"
            fi
        fi

        sleep "$INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
# Support --dry-run for testing config parsing
if [[ "${1:-}" == "--dry-run" ]]; then
    parse_config
    echo "Config parsed successfully:"
    echo "  HEALTH_URL=$HEALTH_URL"
    echo "  INTERVAL=${INTERVAL}s"
    echo "  TIMEOUT=${TIMEOUT}s"
    echo "  FAILURE_THRESHOLD=$FAILURE_THRESHOLD"
    echo "  ALERT_MESSAGE=$ALERT_MESSAGE"
    echo "  RECOVERY_COMMAND=$RECOVERY_COMMAND"
    echo "  MAX_RECOVERY_ATTEMPTS=$MAX_RECOVERY_ATTEMPTS"
    exit 0
fi

main
