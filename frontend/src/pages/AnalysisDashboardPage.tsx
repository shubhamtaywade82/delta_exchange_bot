import React, { useCallback, useEffect, useState } from 'react';
import axios from 'axios';
import { LineChart, RefreshCw } from 'lucide-react';
import {
  formatQuotePrice,
  formatSignalActivityTimestamp,
  formatSmcPrice,
  sideBadgeMeta,
} from '../utils/tradingDisplay';

const DEFAULT_SMC_TF_ORDER = ['4h', '1h', '5m'] as const;

const OLLAMA_BANNER_DISMISS_KEY = 'analysis:dismiss-ollama-hint';

function smcResolutionOrder(row: {
  market_structure?: { timeframes?: { trend?: string; confirm?: string; entry?: string } };
  smc_by_timeframe?: Record<string, unknown>;
}): string[] {
  const t = row.market_structure?.timeframes;
  if (t?.trend && t?.confirm && t?.entry) return [t.trend, t.confirm, t.entry];
  if (row.smc_by_timeframe && Object.keys(row.smc_by_timeframe).length > 0) return Object.keys(row.smc_by_timeframe);
  return [...DEFAULT_SMC_TF_ORDER];
}

function readOllamaBannerDismissed(): boolean {
  if (typeof window === 'undefined') return false;
  try {
    return window.localStorage.getItem(OLLAMA_BANNER_DISMISS_KEY) === '1';
  } catch {
    return false;
  }
}

interface SmcMitigation {
  state?: string;
  pct?: number;
}

/** Last-bar payload from `Trading::Analysis::SmcConfluence::Engine` (Pine parity). */
interface SmcConfluenceLastBar {
  bar_index?: number;
  long_score?: number;
  short_score?: number;
  /** Engine serializes 1 / -1 / 0; strings may appear from other sources. */
  structure_bias?: string | number | null;
  long_signal?: boolean;
  short_signal?: boolean;
}

/** Top-level digest object from `Trading::Analysis::SmcConfluenceMtf`. */
interface SmcConfluenceMtfPayload {
  kind?: string;
  schema_version?: number;
  symbol?: string;
  generated_at_utc?: string;
  source?: string;
  timeframes?: Record<
    string,
    {
      resolution?: string;
      candle_count?: number;
      last_bar_at?: string;
      last_close?: number;
      confluence?: SmcConfluenceLastBar | null;
    }
  >;
  alignment?: Record<string, Record<string, boolean | number | string | null | undefined>>;
  notes?: string[];
}

interface SmcTfSnapshot {
  resolution?: string;
  error?: string;
  bias_hint?: string | null;
  structure_sequence?: { trend_type?: string; recent_swings?: unknown[] };
  internal_external_structure?: { divergent?: boolean; external?: unknown; internal?: unknown };
  premium_discount?: {
    zone?: string;
    close_percent_in_range?: number;
    long_filter_ok?: boolean;
    short_filter_ok?: boolean;
  };
  inducement_traps_hints?: string[];
  entry_model_flags?: Record<string, boolean>;
  choch?: { direction?: string | null; level?: number | null } | null;
  bos?: { direction?: string | null; level?: number | null; confirmed?: boolean } | null;
  fair_value_gaps?: Array<{
    type: string;
    low: number;
    high: number;
    age_bars: number;
    mitigation?: SmcMitigation;
    inverse_role_candidate?: boolean;
  }>;
  order_blocks?: Array<{
    side: string;
    high: number;
    low: number;
    age_bars: number;
    fresh: boolean;
    strength_pct: number;
    mitigation?: SmcMitigation;
    displacement_qualified?: boolean;
  }>;
  liquidity?: {
    side?: string;
    level?: number;
    interpretation?: string;
    event_style?: string;
    wick_penetration_ratio?: number;
    close_rejection_depth_ratio?: number;
  } | null;
  liquidity_pools?: { equal_high_clusters?: unknown[]; equal_low_clusters?: unknown[] };
  session_liquidity_ranges?: Record<string, { high?: number; low?: number }>;
  order_flow?: { body_ratio?: number; volume_vs_avg?: number; displacement_hint?: boolean };
  price_action_classical?: {
    pin_bar?: boolean;
    inside_bar?: boolean;
    bullish_engulfing?: boolean;
    bearish_engulfing?: boolean;
    doji_hint?: boolean;
  };
  volatility?: { atr?: number; range_vs_atr?: number; expansion_hint?: boolean };
  smc_confluence?: SmcConfluenceLastBar | null;
}

interface TradePlan {
  direction?: string;
  reason?: string;
  entry?: number | null;
  stop_loss?: number | null;
  take_profit_1?: number | null;
  take_profit_2?: number | null;
  take_profit_3?: number | null;
  risk_reward_notes?: string | null;
}

interface TradingRecommendation {
  primary_action?: string;
  conviction_0_to_100?: number;
  preferred_entry_model?: string;
  entry_guidance?: string;
  structural_stop_guidance?: string;
  target_guidance?: string | string[];
  aligns_with_htf_structure?: boolean;
  premium_discount_compliance?: string;
  liquidity_context?: string;
  key_risks?: string[];
  checklist?: string[];
}

