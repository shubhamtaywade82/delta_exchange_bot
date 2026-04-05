import React, { useState, useEffect, useCallback, useMemo } from 'react';
import axios from 'axios';
import { useLiveLtp } from '../liveLtp/liveLtpContext';
import {
  Wallet,
  History,
  Cpu,
  BarChart3,
  Activity,
} from 'lucide-react';
import type { SignalActivity } from '../types/operationalState';
import {
  formatDisplayDecimal,
  formatInr,
  formatQuotePrice,
  formatSignalActivityTimestamp,
  formatUsd,
  sideBadgeMeta,
} from '../utils/tradingDisplay';
import { FlashValue } from '../components/common/FlashValue';


interface FilterResult {
  passed: boolean;
  reason: string;
}

interface OrderBlock {
  price: number;
  type: 'demand' | 'supply';
}

interface SymbolState {
  symbol: string;
  trend_dir?: string;
  confirm_dir?: string;
  entry_dir?: string;
  adx?: number;
  signal?: string;
  updated_at?: string;
  bos_direction?: string;
  bos_level?: number;
  rsi?: number;
  vwap?: number;
  vwap_deviation_pct?: number;
  order_blocks?: OrderBlock[];
  cvd_trend?: string;
  cvd_delta?: number;
  oi_usd?: number;
  oi_trend?: string;
  funding_rate?: number;
  funding_extreme?: boolean;
  filters?: {
    momentum?: FilterResult;
    volume?: FilterResult;
    derivatives?: FilterResult;
  };
}

interface StrategyStatus {
  strategy: {
    name: string;
    description: string;
    mode: string;
    timeframes: { tf: string; role: string; indicator: string }[];
  };
  symbols: SymbolState[];
}

interface ExitSummaryTrailing {
  trigger_price: number;
  room_pct: number;
  at_risk: boolean;
}

interface ExitSummaryLiquidation {
  trigger_price: number;
  distance_pct: number;
  within_near_liquidation_band: boolean;
}

interface ExitSummaryNearest {
  kind: string;
  room_pct: number;
  trigger_price?: number;
  note?: string;
}

interface PositionExitSummary {
  trailing_stop?: ExitSummaryTrailing;
  liquidation?: ExitSummaryLiquidation;
  nearest_exit?: ExitSummaryNearest;
}

interface ApiPosition {
  id?: number;
  symbol: string;
  side?: string;
  entry_price?: number | null;
  opened_at?: string | null;
  mark_price?: number | null;
  size?: number | null;
  leverage?: number | null;
  unrealized_pnl?: number | null;
  unrealized_pnl_inr?: number | null;
  unrealized_pnl_pct?: number | null;
  exit_summary?: PositionExitSummary;
}

interface ApiTrade {
  symbol: string;
  side?: string;
  size?: number | null;
  entry_price?: number | null;
  exit_price?: number | null;
  pnl_inr?: number | null;
  timestamp?: string | null;
}

interface ApiWallet {
  cash_balance_usd?: number | null;
  cash_balance_inr?: number | null;
  unrealized_pnl_usd?: number | null;
  unrealized_pnl_inr?: number | null;
  total_equity_usd?: number | null;
  total_equity_inr?: number | null;
  blocked_margin_usd?: number | null;
  blocked_margin_inr?: number | null;
  available_usd?: number | null;
  available_inr?: number | null;
  updated_at?: string | null;
  stale?: boolean;
  ledger_margin_exceeds_cash?: boolean;
}

interface ApiStats {
  equity_curve?: number[];
  daily_pnl?: number | null;
  weekly_pnl?: number | null;
}

