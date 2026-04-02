import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { NavLink } from 'react-router-dom';
import axios from 'axios';
import { 
  Wallet, 
  History, 
  Cpu, 
  Terminal as TerminalIcon,
  BarChart3,
  Activity
} from 'lucide-react';
import type { SignalActivity, OperationalState } from '../types/operationalState';
import {
  formatDisplayDecimal,
  formatInr,
  formatQuotePrice,
  formatSignalActivityTimestamp,
  formatUsd,
  sideBadgeMeta,
} from '../utils/tradingDisplay';


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
  h1_dir?: string;
  m15_dir?: string;
  m5_dir?: string;
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
            <span className="value">RSI {sym.rsi != null ? formatDisplayDecimal(sym.rsi) : '--'}</span>
            {filterBadge(allFilters?.momentum)}
          </div>
        </div>
        <div className="analysis-item">
          <label>VOLUME</label>
          <div className="item-content">
            <span className="value">
              {sym.cvd_trend ? `${trendArrow(sym.cvd_trend)} ${formatDisplayDecimal(sym.cvd_delta ?? 0)}` : '--'}
              <span className="divider">|</span>
              {formatDisplayDecimal(sym.vwap_deviation_pct ?? 0)}%
            </span>
            {filterBadge(allFilters?.volume)}
          </div>
        </div>
        <div className="analysis-item">
          <label>DERIVATIVES</label>
          <div className="item-content">
            <span className="value">
              OI {sym.oi_usd ? `$${formatDisplayDecimal(sym.oi_usd / 1_000_000)}M` : '--'}
              <span className="divider">|</span>
              {formatDisplayDecimal((sym.funding_rate ?? 0) * 100)}%
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
  const [positions, setPositions] = useState<any[]>([]);
  const [trades, setTrades] = useState<any[]>([]);
  const [strategyStatus, setStrategyStatus] = useState<StrategyStatus | null>(null);
  const [wallet, setWallet] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [executionHealth, setExecutionHealth] = useState<any>(null);
  const [signalActivity, setSignalActivity] = useState<SignalActivity | null>(null);
  const [operationalState, setOperationalState] = useState<OperationalState | null>(null);
  const [expandedSym, setExpandedSym] = useState<string | null>(null);
  const [tradeHistoryDay, setTradeHistoryDay] = useState<string>(() => localCalendarDateISO());
  const [tradesMeta, setTradesMeta] = useState<{ total_count: number; limit: number; day: string | null } | null>(
    null
  );
  const [tradesCalendarDays, setTradesCalendarDays] = useState<string[]>([]);
  const [positionsMeta, setPositionsMeta] = useState<{ as_of_date: string; count: number } | null>(null);

  const todayLocal = useCallback(() => localCalendarDateISO(), []);

  const tradeHistoryDayOptions = useMemo(() => {
    const today = todayLocal();
    const merged = new Set<string>([today, tradeHistoryDay, ...tradesCalendarDays]);
    return [...merged].sort((a, b) => b.localeCompare(a));
  }, [todayLocal, tradeHistoryDay, tradesCalendarDays]);

  useEffect(() => {
    fetchEverything();
    const interval = setInterval(fetchEverything, 5000);
    return () => clearInterval(interval);
  }, [tradeHistoryDay]);

  const fetchEverything = async () => {
    try {
      const params = new URLSearchParams();
      params.set('trades_limit', '500');
      params.set('trades_day', tradeHistoryDay || todayLocal());
      params.set('calendar_day', todayLocal());
      const { data: dash } = await axios.get(`/api/dashboard?${params.toString()}`);
      setPositions(dash.positions);
      setPositionsMeta(dash.positions_meta ?? null);
      setTrades(dash.trades);
      setTradesMeta(dash.trades_meta ?? null);
      setTradesCalendarDays(
        Array.isArray(dash.trades_calendar_days) ? dash.trades_calendar_days.map(String) : []
      );
      setWallet(dash.wallet);
      setStats(dash.stats);
      setExecutionHealth(dash.execution_health);
      setSignalActivity(dash.signal_activity ?? null);
      setOperationalState(dash.operational_state ?? null);

      const { data: strat } = await axios.get('/api/strategy_status');
      setStrategyStatus(strat);
    } catch (err) {
      console.error("Dashboard sync error", err);
    }
  };

  const timeAgo = (ts: string) => {
    const diff = Math.floor((new Date().getTime() - new Date(ts).getTime()) / 1000);
    return diff < 60 ? `${diff}s ago` : `${Math.floor(diff/60)}m ago`;
  };

  return (
    <div className="dashboard-content pt-4">
      <header className="terminal-header">
        <div className="brand">
          <div className="brand-text">
            <TerminalIcon size={18} className="icon-pulse" />
            <h1>DELTA_BOT</h1>
            <NavLink to="/operational" className="dashboard-ops-link" title="Gates, blockers, signal timeline">
              OPERATIONAL →
            </NavLink>
            <div className="system-status">
              <span className="dot online"></span>
              <span className="status-online">ONLINE_ v2.0</span>
              <span className="status-latency">12ms</span>
            </div>
          </div>
        </div>
        <div className="session-stats">
          <div className="mini-stat">
            <label>WIN_RATE</label>
            <span className="value">{stats?.win_rate != null ? `${formatDisplayDecimal(stats.win_rate)}%` : '--'}</span>
          </div>
          <div className="mini-stat">
            <label>TOTAL_PNL</label>
            <span className={`value ${(stats?.total_pnl_usd ?? 0) >= 0 ? 'pos' : 'neg'}`}>
              {formatInr(stats?.total_pnl_inr ?? 0)}
            </span>
          </div>
          {wallet && (
            <div className="mini-stat">
              <label>TOTAL_EQUITY</label>
              <span className="value">
                {wallet.paper_mode ? '📄 ' : ''}
                {wallet.total_equity_inr != null
                  ? formatInr(wallet.total_equity_inr)
                  : wallet.available_usd != null
                    ? formatUsd(wallet.available_usd)
                    : '--'}
              </span>
            </div>
          )}
          <div className="mini-stat">
            <label>EXECUTION</label>
            <span className={`value ${executionHealth?.healthy ? 'pos' : executionHealth ? 'neg' : ''}`}>
              {executionHealth?.healthy ? 'HEALTHY' : executionHealth?.category?.toUpperCase() || 'UNKNOWN'}
            </span>
          </div>
          <div className="mini-stat">
            <label>AUTO_ENTRY</label>
            <span className={`value ${operationalState?.auto_entry_allowed ? 'pos' : operationalState ? 'neg' : ''}`}>
              {operationalState == null ? '—' : operationalState.auto_entry_allowed ? 'ALLOWED' : 'BLOCKED'}
            </span>
          </div>
        </div>
      </header>

      <main className="terminal-grid">
        <div className="grid-left">
          {strategyStatus && (
            <section className="terminal-section">
              <div className="section-header">
                <div className="header-title-group">
                  <Cpu size={18} className="icon-accent" />
                  <h2>STRATEGY_MONITOR</h2>
                </div>
                <div className="header-badge-group">
                  <span className="section-badge">{strategyStatus.strategy.name.toUpperCase()}</span>
                  <span className={`mode-badge ${strategyStatus.strategy.mode}`}>
                    {strategyStatus.strategy.mode?.toUpperCase()}
                  </span>
                </div>
              </div>

              <div className="strategy-legend">
                {strategyStatus.strategy.timeframes.map(tf => (
                  <div key={tf.tf} className="tf-legend-item">
                    <span className="tf-label">{tf.tf}</span>
                    <span className="tf-role">{tf.role}</span>
                    <span className="tf-indicator">{tf.indicator}</span>
                  </div>
                ))}
              </div>

              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>SYMBOL</th>
                      <th>1H_DIR</th>
                      <th>15M_CONF</th>
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
                          <td><span className={`dir-badge ${sym.h1_dir || 'neutral'}`}>{sym.h1_dir?.toUpperCase() || '---'}</span></td>
                          <td><span className={`dir-badge ${sym.m15_dir || 'neutral'}`}>{sym.m15_dir?.toUpperCase() || '---'}</span></td>
                          <td>
                            <span className="font-mono" style={{ color: (sym.adx ?? 0) > 20 ? 'var(--primary)' : 'var(--text-muted)' }}>
                              {formatDisplayDecimal(sym.adx ?? 0)}
                            </span>
                          </td>
                          <td><span className="text-dim">--</span></td>
                          <td><span className={`side-badge ${sym.signal ? 'long' : 'none'}`}>{sym.signal?.toUpperCase() || 'NONE'}</span></td>
                          <td><span className="text-muted">{sym.updated_at ? timeAgo(sym.updated_at) : '--'}</span></td>
                        </tr>
                        {expandedSym === sym.symbol && (
                          <tr>
                            <td colSpan={7} className="no-padding">
                              <SignalQualityPanel sym={sym} />
                            </td>
                          </tr>
                        )}
                      </React.Fragment>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          <section className="terminal-section signal-activity-section">
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

          <section className="terminal-section">
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
                  </tr>
                </thead>
                <tbody>
                  {(positions && positions.length > 0) ? positions.map((p, i) => (
                    <tr key={i} className="row-hover">
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
                      <td className="font-mono">{formatQuotePrice(p.mark_price)}</td>
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
                    </tr>
                  )) : (
                    <tr>
                      <td colSpan={9} className="text-center text-muted table-empty-row">
                        NO_ACTIVE_POSITIONS_FOUND
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <section className="terminal-section">
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
                      <td className="font-mono">{formatQuotePrice(t.entry_price)}</td>
                      <td className="font-mono">{formatQuotePrice(t.exit_price)}</td>
                      <td className={(t.pnl_inr || 0) >= 0 ? 'pos' : 'neg'}>
                        {t.pnl_inr >= 0 ? '+' : ''}
                        {formatInr(t.pnl_inr || 0)}
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
                      <td colSpan={6} className="text-center text-muted table-empty-row">
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
                  const max = Math.max(...(stats?.equity_curve.map(Math.abs) ?? [1]), 1);
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

      <footer className="terminal-footer">
        <div className="command-line">
          <span className="prompt">root@delta-bot:v2.0#</span>
          <span className="cursor-blink">Awaiting input_</span>
        </div>
        <div className="system-metrics">
          <span>MODE: DRY_RUN</span>
          <span>SESSIONS: ACTIVE</span>
          <span>LOAD: 0.24ms</span>
        </div>
      </footer>
    </div>
  );
}

export default DashboardPage;