interface AiSmcStructured {
  summary?: string;
  htf_bias?: string;
  scenario?: string;
  confidence_0_to_100?: number;
  invalidation?: string;
  takeaway_bullets?: string[];
  comment_on_plan?: string;
  timeframe_notes?: Record<string, string>;
  long_trigger_conditions?: string[];
  short_trigger_conditions?: string[];
  trading_recommendation?: TradingRecommendation;
}

interface SymbolDigest {
  symbol: string;
  error?: string | null;
  updated_at?: string;
  ai_insight?: string | null;
  ai_smc?: AiSmcStructured | null;
  smc_model_version?: string;
  mtf_alignment?: Record<string, unknown>;
  risk_and_execution_framework?: Record<string, unknown>;
  price_action?: {
    last_close: number;
    ltp: number | null;
    entry_timeframe: string;
    last_bar_at: string;
  };
  market_structure?: {
    bias: string;
    trend: string;
    confirm: string;
    entry: string;
    timeframes?: { trend: string; confirm: string; entry: string };
    adx: number | null;
    plus_di?: number | null;
    minus_di?: number | null;
    adx_threshold: number;
    trending: boolean;
  };
  timeframes?: Record<
    string,
    {
      resolution: string;
      bars: number;
      supertrend_direction: string;
      close: number;
      last_at: string;
    }
  >;
  smc_by_timeframe?: Record<string, SmcTfSnapshot>;
  smc_confluence_mtf?: SmcConfluenceMtfPayload | null;
  trade_plan?: TradePlan;
  smc?: {
    bos: {
      direction: string | null;
      level: number | null;
      confirmed: boolean;
    };
    order_blocks: Array<{
      side: string;
      high: number;
      low: number;
      age_bars: number;
      fresh: boolean;
      strength_pct: number;
    }>;
  };
}

interface AnalysisPayload {
  updated_at: string | null;
  symbols: SymbolDigest[];
  meta?: { source?: string; symbol_count?: number; error?: string | null };
}

function symbolHasAiNarrative(row: SymbolDigest): boolean {
  if (row.ai_insight?.trim()) return true;
  const a = row.ai_smc;
  if (!a || Object.keys(a).length === 0) return false;
  if (a.summary?.trim()) return true;
  if ((a.takeaway_bullets?.length ?? 0) > 0) return true;
  if (a.comment_on_plan?.trim()) return true;
  if (Object.keys(a.timeframe_notes ?? {}).length > 0) return true;
  if (a.htf_bias?.trim() || a.scenario?.trim() || a.invalidation?.trim()) return true;
  if (a.confidence_0_to_100 != null) return true;
  if (a.trading_recommendation?.primary_action?.trim()) return true;
  return false;
}

/** Confluence engine uses numeric bias: 1 bull, -1 bear, 0 neutral (JSON number). */
function formatStructureBias(bias: unknown): string {
  if (bias === 1 || bias === '1') return 'bullish';
  if (bias === -1 || bias === '-1') return 'bearish';
  if (bias === 0 || bias === '0') return 'neutral';
  if (typeof bias === 'string' && bias.trim()) return bias;
  return '—';
}

function dirClass(dir: string | number | null | undefined): string {
  if (typeof dir === 'number') {
    if (dir === 1) return 'analysis-dir-bull';
    if (dir === -1) return 'analysis-dir-bear';
    return 'analysis-dir-neutral';
  }
  const d = String(dir ?? '').toLowerCase();
  if (d.includes('bullish_aligned')) return 'analysis-dir-bullish-aligned analysis-dir-bull';
  if (d.includes('bearish_aligned')) return 'analysis-dir-bearish-aligned analysis-dir-bear';
  if (d === 'bullish' || d === 'bull') return 'analysis-dir-bull';
  if (d === 'bearish' || d === 'bear') return 'analysis-dir-bear';
  return 'analysis-dir-neutral';
}

function mitLabel(m?: SmcMitigation): string {
  if (!m?.state) return '—';
  const p = m.pct != null ? ` ${m.pct}%` : '';
  return `${m.state}${p}`;
}

function smcFreshLabel(fresh: boolean): string {
  return fresh ? 'fresh' : 'aged';
}

const CONFLUENCE_ALIGNMENT_ROWS: { key: string; label: string }[] = [
  { key: 'long_score', label: 'Long score' },
  { key: 'short_score', label: 'Short score' },
  { key: 'structure_bias', label: 'Structure bias' },
  { key: 'long_signal', label: 'Long signal' },
  { key: 'short_signal', label: 'Short signal' },
  { key: 'choch_bull', label: 'CHOCH bull' },
  { key: 'choch_bear', label: 'CHOCH bear' }
];

function formatAlignCell(
  metricKey: string,
  value: boolean | number | string | null | undefined
): React.ReactNode {
  if (value === undefined || value === null) return '—';
  if (typeof value === 'boolean') return value ? 'yes' : 'no';
  if (typeof value === 'number') {
    if (metricKey === 'structure_bias') {
      return <span className={dirClass(value)}>{formatStructureBias(value)}</span>;
    }
    return String(value);
  }
  if (typeof value === 'string') {
    return <span className={dirClass(value)}>{value}</span>;
  }
  return String(value);
}