function exitProximityTitle(p: ApiPosition, displayLtp: number | null | undefined): string {
  const ex = p.exit_summary;
  const lines: string[] = [
    'Automated exit proximity (price space vs server LTP / mark used in this row).',
    'Trailing: runner exits when LTP crosses stop (after grace).',
    'Liquidation: same distance definition as NearLiquidationExit (live).',
  ];
  if (displayLtp != null && Number.isFinite(displayLtp)) {
    lines.push(`UI LTP (if live): ${formatQuotePrice(displayLtp)} — exit math uses server mark unless you refresh.`);
  }
  if (!ex?.trailing_stop && !ex?.liquidation) {
    lines.push('No stop_price or liquidation_price on this position row.');
    return lines.join('\n');
  }
  if (ex.trailing_stop) {
    const t = ex.trailing_stop;
    lines.push(
      `Trailing stop: $${formatQuotePrice(t.trigger_price)} · room ${formatDisplayDecimal(t.room_pct)}% · at_risk=${t.at_risk}`,
    );
  }
  if (ex.liquidation) {
    const l = ex.liquidation;
    lines.push(
      `Liquidation: $${formatQuotePrice(l.trigger_price)} · distance ${formatDisplayDecimal(l.distance_pct)}% · near_liq_band=${l.within_near_liquidation_band}`,
    );
  }
  return lines.join('\n');
}

function exitProximityCell(p: ApiPosition): { text: string; className: string } {
  const ex = p.exit_summary;
  const nearest = ex?.nearest_exit;
  if (nearest?.note === 'at_or_past_stop') {
    return { text: 'AT_STOP', className: 'neg font-bold' };
  }
  if (!nearest) {
    if (!ex?.trailing_stop && !ex?.liquidation) {
      return { text: '—', className: 'text-muted' };
    }
    return { text: '—', className: 'text-muted' };
  }
  const label = nearest.kind === 'liquidation' ? 'LIQ' : 'TRAIL';
  const tight = nearest.room_pct <= 0.15;
  return {
    text: `${label} ${formatDisplayDecimal(nearest.room_pct)}%`,
    className: tight ? 'neg' : 'text-zinc-300',
  };
}

function filterBadge(result?: FilterResult) {
  if (!result) return null;
  return (
    <span className={`dir-badge-sm ${result.passed ? 'bullish' : 'bearish'}`}
          title={result.reason}>
      {result.passed ? '✓' : '✗'}
    </span>
  );
}

function trendArrow(trend?: string) {
  return trend === 'rising' || trend === 'bullish' ? '▲' : '▼';
}

/** Local calendar date YYYY-MM-DD (not UTC) — matches how users pick "today" in the date control. */
function localCalendarDateISO(d = new Date()) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** YYYY-MM-DD → localized medium date for dropdown labels */
function formatTradeHistoryDayLabel(iso: string) {
  const parts = iso.split('-').map(Number);
  if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return iso;
  const [y, m, d] = parts;
  return new Date(y, m - 1, d).toLocaleDateString(undefined, { dateStyle: 'medium' });
}

/** Free cash = balance − blocked margin; negative means IM exceeds cash. */
function walletCashValueClassName(value: unknown): string {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return 'wallet-value';
  if (n < 0) return 'wallet-value neg';
  return 'wallet-value pos';
}

/** Signed PnL-style coloring (zero is neutral). */
function walletSignedValueClassName(value: unknown): string {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return 'wallet-value';
  if (n < 0) return 'wallet-value neg';
  if (n > 0) return 'wallet-value pos';
  return 'wallet-value';
}

