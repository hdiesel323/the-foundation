/**
 * Daneel Patrol — Hourly infrastructure health checks.
 *
 * Checks: disk usage, git dirty file counts, running processes,
 * memory pressure, and large log file detection (>100MB).
 * Publishes findings as infrastructure insights with TTL to shared memory.
 */

import { execSync } from 'node:child_process';
import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const DISK_WARNING_THRESHOLD = 80;  // percent
const DISK_CRITICAL_THRESHOLD = 90; // percent
const MEMORY_WARNING_THRESHOLD = 80; // percent
const MEMORY_CRITICAL_THRESHOLD = 90; // percent
const LARGE_LOG_FILE_BYTES = 100 * 1024 * 1024; // 100MB

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Check disk usage on all mounted filesystems.
 * Returns findings for partitions exceeding thresholds.
 */
export function checkDiskUsage(): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  try {
    const output = execSync('df -h --output=pcent,target 2>/dev/null || df -h', { encoding: 'utf8', timeout: 10000 });
    const lines = output.trim().split('\n').slice(1); // skip header

    for (const line of lines) {
      const match = line.trim().match(/(\d+)%\s+(.+)/);
      if (!match) continue;

      const usage = parseInt(match[1], 10);
      const mount = match[2];

      if (usage >= DISK_CRITICAL_THRESHOLD) {
        findings.push({
          subject: `disk:${mount}`,
          predicate: 'usage_critical',
          description: `Disk usage at ${usage}% on ${mount} (threshold: ${DISK_CRITICAL_THRESHOLD}%)`,
          severity: 'critical',
        });
      } else if (usage >= DISK_WARNING_THRESHOLD) {
        findings.push({
          subject: `disk:${mount}`,
          predicate: 'usage_warning',
          description: `Disk usage at ${usage}% on ${mount} (threshold: ${DISK_WARNING_THRESHOLD}%)`,
          severity: 'warning',
        });
      }
    }
  } catch (err) {
    findings.push({
      subject: 'disk',
      predicate: 'check_failed',
      description: `Disk usage check failed: ${err instanceof Error ? err.message : String(err)}`,
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Check git status for dirty/untracked files in the project directory.
 */
export function checkGitStatus(): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  try {
    const output = execSync('git status --porcelain 2>/dev/null', { encoding: 'utf8', timeout: 10000 });
    const dirtyFiles = output.trim().split('\n').filter(l => l.length > 0);

    if (dirtyFiles.length > 0) {
      findings.push({
        subject: 'git',
        predicate: 'dirty_files',
        description: `${dirtyFiles.length} uncommitted file(s) detected in working directory`,
        severity: dirtyFiles.length > 10 ? 'warning' : 'info',
      });
    }
  } catch {
    // Not a git repo or git not available — skip
  }

  return findings;
}

/**
 * Check running Docker container processes.
 */
export function checkRunningProcesses(): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  try {
    const output = execSync('docker ps --format "{{.Names}} {{.Status}}" 2>/dev/null', { encoding: 'utf8', timeout: 10000 });
    const containers = output.trim().split('\n').filter(l => l.length > 0);

    const unhealthy = containers.filter(c => c.includes('unhealthy') || c.includes('Restarting'));
    if (unhealthy.length > 0) {
      findings.push({
        subject: 'docker',
        predicate: 'unhealthy_containers',
        description: `${unhealthy.length} unhealthy/restarting container(s): ${unhealthy.map(c => c.split(' ')[0]).join(', ')}`,
        severity: 'critical',
      });
    }

    const running = containers.filter(c => c.includes('Up'));
    findings.push({
      subject: 'docker',
      predicate: 'running_count',
      description: `${running.length} container(s) running, ${containers.length} total`,
      severity: 'info',
    });
  } catch {
    findings.push({
      subject: 'docker',
      predicate: 'check_failed',
      description: 'Docker process check failed (docker not available)',
      severity: 'warning',
    });
  }

  return findings;
}

/**
 * Check system memory pressure.
 */
export function checkMemoryPressure(): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  try {
    // Try Linux free command first, fall back to macOS vm_stat
    let usagePercent: number | null = null;

    try {
      const output = execSync('free -m 2>/dev/null', { encoding: 'utf8', timeout: 10000 });
      const memLine = output.split('\n').find(l => l.startsWith('Mem:'));
      if (memLine) {
        const parts = memLine.split(/\s+/);
        const total = parseInt(parts[1], 10);
        const used = parseInt(parts[2], 10);
        usagePercent = Math.round((used / total) * 100);
      }
    } catch {
      // macOS fallback
      const nodeUsage = process.memoryUsage();
      const heapUsedMB = Math.round(nodeUsage.heapUsed / 1024 / 1024);
      const heapTotalMB = Math.round(nodeUsage.heapTotal / 1024 / 1024);
      usagePercent = Math.round((heapUsedMB / heapTotalMB) * 100);
    }

    if (usagePercent !== null) {
      if (usagePercent >= MEMORY_CRITICAL_THRESHOLD) {
        findings.push({
          subject: 'memory',
          predicate: 'pressure_critical',
          description: `Memory usage at ${usagePercent}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)`,
          severity: 'critical',
        });
      } else if (usagePercent >= MEMORY_WARNING_THRESHOLD) {
        findings.push({
          subject: 'memory',
          predicate: 'pressure_warning',
          description: `Memory usage at ${usagePercent}% (threshold: ${MEMORY_WARNING_THRESHOLD}%)`,
          severity: 'warning',
        });
      }
    }
  } catch {
    // Memory check not available
  }

  return findings;
}

/**
 * Detect large log files exceeding 100MB threshold.
 */
export function checkLargeLogFiles(): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  try {
    // Check Docker container log sizes
    const output = execSync(
      `find /var/lib/docker/containers -name "*.log" -size +${LARGE_LOG_FILE_BYTES}c 2>/dev/null || true`,
      { encoding: 'utf8', timeout: 15000 }
    );

    const files = output.trim().split('\n').filter(l => l.length > 0);
    if (files.length > 0) {
      findings.push({
        subject: 'logs',
        predicate: 'large_files',
        description: `${files.length} log file(s) exceed ${LARGE_LOG_FILE_BYTES / 1024 / 1024}MB: ${files.join(', ')}`,
        severity: 'warning',
      });
    }
  } catch {
    // find not available or no permissions
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

/**
 * Run all daneel patrol checks and return combined findings.
 * Intended to be called from BaseRunner.runPatrol() override.
 */
export function runDaneelPatrol(): PatrolFinding[] {
  const findings: PatrolFinding[] = [
    ...checkDiskUsage(),
    ...checkGitStatus(),
    ...checkRunningProcesses(),
    ...checkMemoryPressure(),
    ...checkLargeLogFiles(),
  ];

  return findings;
}
