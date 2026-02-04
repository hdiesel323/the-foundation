/**
 * Mis Patrol — 6-hourly competitive intelligence scan.
 *
 * Scans competitor pages for changes in pricing, products,
 * strategic announcements, hiring signals, and content updates.
 * Uses AI-powered change detection and significance scoring.
 */

import type { PatrolFinding } from '../base-runner.js';

// ── Configuration ──────────────────────────────────────────────────────

const CHANGE_TYPES = ['pricing', 'product', 'strategic', 'content', 'hiring', 'partnership'] as const;
type ChangeType = typeof CHANGE_TYPES[number];

const SIGNIFICANCE_THRESHOLD = 5;

interface CompetitorChange {
  competitor: string;
  url: string;
  change_type: ChangeType;
  significance: number;
  summary: string;
  previous_content: string;
  new_content: string;
  detected_at: string;
}

interface ScanTarget {
  competitor: string;
  page_type: 'pricing' | 'products' | 'careers' | 'blog' | 'news';
  url: string;
  last_hash: string;
  last_scanned: string;
}

// ── Patrol Actions ─────────────────────────────────────────────────────

/**
 * Classify and score detected changes.
 */
export function classifyChanges(changes: CompetitorChange[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];

  // High-significance changes (pricing, strategic)
  const critical = changes.filter(
    (c) => c.significance >= 8 && (c.change_type === 'pricing' || c.change_type === 'strategic')
  );

  if (critical.length > 0) {
    findings.push({
      level: 'critical',
      source: 'mis-patrol',
      message: `${critical.length} high-significance competitive change(s) detected`,
      detail: critical.map((c) => ({
        competitor: c.competitor,
        type: c.change_type,
        significance: c.significance,
        summary: c.summary,
        url: c.url,
      })),
      action: 'Immediate competitive response assessment needed — escalate to Seldon',
    });
  }

  // Medium-significance changes
  const notable = changes.filter(
    (c) => c.significance >= SIGNIFICANCE_THRESHOLD && c.significance < 8
  );

  if (notable.length > 0) {
    findings.push({
      level: 'warning',
      source: 'mis-patrol',
      message: `${notable.length} notable competitive change(s) detected`,
      detail: notable.map((c) => ({
        competitor: c.competitor,
        type: c.change_type,
        significance: c.significance,
        summary: c.summary,
      })),
      action: 'Add to weekly intelligence digest for review',
    });
  }

  // New product launches
  const newProducts = changes.filter((c) => c.change_type === 'product' && c.significance >= 6);
  if (newProducts.length > 0) {
    findings.push({
      level: 'info',
      source: 'mis-patrol',
      message: `${newProducts.length} competitor product update(s) detected`,
      detail: newProducts.map((c) => ({
        competitor: c.competitor,
        summary: c.summary,
        url: c.url,
      })),
      action: 'Update competitor product matrix and assess positioning impact',
    });
  }

  // Hiring signals
  const hiringSignals = changes.filter((c) => c.change_type === 'hiring');
  if (hiringSignals.length > 0) {
    findings.push({
      level: 'info',
      source: 'mis-patrol',
      message: `${hiringSignals.length} competitor hiring signal(s) detected`,
      detail: hiringSignals.map((c) => ({
        competitor: c.competitor,
        summary: c.summary,
      })),
      action: 'Analyze hiring patterns for strategic direction indicators',
    });
  }

  return findings;
}

/**
 * Check scan coverage — ensure all targets are being scanned on schedule.
 */
export function checkScanCoverage(targets: ScanTarget[]): PatrolFinding[] {
  const findings: PatrolFinding[] = [];
  const now = Date.now();

  const stale = targets.filter((t) => {
    const lastScan = new Date(t.last_scanned).getTime();
    const hoursSince = (now - lastScan) / (1000 * 60 * 60);
    return hoursSince > 24;
  });

  if (stale.length > 0) {
    findings.push({
      level: 'warning',
      source: 'mis-patrol',
      message: `${stale.length} scan target(s) not scanned in >24 hours`,
      detail: stale.map((t) => ({
        competitor: t.competitor,
        page_type: t.page_type,
        url: t.url,
        last_scanned: t.last_scanned,
      })),
      action: 'Retry failed scans and check for access issues',
    });
  }

  return findings;
}

// ── Main Patrol Runner ─────────────────────────────────────────────────

export const patrolConfig = {
  name: 'mis-competitive-scan',
  agent: 'mis',
  interval_hours: 6,
  description: 'Competitive page scanning with AI-powered change detection and significance scoring',
  dispatch_to: 'seldon',
  scan_targets: ['pricing', 'products', 'careers', 'blog', 'news'],
  change_types: CHANGE_TYPES,
};