function SignalQualityPanel({ sym }: { sym: SymbolState }) {
  const allFilters = sym.filters;
  const allPassed = allFilters &&
    allFilters.momentum?.passed &&
    allFilters.volume?.passed &&
    allFilters.derivatives?.passed;

  const blockedReason = allFilters && (
    (!allFilters.momentum?.passed && allFilters.momentum?.reason) ||
    (!allFilters.volume?.passed && allFilters.volume?.reason) ||
    (!allFilters.derivatives?.passed && allFilters.derivatives?.reason)
  );

  return (
    <div className="signal-analysis-card">
      <div className="analysis-grid">
        <div className="analysis-item">
          <label>MOMENTUM</label>
          <div className="item-content">
            <span className="value">
              RSI <FlashValue value={sym.rsi}>{sym.rsi != null ? formatDisplayDecimal(sym.rsi) : '--'}</FlashValue>
            </span>
            {filterBadge(allFilters?.momentum)}
          </div>
        </div>
        <div className="analysis-item">
          <label>VOLUME</label>
          <div className="item-content">
            <span className="value">
              <FlashValue value={`${sym.cvd_trend}-${sym.cvd_delta}`}>
                {sym.cvd_trend ? `${trendArrow(sym.cvd_trend)} ${formatDisplayDecimal(sym.cvd_delta ?? 0)}` : '--'}
              </FlashValue>
              <span className="divider">|</span>
              <FlashValue value={sym.vwap_deviation_pct}>
                {formatDisplayDecimal(sym.vwap_deviation_pct ?? 0)}%
              </FlashValue>
            </span>
            {filterBadge(allFilters?.volume)}
          </div>
        </div>
        <div className="analysis-item">
          <label>DERIVATIVES</label>
          <div className="item-content">
            <span className="value">
              OI <FlashValue value={sym.oi_usd}>{sym.oi_usd ? `$${formatDisplayDecimal(sym.oi_usd / 1_000_000)}M` : '--'}</FlashValue>
              <span className="divider">|</span>
              <FlashValue value={sym.funding_rate}>
                {formatDisplayDecimal((sym.funding_rate ?? 0) * 100)}%
              </FlashValue>
            </span>
            {filterBadge(allFilters?.derivatives)}
          </div>
        </div>
        <div className="analysis-item status-item">
          <label>VERDICT</label>
          <div className={`verdict-text ${allPassed ? 'pos' : blockedReason ? 'neg' : 'neutral'}`}>
            {sym.signal ? 'EXECUTION_READY' : allPassed === false ? 'BLOCKED' : 'QUALIFYING'}
          </div>
        </div>
      </div>
      {blockedReason && (
        <div className="analysis-block-reason">
          <span className="label">BLOCK_ERROR:</span> {blockedReason}
        </div>
      )}
    </div>
  );
}

// Dashboard Specific UI Components below

