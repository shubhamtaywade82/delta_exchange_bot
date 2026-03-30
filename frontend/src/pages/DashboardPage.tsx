import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { 
  TrendingUp, 
  TrendingDown, 
  Activity, 
  Wallet, 
  History, 
  Zap, 
  ShieldCheck, 
  Cpu, 
  Terminal as TerminalIcon,
  ChevronRight,
  ChevronDown,
  BarChart3,
  Waves
} from 'lucide-react';


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
            <span className="value">RSI {sym.rsi?.toFixed(0) ?? '--'}</span>
            {filterBadge(allFilters?.momentum)}
          </div>
        </div>
        <div className="analysis-item">
          <label>VOLUME</label>
          <div className="item-content">
            <span className="value">
              {sym.cvd_trend ? `${trendArrow(sym.cvd_trend)} ${(sym.cvd_delta ?? 0).toFixed(0)}` : '--'}
              <span className="divider">|</span>
              {(sym.vwap_deviation_pct ?? 0).toFixed(2)}%
            </span>
            {filterBadge(allFilters?.volume)}
          </div>
        </div>
        <div className="analysis-item">
          <label>DERIVATIVES</label>
          <div className="item-content">
            <span className="value">
              OI {sym.oi_usd ? `$${(sym.oi_usd / 1_000_000).toFixed(1)}M` : '--'}
              <span className="divider">|</span>
              {((sym.funding_rate ?? 0) * 100).toFixed(4)}%
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
  const [expandedSym, setExpandedSym] = useState<string | null>(null);

  useEffect(() => {
    fetchEverything();
    const interval = setInterval(fetchEverything, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchEverything = async () => {
    try {
      const { data: dash } = await axios.get('/api/dashboard');
      setPositions(dash.positions);
      setTrades(dash.trades);
      setWallet(dash.wallet);
      setStats(dash.stats);

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
            <span className="value">{stats?.win_rate}%</span>
          </div>
          <div className="mini-stat">
            <label>TOTAL_PNL</label>
            <span className={`value ${(stats?.total_pnl_usd ?? 0) >= 0 ? 'pos' : 'neg'}`}>
              ₹{stats?.total_pnl_inr?.toLocaleString() ?? '0'}
            </span>
          </div>
          {wallet && (
            <div className="mini-stat">
              <label>AVAILABLE_CAPITAL</label>
              <span className="value">
                {wallet.paper_mode ? '📄 ' : ''}
                {wallet.total_equity_inr != null 
                  ? `₹${Math.round(wallet.total_equity_inr).toLocaleString()}` 
                  : wallet.available_usd != null 
                    ? `$${wallet.available_usd.toFixed(2)}` 
                    : '--'}
              </span>
            </div>
          )}
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
                              {(sym.adx ?? 0).toFixed(1)}
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

          <section className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <BarChart3 size={18} className="icon-accent" />
                <h2>ACTIVE_POSITIONS</h2>
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
                    <th>LTP</th>
                    <th>SIZE</th>
                    <th>LEVERAGE</th>
                    <th>PNL_UNREALIZED (INR)</th>
                    <th>PNL_%</th>
                  </tr>
                </thead>
                <tbody>
                  {(positions && positions.length > 0) ? positions.map((p, i) => (
                    <tr key={i} className="row-hover">
                      <td className="font-bold">{p.symbol}</td>
                      <td><span className={`side-badge ${p.side}`}>{p.side.toUpperCase()}</span></td>
                      <td>{p.entry_price}</td>
                      <td>{p.mark_price}</td>
                      <td>{p.size}</td>
                      <td className="font-mono text-zinc-400">{p.leverage}x</td>
                      <td className={(p.unrealized_pnl_inr || 0) >= 0 ? 'pos' : 'neg'}>
                        ₹{(p.unrealized_pnl_inr || 0).toLocaleString()}
                      </td>
                      <td className={(p.unrealized_pnl_pct || 0) >= 0 ? 'pos' : 'neg'}>
                        {(p.unrealized_pnl_pct || 0).toFixed(2)}%
                      </td>
                    </tr>
                  )) : (
                    <tr><td colSpan={7} className="text-center text-muted">NO_ACTIVE_POSITIONS_FOUND</td></tr>
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
                    <tr key={i} className="row-hover">
                      <td className="font-bold">{t.symbol}</td>
                      <td><span className={`side-badge ${t.side}`}>{t.side.toUpperCase()}</span></td>
                      <td>{t.entry_price}</td>
                      <td>{t.exit_price}</td>
                      <td className={(t.pnl_inr || 0) >= 0 ? 'pos' : 'neg'}>
                        {t.pnl_inr >= 0 ? '+' : ''}₹{(t.pnl_inr || 0).toLocaleString()}
                      </td>
                      <td className="text-muted">{new Date(t.timestamp).toLocaleTimeString()}</td>
                    </tr>
                  )) : (
                    <tr><td colSpan={6} className="text-center text-muted">NO_TRADES_IN_HISTORY</td></tr>
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
                <label>TOTAL EQUITY</label>
                <div className="wallet-value">
                  {wallet?.total_equity_inr != null ? `₹${wallet.total_equity_inr.toLocaleString()}` : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label>SPENDABLE (USD)</label>
                <div className="wallet-value pos">
                  {wallet?.available_usd != null ? `$${wallet.available_usd.toFixed(2)}` : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label>SPENDABLE (INR)</label>
                <div className="wallet-value pos">
                  {wallet?.available_inr != null ? `₹${wallet.available_inr.toLocaleString()}` : '--'}
                </div>
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
                  +${stats?.daily_pnl?.toFixed(2) ?? '9.86'}
                </div>
              </div>
              <div className="pnl-item">
                <label>WEEKLY_EST</label>
                <div className={`value ${(stats?.weekly_pnl ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  +${stats?.weekly_pnl?.toFixed(2) ?? '72.86'}
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