function SmcConfluenceMtfSection({
  mtf,
  resolutionOrder
}: {
  mtf?: SmcConfluenceMtfPayload | null;
  resolutionOrder: string[];
}) {
  if (!mtf || mtf.kind !== 'smc_confluence_mtf') return null;
  const align = mtf.alignment;
  if (!align || typeof align !== 'object') return null;

  return (
    <div className="dense-group full-width border-top smc-confluence-section">
      <div className="smc-section-title-row smc-section-title-compact">
        <span className="dense-label">SMC confluence (last bar per TF)</span>
        <span className="smc-source-pill smc-source-rules">Engine</span>
      </div>
      <div className="smc-conf-align-table">
        <div className="smc-conf-align-row smc-conf-align-head">
          <span>Metric</span>
          {resolutionOrder.map(tf => (
            <span key={tf}>{tf}</span>
          ))}
        </div>
        {CONFLUENCE_ALIGNMENT_ROWS.map(row => (
          <div key={row.key} className="smc-conf-align-row">
            <span className="smc-conf-metric-label">{row.label}</span>
            {resolutionOrder.map(tf => (
              <span key={tf}>{formatAlignCell(row.key, align[row.key]?.[tf])}</span>
            ))}
          </div>
        ))}
      </div>
      {mtf.generated_at_utc && (
        <p className="text-muted small smc-conf-meta">Confluence MTF generated {mtf.generated_at_utc} (UTC)</p>
      )}
    </div>
  );
}