const DashboardPage: React.FC = () => {
  const liveLtp = useLiveLtp();
  const [positions, setPositions] = useState<ApiPosition[]>([]);
  const [trades, setTrades] = useState<ApiTrade[]>([]);
  const [strategyStatus, setStrategyStatus] = useState<StrategyStatus | null>(null);
  const [wallet, setWallet] = useState<ApiWallet | null>(null);
  const [stats, setStats] = useState<ApiStats | null>(null);
  const [signalActivity, setSignalActivity] = useState<SignalActivity | null>(null);
  const [expandedSym, setExpandedSym] = useState<string | null>(null);
  const [tradeHistoryDay, setTradeHistoryDay] = useState<string>(() => localCalendarDateISO());
  const [tradesMeta, setTradesMeta] = useState<{ total_count: number; limit: number; day: string | null } | null>(
    null
  );
  const [tradesCalendarDays, setTradesCalendarDays] = useState<string[]>([]);
  const [positionsMeta, setPositionsMeta] = useState<{ as_of_date: string; count: number } | null>(null);
  const [closingPositionId, setClosingPositionId] = useState<number | null>(null);
  const [closePositionError, setClosePositionError] = useState<string | null>(null);

  const todayLocal = useCallback(() => localCalendarDateISO(), []);

  const tradeHistoryDayOptions = useMemo(() => {
    const today = todayLocal();
    const merged = new Set<string>([today, tradeHistoryDay, ...tradesCalendarDays]);
    return [...merged].sort((a, b) => b.localeCompare(a));
  }, [todayLocal, tradeHistoryDay, tradesCalendarDays]);

  const fetchEverything = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      params.set('trades_limit', '500');
      params.set('trades_day', tradeHistoryDay || todayLocal());
      params.set('calendar_day', todayLocal());
      const { data: dash } = await axios.get(`/api/dashboard?${params.toString()}`);
      setPositions((dash.positions ?? []) as ApiPosition[]);
      setPositionsMeta(dash.positions_meta ?? null);
      setTrades((dash.trades ?? []) as ApiTrade[]);
      setTradesMeta(dash.trades_meta ?? null);
      setTradesCalendarDays(
        Array.isArray(dash.trades_calendar_days) ? dash.trades_calendar_days.map(String) : []
      );
      setWallet((dash.wallet ?? null) as ApiWallet | null);
      setStats((dash.stats ?? null) as ApiStats | null);
      setSignalActivity(dash.signal_activity ?? null);

      const { data: strat } = await axios.get('/api/strategy_status');
      setStrategyStatus(strat);
    } catch (err) {
      console.error("Dashboard sync error", err);
    }
  }, [tradeHistoryDay, todayLocal]);

  const closePosition = useCallback(
    async (positionId: number, symbol: string) => {
      const ok = window.confirm(
        `Manually close ${symbol} at the server mark price?\n\nPaper: synthetic exit. Live: market order + close in DB.`
      );
      if (!ok) return;
      setClosePositionError(null);
      setClosingPositionId(positionId);
      try {
        await axios.post('/api/dashboard/close_position', { position_id: positionId });
        await fetchEverything();
      } catch (e: unknown) {
        const msg =
          axios.isAxiosError(e) && e.response?.data && typeof e.response.data === 'object' && e.response.data !== null && 'error' in e.response.data
            ? String((e.response.data as { error?: string }).error ?? e.message)
            : e instanceof Error
              ? e.message
              : 'close_failed';
        setClosePositionError(msg);
      } finally {
        setClosingPositionId(null);
      }
    },
    [fetchEverything]
  );

  useEffect(() => {
    const initial = setTimeout(() => void fetchEverything(), 0);
    const interval = setInterval(() => void fetchEverything(), 5000);
    return () => {
      clearTimeout(initial);
      clearInterval(interval);
    };
  }, [fetchEverything]);

  const strategyTfLegend = useMemo(
    () =>
      strategyStatus?.strategy.timeframes?.length
        ? strategyStatus.strategy.timeframes
        : [
            { tf: '4H', role: 'Trend filter', indicator: 'Supertrend direction' },
            { tf: '1H', role: 'Confirmation', indicator: 'Supertrend + ADX strength' },
            { tf: '5M', role: 'Entry trigger', indicator: 'BOS + Order Block zone' },
          ],
    [strategyStatus]
  );

  const timeAgo = (ts: string) => {
    const diff = Math.floor((new Date().getTime() - new Date(ts).getTime()) / 1000);
    return diff < 60 ? `${diff}s ago` : `${Math.floor(diff/60)}m ago`;
  };

  return (
    <div className="dashboard-content pt-4">
      <main className="terminal-grid">
        <div className="grid-left dashboard-trading-flow">
          <section id="strategy-monitor" className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <Cpu size={18} className="icon-accent" />
                <h2>STRATEGY_MONITOR</h2>
              </div>
              <div className="header-badge-group">
                <span className="section-badge">
                  {(strategyStatus?.strategy.name ?? 'MULTI-TIMEFRAME CONFLUENCE').toUpperCase()}
                </span>
                <span className={`mode-badge ${strategyStatus?.strategy.mode ?? 'unknown'}`}>
                  {(strategyStatus?.strategy.mode ?? '…').toUpperCase()}
                </span>
              </div>
            </div>

            {strategyStatus ? (
              <>
                <div className="strategy-legend">
                  {strategyTfLegend.map(tf => (
                    <div key={tf.tf} className="tf-legend-item">
                      <span className="tf-label">{tf.tf}</span>
                      <span className="tf-role">{tf.role}</span>
                      <span className="tf-indicator">{tf.indicator}</span>
                    </div>
                  ))}
                </div>

                <div className="table-wrapper strategy-monitor-table-scroll" title="Scroll for more symbols — keeps positions visible below.">
                  <table>
                    <thead>
                      <tr>
                        <th>SYMBOL</th>
                        {strategyTfLegend.map(row => (
                          <th key={row.tf}>{row.tf}_ST</th>
                        ))}
                        <th>ADX_PWR</th>
                        <th>BOS</th>
                        <th>SIGNAL</th>
                        <th>LAST_UPD</th>
                      </tr>
                    </thead>
                    <tbody>
                      {strategyStatus.symbols.map(sym => (
                        <React.Fragment key={sym.symbol}>
                          <tr className="row-hover cursor-pointer" onClick={() => setExpandedSym(expandedSym === sym.symbol ? null : sym.symbol)}>
                            <td><span className="font-bold">{sym.symbol.replace('USDT', '')}</span></td>
                            {[sym.trend_dir, sym.confirm_dir, sym.entry_dir]
                              .slice(0, strategyTfLegend.length)
                              .map((dir, idx) => (
                                <td key={idx}>
                                  <span className={`dir-badge ${dir || 'neutral'}`}>{dir?.toUpperCase() || '---'}</span>
                                </td>
                              ))}
                            <td>
                              <FlashValue value={sym.adx}>
                                <span className="font-mono" style={{ color: (sym.adx ?? 0) > 20 ? 'var(--primary)' : 'var(--text-muted)' }}>
                                  {formatDisplayDecimal(sym.adx ?? 0)}
                                </span>
                              </FlashValue>
                            </td>
                            <td><span className="text-dim">--</span></td>
                            <td><span className={`side-badge ${sym.signal ? 'long' : 'none'}`}>{sym.signal?.toUpperCase() || 'NONE'}</span></td>
                            <td><span className="text-muted">{sym.updated_at ? timeAgo(sym.updated_at) : '--'}</span></td>
                          </tr>
                          {expandedSym === sym.symbol && (
                            <tr>
                              <td colSpan={5 + strategyTfLegend.length} className="no-padding">
                                <SignalQualityPanel sym={sym} />
                              </td>
                            </tr>
                          )}
                        </React.Fragment>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            ) : (
              <div className="dashboard-section-loading" aria-live="polite">
                SYNCING_STRATEGY_STATE_FROM_API…
              </div>
            )}
          </section>

          <section id="active-positions" className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <BarChart3 size={18} className="icon-accent" />
                <h2>ACTIVE_POSITIONS</h2>
                {positionsMeta?.as_of_date && (
                  <span className="text-muted trade-day-label" style={{ marginLeft: "0.5rem" }}>
                    LOCAL_DATE {positionsMeta.as_of_date}
                  </span>
                )}
              </div>
              <span className="section-badge">{positions?.length || 0}</span>
            </div>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>SYMBOL</th>
                    <th>SIDE</th>
                    <th>ENTRY</th>
                    <th>OPENED</th>
                    <th>LTP</th>
                    <th
                      title="Order size in exchange contracts (not base coins). Notional ≈ contracts × contract_value × price."
                    >
                      CONTRACTS
                    </th>
                    <th>LEVERAGE</th>
                    <th>PNL_UNREALIZED (INR)</th>
                    <th
                      title="Return on initial margin (ROE), not underlying price change %. ≈ (unrealized PnL USD) ÷ (initial margin USD) × 100."
                    >
                      ROE%
                    </th>
                    <th
                      title="Tightest runner-driven exit in % of price: trailing stop (TrailingStopHandler) or near-liquidation distance. Smaller % = closer. See tooltip for full detail."
                    >
                      EXIT_NEAR
                    </th>
                    <th>ACTION</th>
                  </tr>
                </thead>
                <tbody>
                  {(positions && positions.length > 0) ? positions.map((p, i) => {
                    const prox = exitProximityCell(p);
                    const ltpForTip = liveLtp[p.symbol] ?? p.mark_price ?? undefined;
                    return (
                    <tr key={p.id ?? i} className="row-hover">
                      <td className="font-bold">{p.symbol}</td>
                      <td>
                        <span className={`side-badge ${sideBadgeMeta(p.side).css}`}>
                          {sideBadgeMeta(p.side).label}
                        </span>
                      </td>
                      <td className="font-mono">{formatQuotePrice(p.entry_price)}</td>
                      <td className="text-muted">
                        {p.opened_at
                          ? new Date(p.opened_at).toLocaleString(undefined, {
                              dateStyle: "short",
                              timeStyle: "short",
                            })
                          : "--"}
                      </td>
                      <td className="font-mono">
                        <FlashValue value={liveLtp[p.symbol] ?? p.mark_price}>
                          {formatQuotePrice(liveLtp[p.symbol] ?? p.mark_price)}
                        </FlashValue>
                      </td>
                      <td className="font-mono">{formatDisplayDecimal(p.size)}</td>
                      <td className="font-mono text-zinc-400">{p.leverage}x</td>
                      <td
                        className={(p.unrealized_pnl_inr || 0) >= 0 ? 'pos' : 'neg'}
                        title={
                          p.unrealized_pnl != null
                            ? `Unrealized ≈ ${formatUsd(p.unrealized_pnl)} USD (display INR uses a fixed USD/INR for the dashboard).`
                            : undefined
                        }
                      >
                        {formatInr(p.unrealized_pnl_inr || 0)}
                      </td>
                      <td
                        className={(p.unrealized_pnl_pct || 0) >= 0 ? 'pos' : 'neg'}
                        title="Return on equity vs posted initial margin (leverage magnifies this vs spot %)."
                      >
                        {formatDisplayDecimal(p.unrealized_pnl_pct || 0)}%
                      </td>
                      <td
                        className={`font-mono ${prox.className}`}
                        title={exitProximityTitle(p, ltpForTip)}
                      >
                        {prox.text}
                      </td>
                      <td>
                        {p.id != null ? (
                          <button
                            type="button"
                            className="btn-close-position"
                            disabled={closingPositionId === p.id}
                            onClick={() => void closePosition(p.id!, p.symbol)}
                          >
                            {closingPositionId === p.id ? 'CLOSING…' : 'CLOSE'}
                          </button>
                        ) : (
                          <span className="text-muted">—</span>
                        )}
                      </td>
                    </tr>
                    );
                  }) : (
                    <tr>
                      <td colSpan={11} className="text-center text-muted table-empty-row">
                        NO_ACTIVE_POSITIONS_FOUND
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            {closePositionError && (
              <p className="dashboard-close-error neg" role="alert">
                {closePositionError}
              </p>
            )}
          </section>

          <section id="signal-activity" className="terminal-section signal-activity-section">
            <div className="section-header">
              <div className="header-title-group">
                <Activity size={18} className="icon-accent" />
                <h2>SIGNAL_ACTIVITY</h2>
              </div>
            </div>
            <div className="signal-activity-grid">
              <div className="signal-activity-block">
                <label className="signal-activity-label">LAST_SIGNAL</label>
                {signalActivity?.last_signal ? (
                  <div className="signal-activity-detail">
                    <div className="signal-activity-line">
                      <span className="font-mono signal-activity-symbol">{signalActivity.last_signal.symbol}</span>
                      <span className={`side-badge ${sideBadgeMeta(signalActivity.last_signal.side).css}`}>
                        {sideBadgeMeta(signalActivity.last_signal.side).label}
                      </span>
                      <span className={`signal-status-pill status-${signalActivity.last_signal.status}`}>
                        {signalActivity.last_signal.status.toUpperCase()}
                      </span>
                    </div>
                    <div className="signal-activity-meta font-mono text-muted">
                      {signalActivity.last_signal.strategy} · {signalActivity.last_signal.source} · entry{' '}
                      {formatQuotePrice(signalActivity.last_signal.entry_price)}
                    </div>
                    <div className="signal-activity-time text-muted">
                      {formatSignalActivityTimestamp(signalActivity.last_signal.created_at)}
                    </div>
                    {signalActivity.last_signal.error_message && (
                      <div className="signal-activity-error">{signalActivity.last_signal.error_message}</div>
                    )}
                  </div>
                ) : (
                  <div className="text-muted signal-activity-empty">NO_SIGNALS_RECORDED</div>
                )}
              </div>
              <div className="signal-activity-block">
                <label className="signal-activity-label">LAST_REJECTION_OR_FAILURE</label>
                {signalActivity?.last_rejection ? (
                  <div className="signal-activity-detail">
                    <div className="signal-activity-line">
                      <span className="font-mono signal-activity-symbol">{signalActivity.last_rejection.symbol}</span>
                      <span className={`side-badge ${sideBadgeMeta(signalActivity.last_rejection.side).css}`}>
                        {sideBadgeMeta(signalActivity.last_rejection.side).label}
                      </span>
                      <span className={`signal-status-pill status-${signalActivity.last_rejection.status}`}>
                        {signalActivity.last_rejection.status.toUpperCase()}
                      </span>
                    </div>
                    <div className="signal-activity-meta font-mono text-muted">
                      {signalActivity.last_rejection.strategy} · {signalActivity.last_rejection.source}
                    </div>
                    <div className="signal-activity-reason signal-activity-error">
                      {signalActivity.last_rejection.error_message || 'NO_ERROR_MESSAGE_STORED'}
                    </div>
                    <div className="signal-activity-time text-muted">
                      {formatSignalActivityTimestamp(signalActivity.last_rejection.created_at)}
                    </div>
                  </div>
                ) : (
                  <div className="text-muted signal-activity-empty">NONE</div>
                )}
              </div>
            </div>
          </section>

          <section id="trade-history" className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <History size={18} className="icon-accent" />
                <h2>TRADE_HISTORY</h2>
              </div>
              <div className="header-badge-group trade-history-filters">
                <label className="trade-day-filter">
                  <span className="trade-day-label">DATE</span>
                  <select
                    value={tradeHistoryDay}
                    onChange={(e) => setTradeHistoryDay(e.target.value)}
                    className="trade-day-select"
                    aria-label="Trade history calendar day"
                  >
                    {tradeHistoryDayOptions.map((iso) => (
                      <option key={iso} value={iso}>
                        {formatTradeHistoryDayLabel(iso)}
                        {iso === todayLocal() ? ' — TODAY' : ''}
                      </option>
                    ))}
                  </select>
                </label>
                <button
                  type="button"
                  className="trade-day-clear"
                  disabled={tradeHistoryDay === todayLocal()}
                  onClick={() => setTradeHistoryDay(todayLocal())}
                >
                  TODAY
                </button>
                {tradesMeta && (
                  <span className="section-badge trade-count-badge">
                    {trades.length}/{tradesMeta.total_count}
                  </span>
                )}
              </div>
            </div>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>SYMBOL</th>
                    <th>SIDE</th>
                    <th>SIZE</th>
                    <th>ENTRY</th>
                    <th>EXIT</th>
                    <th>PNL_REALIZED</th>
                    <th>TIMESTAMP</th>
                  </tr>
                </thead>
                <tbody>
                  {trades.length > 0 ? trades.map((t, i) => (
                    <tr key={`${t.symbol}-${t.timestamp}-${i}`} className="row-hover">
                      <td className="font-bold">{t.symbol}</td>
                      <td>
                        <span className={`side-badge ${sideBadgeMeta(t.side).css}`}>
                          {sideBadgeMeta(t.side).label}
                        </span>
                      </td>
                      <td className="font-mono" title="Contracts / net quantity for the closed leg">
                        {formatDisplayDecimal(t.size)}
                      </td>
                      <td className="font-mono">{formatQuotePrice(t.entry_price)}</td>
                      <td className="font-mono">{formatQuotePrice(t.exit_price)}</td>
                      <td className={(t.pnl_inr ?? 0) >= 0 ? 'pos' : 'neg'}>
                        {(t.pnl_inr ?? 0) >= 0 ? '+' : ''}
                        {formatInr(t.pnl_inr ?? 0)}
                      </td>
                      <td className="text-muted">
                        {t.timestamp
                          ? new Date(t.timestamp).toLocaleString(undefined, {
                              dateStyle: 'short',
                              timeStyle: 'medium',
                            })
                          : '--'}
                      </td>
                    </tr>
                  )) : (
                    <tr>
                      <td colSpan={7} className="text-center text-muted table-empty-row">
                        NO_TRADES_IN_HISTORY
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <div className="grid-right">
          <section className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <Wallet size={16} className="icon-accent" />
                <h2>WALLET_OVERVIEW</h2>
              </div>
              <span className="mode-badge live">PAPER_TRADING</span>
            </div>
            <div className="wallet-grid">
              <div className="wallet-item">
                <label title="Ledger cash from realized fills; does not include mark-to-market on open positions.">
                  CASH BALANCE (USD)
                </label>
                <div className="wallet-value">
                  {wallet?.cash_balance_usd != null ? formatUsd(wallet.cash_balance_usd) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Ledger cash from realized fills; does not include mark-to-market on open positions.">
                  CASH BALANCE (INR)
                </label>
                <div className="wallet-value">
                  {wallet?.cash_balance_inr != null ? formatInr(wallet.cash_balance_inr) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Unrealized PnL on open positions (included in total equity, not in free cash).">
                  UNREALIZED (USD)
                </label>
                <div className={walletSignedValueClassName(wallet?.unrealized_pnl_usd)}>
                  {wallet?.unrealized_pnl_usd != null ? formatUsd(wallet.unrealized_pnl_usd) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Unrealized PnL on open positions (included in total equity, not in free cash).">
                  UNREALIZED (INR)
                </label>
                <div className={walletSignedValueClassName(wallet?.unrealized_pnl_inr)}>
                  {wallet?.unrealized_pnl_inr != null ? formatInr(wallet.unrealized_pnl_inr) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Cash balance plus unrealized PnL on open positions.">TOTAL EQUITY (USD)</label>
                <div className="wallet-value">
                  {wallet?.total_equity_usd != null ? formatUsd(wallet.total_equity_usd) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Cash balance plus unrealized PnL on open positions.">TOTAL EQUITY (INR)</label>
                <div className="wallet-value">
                  {wallet?.total_equity_inr != null ? formatInr(wallet.total_equity_inr) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Initial margin reserved for open positions.">BLOCKED MARGIN (USD)</label>
                <div className="wallet-value">
                  {wallet?.blocked_margin_usd != null ? formatUsd(wallet.blocked_margin_usd) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Initial margin reserved for open positions.">BLOCKED MARGIN (INR)</label>
                <div className="wallet-value">
                  {wallet?.blocked_margin_inr != null ? formatInr(wallet.blocked_margin_inr) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Cash balance minus blocked margin only. Unrealized PnL is not added — so equity minus blocked is not free cash unless unrealized is zero.">
                  FREE CASH (USD)
                </label>
                <div className={walletCashValueClassName(wallet?.available_usd)}>
                  {wallet?.available_usd != null ? formatUsd(wallet.available_usd) : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label title="Cash balance minus blocked margin only. Unrealized PnL is not added — so equity minus blocked is not free cash unless unrealized is zero.">
                  FREE CASH (INR)
                </label>
                <div className={walletCashValueClassName(wallet?.available_inr)}>
                  {wallet?.available_inr != null ? formatInr(wallet.available_inr) : '--'}
                </div>
              </div>
              <div className="wallet-item wallet-item-span">
                <p className="wallet-reconcile-hint">
                  Reconcile: total equity = cash + unrealized. Free cash = cash − blocked margin (not equity −
                  blocked).
                </p>
              </div>
              <div className="wallet-item">
                <label>LAST_SYNC</label>
                <div className="wallet-value timestamp">
                  {wallet?.updated_at ? timeAgo(wallet.updated_at) : '--'}
                </div>
              </div>
            </div>
            {wallet?.stale && (
              <div className="wallet-stale">⚠ Wallet data sync failed — check bot status</div>
            )}
            {wallet?.ledger_margin_exceeds_cash && (
              <div className="wallet-stale">
                Blocked margin still exceeds ledger cash after an automatic position recompute — check open fills,
                session leverage, and contract size; the next exchange fill also recomputes margin.
              </div>
            )}
          </section>

          <section className="terminal-section performance-card">
            <div className="section-header">
              <div className="header-title-group">
                <Cpu size={16} className="icon-accent" />
                <h2>EQUITY_7D</h2>
              </div>
            </div>
            <div className="chart-mock">
              <div className="bars">
                {stats?.equity_curve?.map((val: number, i: number) => {
                  const curve = stats?.equity_curve ?? [];
                  const max = Math.max(...curve.map(Math.abs), 1);
                  const h = Math.max((Math.abs(val) / max) * 100, 15);
                  return (
                    <div key={i} className="bar-container">
                      <div className={`bar ${val >= 0 ? 'pos-bar' : 'neg-bar'}`} style={{ height: `${h}%` }}></div>
                    </div>
                  );
                })}
              </div>
            </div>
            <div className="pnl-summary">
              <div className="pnl-item">
                <label>DAILY_EST</label>
                <div className={`value ${(stats?.daily_pnl ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  {stats?.daily_pnl != null
                    ? `${stats.daily_pnl >= 0 ? '+' : ''}${formatUsd(stats.daily_pnl)}`
                    : `+${formatUsd(9.86)}`}
                </div>
              </div>
              <div className="pnl-item">
                <label>WEEKLY_EST</label>
                <div className={`value ${(stats?.weekly_pnl ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  {stats?.weekly_pnl != null
                    ? `${stats.weekly_pnl >= 0 ? '+' : ''}${formatUsd(stats.weekly_pnl)}`
                    : `+${formatUsd(72.86)}`}
                </div>
              </div>
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}

export default DashboardPage;