function SmcTimeframePanel({ label, snap }: { label: string; snap?: SmcTfSnapshot }) {
  if (!snap) {
    return (
      <div className="smc-tf-panel">
        <div className="smc-tf-head">{label}</div>
        <p className="text-muted smc-panel-empty">No snapshot for this timeframe.</p>
      </div>
    );
  }
  if (snap.error) {
    return (
      <div className="smc-tf-panel smc-tf-panel-warn">
        <div className="smc-tf-head">{label}</div>
        <p className="analysis-error smc-panel-empty">{snap.error}</p>
      </div>
    );
  }

  const choch = snap.choch;
  const bos = snap.bos;
  const liq = snap.liquidity;

  return (
    <div className="smc-tf-panel">
      <div className="smc-tf-head">
        <span className="smc-tf-title">{label}</span>
        {snap.bias_hint && (
          <span className={`smc-bias-tag ${dirClass(snap.bias_hint)}`}>{snap.bias_hint}</span>
        )}
      </div>

      {snap.smc_confluence && (
        <p
          className="smc-confluence-strip text-muted small"
          title="Pine-parity confluence engine on the last bar in the fetched window"
        >
          Confluence: L {snap.smc_confluence.long_score ?? '—'} / S {snap.smc_confluence.short_score ?? '—'} ·{' '}
          <span className={dirClass(snap.smc_confluence.structure_bias ?? undefined)}>
            {formatStructureBias(snap.smc_confluence.structure_bias)}
          </span>
          {' · '}
          sig{' '}
          {[snap.smc_confluence.long_signal && 'L', snap.smc_confluence.short_signal && 'S']
            .filter(Boolean)
            .join(' ') || '—'}
        </p>
      )}

      <div className="smc-microgrid">
        <div className="smc-kv">
          <abbr className="dense-label smc-abbr" title="Change of character — potential shift in internal structure">
            CHOCH
          </abbr>
          <span className={`dense-val smc-kv-val ${dirClass(choch?.direction ?? undefined)}`}>
            {(choch?.direction ?? '—').toUpperCase()} @ {formatSmcPrice(choch?.level ?? null)}
          </span>
        </div>
        <div className="smc-kv">
          <abbr className="dense-label smc-abbr" title="Break of structure — continuation vs reversal cue">
            BOS
          </abbr>
          <span className={`dense-val smc-kv-val ${dirClass(bos?.direction ?? undefined)}`}>
            {(bos?.direction ?? '—').toUpperCase()} @ {formatSmcPrice(bos?.level ?? null)}
            {bos?.confirmed ? ' (confirmed)' : ''}
          </span>
        </div>
        <div className="smc-kv smc-kv-wide">
          <span className="dense-label">LIQUIDITY</span>
          <span className="dense-val smc-kv-val smc-liq-wrap">
            {liq
              ? `${liq.side?.toUpperCase() ?? '—'} @ ${formatSmcPrice(liq.level ?? null)} — ${liq.interpretation ?? '—'}${liq.event_style ? ` (${liq.event_style})` : ''}`
              : '—'}
          </span>
        </div>
      </div>

      <div className="smc-context-row">
        <span title="Swing sequence trend (HH/HL/LH/LL)">
          ST: <strong>{snap.structure_sequence?.trend_type ?? '—'}</strong>
        </span>
        <span title="Premium / discount vs recent range">
          PD: <strong>{snap.premium_discount?.zone ?? '—'}</strong>
          {snap.premium_discount?.close_percent_in_range != null && (
            <span className="smc-pd-pct"> ({snap.premium_discount.close_percent_in_range}%)</span>
          )}
        </span>
        <span title="Order-flow proxy (body vs range, volume)">
          Disp:{' '}
          <strong>{snap.order_flow?.displacement_hint ? 'yes' : 'no'}</strong>
        </span>
        <span title="ATR range ratio">
          ATR×: <strong>{snap.volatility?.range_vs_atr ?? '—'}</strong>
        </span>
      </div>

      {(snap.inducement_traps_hints?.length ?? 0) > 0 && (
        <p className="smc-hints text-muted small">
          Hints: {snap.inducement_traps_hints!.join(' · ')}
        </p>
      )}

      <div className="smc-subhdr-wrap">
        <span className="dense-label smc-subhdr">Fair value gaps</span>
        <span className="smc-subhdr-hint">fill %</span>
      </div>
      <div className="dense-ob-list smc-scroll-list">
        {(snap.fair_value_gaps?.length ?? 0) === 0 ? (
          <span className="text-muted smc-panel-empty">None detected</span>
        ) : (
          snap.fair_value_gaps!.map((f, i) => (
            <div
              key={i}
              className={`ob-compact-pill ob-compact-pill-smc ${dirClass(f.type === 'bullish' ? 'bullish' : 'bearish')}`}
            >
              <span className="ob-side">{f.type.toUpperCase()}</span>
              <span className="ob-range">
                {formatSmcPrice(f.low)} – {formatSmcPrice(f.high)}
              </span>
              <span className="ob-meta ob-meta-stack">
                <span>
                  {f.age_bars} bar{f.age_bars === 1 ? '' : 's'} old
                </span>
                <span className="ob-mit">
                  {mitLabel(f.mitigation)}
                  {f.inverse_role_candidate ? ' · inv?' : ''}
                </span>
              </span>
            </div>
          ))
        )}
      </div>

      <div className="smc-subhdr-wrap">
        <span className="dense-label smc-subhdr">Order blocks</span>
        <span className="smc-subhdr-hint">fresh / aged</span>
      </div>
      <div className="dense-ob-list smc-scroll-list">
        {(snap.order_blocks?.length ?? 0) === 0 ? (
          <span className="text-muted smc-panel-empty">None detected</span>
        ) : (
          snap.order_blocks!.map((ob, i) => (
            <div
              key={i}
              className={`ob-compact-pill ob-compact-pill-smc ${dirClass(ob.side === 'bull' ? 'bullish' : 'bearish')}`}
            >
              <span className="ob-side">{ob.side.toUpperCase()}</span>
              <span className="ob-range">
                {formatSmcPrice(ob.low)} – {formatSmcPrice(ob.high)}
              </span>
              <span className="ob-meta ob-meta-stack">
                <span>
                  {ob.age_bars} bar{ob.age_bars === 1 ? '' : 's'} · {smcFreshLabel(ob.fresh)}
                </span>
                <span className="ob-mit">
                  {mitLabel(ob.mitigation)}
                  {ob.displacement_qualified === false ? ' · low disp' : ''}
                </span>
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function TradePlanBlock({ plan }: { plan?: TradePlan }) {
  if (!plan) return null;
  if (plan.direction === 'none' || !plan.direction) {
    return (
      <div className="dense-group full-width border-top trade-plan-block">
        <div className="smc-section-title-row">
          <span className="dense-label">Heuristic trade plan</span>
          <span className="smc-source-pill smc-source-rules">Rules</span>
        </div>
        <p className="text-muted smc-panel-empty">No active plan ({plan.reason ?? 'n/a'})</p>
      </div>
    );
  }
  const labelDir = plan.direction.toUpperCase();
  return (
    <div className="dense-group full-width border-top trade-plan-block">
      <div className="smc-section-title-row">
        <span className="dense-label">Heuristic trade plan ({labelDir})</span>
        <span className="smc-source-pill smc-source-rules">Rules</span>
      </div>
      <div className="trade-plan-grid">
        <div className="tp-cell">
          <span className="dense-label">ENTRY</span>
          <span className="dense-val">{formatQuotePrice(plan.entry ?? null)}</span>
        </div>
        <div className="tp-cell">
          <span className="dense-label">SL</span>
          <span className="dense-val">{formatQuotePrice(plan.stop_loss ?? null)}</span>
        </div>
        <div className="tp-cell">
          <span className="dense-label">TP1</span>
          <span className="dense-val">{formatQuotePrice(plan.take_profit_1 ?? null)}</span>
        </div>
        <div className="tp-cell">
          <span className="dense-label">TP2</span>
          <span className="dense-val">{formatQuotePrice(plan.take_profit_2 ?? null)}</span>
        </div>
        <div className="tp-cell">
          <span className="dense-label">TP3</span>
          <span className="dense-val">{formatQuotePrice(plan.take_profit_3 ?? null)}</span>
        </div>
      </div>
      {plan.risk_reward_notes && <p className="text-muted small trade-plan-notes">{plan.risk_reward_notes}</p>}
    </div>
  );
}

function AiSmcBlock({ ai }: { ai?: AiSmcStructured | null }) {
  if (!ai || Object.keys(ai).length === 0) return null;
  const bullets = ai.takeaway_bullets ?? [];
  const tfNotes = ai.timeframe_notes ?? {};
  return (
    <div className="dense-group full-width border-top ai-smc-structured">
      <div className="smc-section-title-row">
        <span className="dense-label ai-label">AI read (Ollama)</span>
        <span className="smc-source-pill smc-source-ai">LLM</span>
      </div>
      {ai.summary && <p className="ai-insight-text">{ai.summary}</p>}
      <div className="ai-smc-meta">
        {ai.htf_bias && (
          <span className={`ai-chip ${dirClass(ai.htf_bias)}`}>BIAS: {ai.htf_bias}</span>
        )}
        {ai.scenario && <span className="ai-chip">SCENARIO: {ai.scenario}</span>}
        {ai.confidence_0_to_100 != null && (
          <span className="ai-chip">CONF: {ai.confidence_0_to_100}</span>
        )}
      </div>
      {ai.invalidation && (
        <p className="text-muted small">
          <strong>INVALIDATION:</strong> {ai.invalidation}
        </p>
      )}
      {bullets.length > 0 && (
        <ul className="ai-smc-bullets">
          {bullets.map((b, i) => (
            <li key={i}>{b}</li>
          ))}
        </ul>
      )}
      {ai.comment_on_plan && (
        <p className="text-muted small">
          <strong>PLAN:</strong> {ai.comment_on_plan}
        </p>
      )}

      {((ai.long_trigger_conditions?.length ?? 0) > 0 || (ai.short_trigger_conditions?.length ?? 0) > 0) && (
        <div className="ai-trigger-conditions">
          {(ai.long_trigger_conditions?.length ?? 0) > 0 && (
            <div className="ai-trigger-block ai-trigger-long">
              <div className="ai-trigger-head">
                <span className="ai-trigger-icon">🟢</span>
                <span className="dense-label">CONSIDER LONG WHEN</span>
              </div>
              <ul className="ai-smc-bullets">
                {ai.long_trigger_conditions!.map((c, i) => (
                  <li key={i}>{c}</li>
                ))}
              </ul>
            </div>
          )}
          {(ai.short_trigger_conditions?.length ?? 0) > 0 && (
            <div className="ai-trigger-block ai-trigger-short">
              <div className="ai-trigger-head">
                <span className="ai-trigger-icon">🔴</span>
                <span className="dense-label">CONSIDER SHORT WHEN</span>
              </div>
              <ul className="ai-smc-bullets">
                {ai.short_trigger_conditions!.map((c, i) => (
                  <li key={i}>{c}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      {Object.keys(tfNotes).length > 0 && (
        <div className="ai-tf-notes">
          {Object.entries(tfNotes).map(([tf, note]) => (
            <div key={tf} className="ai-tf-note-row">
              <span className="dense-label">{tf.toUpperCase()}</span>
              <span className="small">{note}</span>
            </div>
          ))}
        </div>
      )}

      {ai.trading_recommendation && (
        <div className="ai-trading-rec">
          <div className="dense-label smc-subhdr">Trading recommendation</div>
          {(() => {
            const r = ai.trading_recommendation!;
            const badge = sideBadgeMeta(r.primary_action);
            return (
              <>
                <div className="ai-rec-head">
                  <span className={`mode-badge smc-rec-action smc-rec-${badge.css}`}>{r.primary_action?.toUpperCase() ?? '—'}</span>
                  {r.conviction_0_to_100 != null && (
                    <span className="ai-chip">CONV: {r.conviction_0_to_100}</span>
                  )}
                  {r.preferred_entry_model && <span className="ai-chip">MODEL: {r.preferred_entry_model}</span>}
                  {r.aligns_with_htf_structure != null && (
                    <span className="ai-chip">HTF: {r.aligns_with_htf_structure ? 'aligned' : 'conflict'}</span>
                  )}
                </div>
                {r.entry_guidance && <p className="small ai-rec-line">{r.entry_guidance}</p>}
                {r.structural_stop_guidance && (
                  <p className="small ai-rec-line">
                    <strong>Stop:</strong> {r.structural_stop_guidance}
                  </p>
                )}
                {r.target_guidance != null && (
                  <p className="small ai-rec-line">
                    <strong>Targets:</strong>{' '}
                    {Array.isArray(r.target_guidance) ? r.target_guidance.join(' · ') : r.target_guidance}
                  </p>
                )}
                {r.premium_discount_compliance && (
                  <p className="small text-muted">PD: {r.premium_discount_compliance}</p>
                )}
                {r.liquidity_context && (
                  <p className="small text-muted">Liq: {r.liquidity_context}</p>
                )}
                {(r.key_risks?.length ?? 0) > 0 && (
                  <ul className="ai-smc-bullets ai-rec-risks">
                    {r.key_risks!.map((x, i) => (
                      <li key={i}>
                        <strong>Risk:</strong> {x}
                      </li>
                    ))}
                  </ul>
                )}
                {(r.checklist?.length ?? 0) > 0 && (
                  <ul className="ai-smc-bullets ai-rec-check">
                    {r.checklist!.map((x, i) => (
                      <li key={i}>{x}</li>
                    ))}
                  </ul>
                )}
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
}

function AiSynthesisSection({
  aiSmc,
  aiInsight,
}: {
  aiSmc?: AiSmcStructured | null;
  aiInsight?: string | null;
}) {
  const hasStructured = aiSmc && Object.keys(aiSmc).length > 0;
  if (hasStructured) {
    return <AiSmcBlock ai={aiSmc} />;
  }
  if (aiInsight) {
    return (
      <div className="dense-group full-width border-top ai-insight-block">
        <div className="smc-section-title-row">
          <span className="dense-label ai-label">AI synthesis (Ollama)</span>
          <span className="smc-source-pill smc-source-ai">LLM</span>
        </div>
        <p className="ai-insight-text">
          <span className="ai-sparkle">✨</span> {aiInsight}
        </p>
      </div>
    );
  }
  return null;
}

const AnalysisDashboardPage: React.FC = () => {
  const [data, setData] = useState<AnalysisPayload | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [inFlight, setInFlight] = useState(false);
  const [hadFirstLoad, setHadFirstLoad] = useState(false);
  const [selectedSymbol, setSelectedSymbol] = useState<string | null>(null);
  const [ollamaBannerDismissed, setOllamaBannerDismissed] = useState(readOllamaBannerDismissed);

  const dismissOllamaBanner = useCallback(() => {
    try {
      window.localStorage.setItem(OLLAMA_BANNER_DISMISS_KEY, '1');
    } catch {
      /* ignore quota / private mode */
    }
    setOllamaBannerDismissed(true);
  }, []);

  const fetchData = useCallback(async (opts?: { silent?: boolean }) => {
    if (!opts?.silent) setInFlight(true);
    try {
      const { data: body } = await axios.get<AnalysisPayload>('/api/analysis_dashboard');
      setData(body);
      setLoadError(null);
      
      // Auto-select first symbol if none selected
      if (!selectedSymbol && body.symbols?.length > 0) {
        setSelectedSymbol(body.symbols[0].symbol);
      }
    } catch (e) {
      setLoadError('Failed to load analysis snapshot');
      console.error(e);
    } finally {
      if (!opts?.silent) setInFlight(false);
      setHadFirstLoad(true);
    }
  }, [selectedSymbol]);

  useEffect(() => {
    fetchData();
    const id = setInterval(() => fetchData({ silent: true }), 30_000);
    return () => clearInterval(id);
  }, [fetchData]);

  return (
    <div className="terminal-main analysis-page">
      <header className="analysis-page-header">
        <div className="header-title-group">
          <LineChart size={22} className="icon-accent" />
          <div>
            <h1>ANALYSIS_DASHBOARD</h1>
            <p className="analysis-subtitle">
              SMC multi-timeframe (config: trend / confirm / entry, e.g. 4h / 1h / 5m) + trade ladder:{' '}
              <strong>Rails rules</strong>. Ollama summary: <strong>optional</strong>. Queue refresh + 30s poll.
            </p>
            <details className="analysis-help-details">
              <summary>Details</summary>
              <p>
                CHOCH/BOS/FVG/order blocks are deterministic from OHLC. Heuristic entry/SL/TP uses the same snapshot.
                When the analysis job calls Ollama, a narrative appears in each symbol card; otherwise cards stay
                rule-only (no repeated “AI off” blocks).
              </p>
            </details>
          </div>
        </div>
        <button type="button" className="analysis-refresh-btn" onClick={() => fetchData()} disabled={inFlight}>
          <RefreshCw size={16} className={inFlight ? 'spin' : ''} />
          REFRESH
        </button>
      </header>

      {loadError && <div className="analysis-banner neg">{loadError}</div>}

      <div className="analysis-meta-bar">
        <span>
          SNAPSHOT:{' '}
          {data?.updated_at ? formatSignalActivityTimestamp(data.updated_at) : !hadFirstLoad ? '…' : '—'}
        </span>
        <span className="sep">|</span>
        <span>SYMBOLS: {data?.symbols?.length ?? 0}</span>
        {data?.meta?.source && (
          <>
            <span className="sep">|</span>
            <span>SOURCE: {data.meta.source}</span>
          </>
        )}
      </div>

      {hadFirstLoad &&
        !ollamaBannerDismissed &&
        (data?.symbols?.length ?? 0) > 0 &&
        !(data?.symbols ?? []).some(s => !s.error && symbolHasAiNarrative(s)) && (
          <div className="analysis-once-hint" role="status">
            <div className="analysis-once-hint-top">
              <p className="analysis-once-hint-lead">
                No Ollama narrative in this snapshot — SMC cards are still the rule engine.
              </p>
              <button type="button" className="analysis-hint-dismiss" onClick={dismissOllamaBanner}>
                Dismiss
              </button>
            </div>
            <details className="analysis-ollama-setup">
              <summary>How to populate AI fields</summary>
              <ol className="analysis-ollama-setup-list">
                <li>
                  <strong>Solid Queue (required for scheduled refresh):</strong> run{' '}
                  <code>cd backend &amp;&amp; bin/jobs start</code> in a dedicated terminal, or use{' '}
                  <code>foreman start</code> / the Procfile <code>jobs</code> process so{' '}
                  <code>Trading::AnalysisDashboardRefreshJob</code> runs (see <code>config/recurring.yml</code>, every
                  15 minutes). Without this, the Redis snapshot may be stale or never rebuilt with Ollama.
                </li>
                <li>
                  <strong>One-shot refresh:</strong>{' '}
                  <code>{`bin/rails runner 'Trading::AnalysisDashboardRefreshJob.perform_now'`}</code>
                </li>
                <li>
                  Run Ollama locally: <code>ollama serve</code>, then <code>ollama pull llama3</code> (or whichever tag
                  you use).
                </li>
                <li>
                  <strong>Ollama Cloud:</strong> set <code>OLLAMA_API_KEY</code> (from ollama.com keys). With the default
                  DB URL still on localhost, the app switches the host to <code>https://ollama.com</code> and sends Bearer
                  auth. Use a cloud model name (e.g. <code>gpt-oss:120b-cloud</code>) in <code>OLLAMA_MODEL</code> /{' '}
                  <code>ai.ollama_model</code>. To keep a local server despite a key in env, set{' '}
                  <code>OLLAMA_FORCE_LOCAL=true</code> or <code>ai.ollama_force_local</code>.
                </li>
                <li>
                  Local Ollama: <code>OLLAMA_URL</code> (default <code>http://127.0.0.1:11434</code>) and{' '}
                  <code>OLLAMA_MODEL</code> matching a pulled model.
                </li>
                <li>
                  Or set runtime settings <code>ai.ollama_url</code> / <code>ai.ollama_model</code> (see{' '}
                  <code>db/seeds.rb</code>) if you use DB-backed config.
                </li>
                <li>
                  If it still stays empty, check logs for <code>[AiSmcSynthesizer]</code> — common causes: Ollama down,
                  wrong model name, <code>OLLAMA_TIMEOUT_SECONDS</code> too low for large SMC JSON, or the model returning
                  non-JSON.
                </li>
              </ol>
            </details>
          </div>
        )}

      {data?.symbols && data.symbols.length > 0 && (
        <div className="analysis-tabs">
          {data.symbols.map(s => (
            <button
              key={s.symbol}
              type="button"
              className={`analysis-tab-btn ${selectedSymbol === s.symbol ? 'active' : ''}`}
              onClick={() => setSelectedSymbol(s.symbol)}
            >
              <span className={`dot ${s.error ? 'neg' : 'online'}`} />
              {s.symbol}
            </button>
          ))}
        </div>
      )}

      <div className="analysis-symbol-detail">
        {(() => {
          const row = (data?.symbols ?? []).find(s => s.symbol === selectedSymbol);
          if (!row) return null;

          const smcTfOrder = smcResolutionOrder(row);
          const msTf = row.market_structure?.timeframes;
          const structureTfLabel = msTf ? `${msTf.trend} / ${msTf.confirm} / ${msTf.entry}` : smcTfOrder.join(' / ');
          const adxTfLabel = msTf?.confirm ?? 'confirm';

          return (
            <div key={row.symbol} className="detail-view-container animate-fade-in">
              <div className="detail-header-compact">
                <div className="header-title-group">
                  <h2>{row.symbol}</h2>
                  {row.error ? (
                    <span className="mode-badge blocked">ERROR</span>
                  ) : (
                    <span className="mode-badge live">OK</span>
                  )}
                  {row.error && row.updated_at && (
                    <p className="text-muted small analysis-digest-meta">
                      Digest record: {formatSignalActivityTimestamp(row.updated_at)}
                    </p>
                  )}
                </div>
                
                {!row.error && (
                  <div className="detail-header-stats">
                    <div className="header-verdict-group">
                      {row.ai_smc?.trading_recommendation?.primary_action && (
                        <>
                          <div className={`header-action-badge action-${row.ai_smc.trading_recommendation.primary_action.toLowerCase()}`}>
                            {row.ai_smc.trading_recommendation.primary_action}
                          </div>
                          {row.ai_smc.trading_recommendation.conviction_0_to_100 != null && (
                            <div className="header-conviction">
                              <label>AI CONV</label>
                              <span className="val">{row.ai_smc.trading_recommendation.conviction_0_to_100}%</span>
                            </div>
                          )}
                        </>
                      )}
                    </div>

                    <div className="detail-stat">
                      <label>LTP / CLOSE</label>
                      <span className="value">
                        {row.price_action?.ltp
                          ? formatQuotePrice(row.price_action.ltp)
                          : formatQuotePrice(row.price_action?.last_close)}
                      </span>
                    </div>
                    <div className="detail-stat">
                      <label>BIAS</label>
                      <span className={`value dense-bias ${dirClass(row.market_structure?.bias)}`}>
                        {(row.market_structure?.bias ?? '—').replace(/_/g, ' ')}
                      </span>
                    </div>
                    <div className="detail-stat">
                      <label>ADX ({adxTfLabel})</label>
                      <span className="value">
                        {formatQuotePrice(row.market_structure?.adx)}{' '}
                        <span className={row.market_structure?.trending ? 'text-trend' : 'text-range'}>
                          {row.market_structure?.trending ? 'TREND' : 'RANGE'}
                        </span>
                      </span>
                    </div>
                    {row.updated_at && (
                      <div className="detail-stat">
                        <label>DIGEST BUILT</label>
                        <span className="value">{formatSignalActivityTimestamp(row.updated_at)}</span>
                      </div>
                    )}
                    {row.price_action?.last_bar_at && (
                      <div className="detail-stat">
                        <label>
                          LAST BAR ({(row.price_action.entry_timeframe ?? 'entry').toUpperCase()})
                        </label>
                        <span className="value">
                          {formatSignalActivityTimestamp(row.price_action.last_bar_at)}
                        </span>
                      </div>
                    )}
                  </div>
                )}
              </div>

              {row.error ? (
                <div className="terminal-section">
                  <p className="analysis-error padding-1-5">{row.error}</p>
                </div>
              ) : (
                <div className="analysis-detail-layout">
                  {/* LEFT COLUMN: AI & Recommendations */}
                  <div className="detail-main-col">
                    <section className="terminal-section">
                      <div className="section-header">
                        <h2>AI_INTERPRETATION</h2>
                      </div>
                      <div className="padding-1-5">
                        {row.ai_smc?.trading_recommendation && (
                          <div className="ai-verdict-card">
                            <div className="ai-verdict-title">
                              <span>FINAL_VERDICT</span>
                              <span className={`smc-rec-action smc-rec-${sideBadgeMeta(row.ai_smc.trading_recommendation.primary_action).css}`}>
                                {row.ai_smc.trading_recommendation.primary_action?.toUpperCase()}
                              </span>
                            </div>
                            <div className="ai-verdict-body">
                              {row.ai_smc.trading_recommendation.entry_guidance || row.ai_smc.summary || "No specific guidance provided."}
                            </div>
                          </div>
                        )}
                        <AiSynthesisSection aiSmc={row.ai_smc} aiInsight={row.ai_insight} />
                        {!symbolHasAiNarrative(row) && (
                          <p className="text-muted small">No AI narrative generated for this snapshot.</p>
                        )}
                      </div>
                    </section>

                    <section className="terminal-section">
                      <div className="section-header">
                        <h2>MARKET_STRUCTURE_BIAS</h2>
                      </div>
                      <div className="padding-1-5">
                         <div className="dense-multi-row">
                          <div className="dense-group">
                            <span className="dense-label">STRUCTURE ({structureTfLabel})</span>
                            <div className="dense-pills">
                              <span className={dirClass(row.market_structure?.trend)}>
                                {row.market_structure?.trend?.substring(0, 4).toUpperCase() || '—'}
                              </span>
                              <span className={dirClass(row.market_structure?.confirm)}>
                                {row.market_structure?.confirm?.substring(0, 4).toUpperCase() || '—'}
                              </span>
                              <span className={dirClass(row.market_structure?.entry)}>
                                {row.market_structure?.entry?.substring(0, 4).toUpperCase() || '—'}
                              </span>
                            </div>
                          </div>

                          <div className="dense-group">
                            <span className="dense-label">ST ({structureTfLabel})</span>
                            <div className="dense-pills">
                              {row.timeframes &&
                                ['trend', 'confirm', 'entry'].map(tfKey => {
                                  const tf = row.timeframes![tfKey];
                                  if (!tf) return <span key={tfKey}>—</span>;
                                  return (
                                    <span key={tfKey} className={dirClass(tf.supertrend_direction)}>
                                      {tf.supertrend_direction?.substring(0, 4).toUpperCase() || '—'}
                                    </span>
                                  );
                                })}
                            </div>
                          </div>
                        </div>
                      </div>
                    </section>
                  </div>

                  {/* RIGHT COLUMN: Technical Rules & Plan */}
                  <div className="detail-side-col">
                    <section className="terminal-section">
                      <div className="section-header">
                        <h2>TECHNICAL_EVIDENCE (SMC)</h2>
                      </div>
                      <div className="padding-1-5">
                        <SmcConfluenceMtfSection mtf={row.smc_confluence_mtf} resolutionOrder={smcTfOrder} />
                        <div className="dense-group full-width border-top smc-algo-section">
                          <div className="smc-section-title-row smc-section-title-compact">
                            <span className="dense-label">SMC · {smcTfOrder.join(' / ')}</span>
                            <span className="smc-source-pill smc-source-rules">Rules</span>
                          </div>
                          <div className="smc-tf-grid">
                            {smcTfOrder.map(tf => (
                              <SmcTimeframePanel key={tf} label={tf} snap={row.smc_by_timeframe?.[tf]} />
                            ))}
                          </div>
                        </div>
                      </div>
                    </section>

                    <section className="terminal-section">
                      <div className="section-header">
                        <h2>EXECUTION_PLAN</h2>
                      </div>
                      <div className="padding-1-5">
                        <TradePlanBlock plan={row.trade_plan} />
                      </div>
                    </section>
                  </div>
                </div>
              )}
            </div>
          );
        })()}
      </div>

      {hadFirstLoad && (data?.symbols?.length ?? 0) === 0 && (
        <p className="text-muted analysis-empty">
          No snapshot yet. Ensure Solid Queue is running and `Trading::AnalysisDashboardRefreshJob` has executed at
          least once (scheduled every 15 minutes), or run the job manually in Rails console.
        </p>
      )}
    </div>
  );
};

export default AnalysisDashboardPage;
