import { useEffect, useState, useRef } from 'react';
import axios from 'axios';
import { LayoutDashboard, History, Terminal as TerminalIcon, Cpu, Wallet } from 'lucide-react';

const API_BASE = 'http://localhost:5000/api';
const WS_URL = 'wss://socket.delta.exchange';

interface DashboardStats {
  open_positions: number;
  total_trades: number;
  total_pnl_usd: number;
  total_pnl_inr: number;
  win_rate: number;
  daily_pnl: number;
  weekly_pnl: number;
  equity_curve: number[];
  market: { symbol: string; price: number; leverage: number }[];
}

interface Position {
  id: number;
  symbol: string;
  side: string;
  entry_price: string;
  size: string;
  leverage: number;
  pnl_usd: string;
  ltp: number;
  unrealized_pnl: number;
  entry_time: string;
}

interface Trade {
  id: number;
  symbol: string;
  side: string;
  entry_price: string;
  exit_price: string;
  pnl_usd: string;
  closed_at: string;
}

interface TickerData {
  symbol: string;
  price: number;
  change: number;
  timestamp: number;
}

interface SymbolState {
  symbol: string;
  h1_dir?: string;
  m15_dir?: string;
  m5_dir?: string;
  adx?: number;
  signal?: string;
  updated_at?: string;
}

interface StrategyParams {
  atr_period: number;
  multiplier: number;
  adx_period: number;
  adx_threshold: number;
  trail_pct: number;
}

interface StrategyStatus {
  strategy: {
    name: string;
    description: string;
    mode: string;
    timeframes: { tf: string; role: string; indicator: string }[];
    params: StrategyParams;
    entry_rules: string[];
    exit_rules: string[];
  };
  symbols: SymbolState[];
}

interface WalletState {
  available_usd: number | null;
  available_inr: number | null;
  capital_inr: number | null;
  paper_mode: boolean;
  updated_at: string | null;
  stale?: boolean;
}

const SYMBOLS = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT'];

function dirBadge(dir?: string) {
  if (!dir) return <span className="dir-badge neutral">--</span>;
  const cls = dir === 'bullish' ? 'bullish' : 'bearish';
  return <span className={`dir-badge ${cls}`}>{dir.toUpperCase()}</span>;
}

function signalBadge(signal?: string) {
  if (!signal) return <span className="dir-badge neutral">NONE</span>;
  const cls = signal === 'long' ? 'bullish' : 'bearish';
  return <span className={`dir-badge ${cls}`}>{signal.toUpperCase()}</span>;
}

function timeAgo(iso?: string) {
  if (!iso) return '--';
  const secs = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (secs < 60) return `${secs}s ago`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  return `${Math.floor(secs / 3600)}h ago`;
}

function App() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [positions, setPositions] = useState<Position[]>([]);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(true);
  const [tickers, setTickers] = useState<Record<string, TickerData>>({});
  const [logs, setLogs] = useState<string[]>([]);
  const [strategyStatus, setStrategyStatus] = useState<StrategyStatus | null>(null);
  const [wallet, setWallet] = useState<WalletState | null>(null);
  const ws = useRef<WebSocket | null>(null);
  const pingInterval = useRef<number | null>(null);

  useEffect(() => {
    fetchInitialData();
    connectWebSocket();
    const interval = setInterval(fetchInitialData, 15000);
    return () => {
      clearInterval(interval);
      if (pingInterval.current) clearInterval(pingInterval.current);
      ws.current?.close();
    };
  }, []);

  const addLog = (msg: string) => {
    setLogs(prev => [`[${new Date().toLocaleTimeString()}] ${msg}`, ...prev].slice(0, 50));
  };

  const connectWebSocket = () => {
    try {
      addLog('INITIATING WEBSOCKET CONNECTION...');
      ws.current = new WebSocket(WS_URL);

      ws.current.onopen = () => {
        addLog('STREAMS_CONNECTED_SUCCESSFULLY');
        ws.current?.send(JSON.stringify({
          type: 'subscribe',
          payload: { channels: [{ name: 'v2/ticker', symbols: SYMBOLS }] }
        }));
        pingInterval.current = window.setInterval(() => {
          if (ws.current?.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: 'ping' }));
          }
        }, 15000);
      };

      ws.current.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'v2/ticker' || data.channel === 'v2/ticker') {
          const payload = data.data || data;
          if (payload.symbol && payload.mark_price) {
            setTickers(prev => ({
              ...prev,
              [payload.symbol]: {
                symbol: payload.symbol,
                price: parseFloat(payload.mark_price),
                change: parseFloat(payload.price_change_24h || 0),
                timestamp: Date.now()
              }
            }));
          }
        }
      };

      ws.current.onerror = () => addLog('CRITICAL_WS_ERROR: CONNECTION_REFUSED');
      ws.current.onclose = (event) => {
        addLog(`CONNECTION_CLOSED_CODE: ${event.code}`);
        if (pingInterval.current) clearInterval(pingInterval.current);
        setTimeout(connectWebSocket, 5000);
      };
    } catch {
      addLog('FAILED_TO_CONSTRUCT_WEBSOCKET');
    }
  };

  const fetchInitialData = async () => {
    try {
      const [statsRes, posRes, tradesRes, strategyRes, walletRes] = await Promise.all([
        axios.get(`${API_BASE}/dashboard`),
        axios.get(`${API_BASE}/positions`),
        axios.get(`${API_BASE}/trades`),
        axios.get(`${API_BASE}/strategy_status`),
        axios.get(`${API_BASE}/wallet`),
      ]);
      setStats(statsRes.data);
      setPositions(posRes.data);
      setTrades(tradesRes.data);
      setStrategyStatus(strategyRes.data);
      setWallet(walletRes.data);
      setLoading(false);
    } catch (error) {
      addLog('ERROR FETCHING API DATA');
      console.error('Error fetching data:', error);
    }
  };

  if (loading) {
    return (
      <div className="terminal-loading">
        <div className="scanner"></div>
        <code>INITIALIZING SYSTEM...</code>
      </div>
    );
  }

  return (
    <div className="terminal-container">
      {/* Real-time Ticker Bar */}
      <div className="ticker-bar">
        {SYMBOLS.map(symbol => {
          const data = tickers[symbol];
          return (
            <div key={symbol} className="ticker-item">
              <span className="symbol">{symbol.replace('USDT', '')}</span>
              <span className={`price ${data?.price ? 'pop' : ''}`}>
                ${data?.price?.toLocaleString(undefined, { minimumFractionDigits: 2 }) || '---'}
              </span>
              <span className={`change ${(data?.change ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                {data?.change ? `${data.change > 0 ? '+' : ''}${data.change.toFixed(2)}%` : '--'}
              </span>
            </div>
          );
        })}
      </div>

      <header className="terminal-header">
        <div className="brand">
          <TerminalIcon size={28} className="icon-pulse" />
          <div>
            <h1>DELTA_BOT_CORE_v2.0</h1>
            <div className="system-status">
              <span className="status-label">SYS_READY_</span>
              <span className="status-online">ONLINE_</span>
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
              <label>CAPITAL</label>
              <span className="value">
                {wallet.paper_mode ? '📄 ' : ''}
                {wallet.capital_inr ? `₹${wallet.capital_inr.toLocaleString()}` : wallet.available_usd ? `$${wallet.available_usd}` : '--'}
              </span>
            </div>
          )}
        </div>
      </header>

      <main className="terminal-grid">
        {/* Left Column */}
        <div className="grid-left">
          {/* Strategy Monitor */}
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

              {/* Timeframe legend */}
              <div className="strategy-legend">
                {strategyStatus.strategy.timeframes.map(tf => (
                  <div key={tf.tf} className="tf-legend-item">
                    <span className="tf-label">{tf.tf}</span>
                    <span className="tf-role">{tf.role}</span>
                    <span className="tf-indicator">{tf.indicator}</span>
                  </div>
                ))}
              </div>

              {/* Per-symbol state */}
              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>SYMBOL</th>
                      <th>1H_DIR</th>
                      <th>15M_CONF</th>
                      <th>ADX_PWR</th>
                      <th>5M_TRIG</th>
                      <th>SIGNAL</th>
                      <th>LAST_UPD</th>
                    </tr>
                  </thead>
                  <tbody>
                    {strategyStatus.symbols.map(sym => (
                      <tr key={sym.symbol} className="row-hover">
                        <td className="font-bold">{sym.symbol}</td>
                        <td>{dirBadge(sym.h1_dir)}</td>
                        <td>{dirBadge(sym.m15_dir)}</td>
                        <td className={sym.adx != null && sym.adx >= (strategyStatus.strategy.params.adx_threshold ?? 20) ? 'pos' : 'neg'}>
                          {sym.adx != null ? sym.adx.toFixed(1) : '--'}
                        </td>
                        <td>{dirBadge(sym.m5_dir)}</td>
                        <td>{signalBadge(sym.signal)}</td>
                        <td className="timestamp">{timeAgo(sym.updated_at)}</td>
                      </tr>
                    ))}
                    {strategyStatus.symbols.length === 0 && (
                      <tr><td colSpan={7} className="empty-row">AWAITING_STRATEGY_EVALUATION...</td></tr>
                    )}
                  </tbody>
                </table>
              </div>

              {/* Params footer */}
              <div className="strategy-params">
                <span>ATR({strategyStatus.strategy.params.atr_period}) ×{strategyStatus.strategy.params.multiplier}</span>
                <span>ADX({strategyStatus.strategy.params.adx_period}) ≥{strategyStatus.strategy.params.adx_threshold}</span>
                <span>TRAIL: {strategyStatus.strategy.params.trail_pct}%</span>
              </div>
            </section>
          )}

          {/* Active Positions */}
          <section className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <LayoutDashboard size={18} className="icon-accent" />
                <h2>ACTIVE_POSITIONS</h2>
              </div>
              <span className="section-badge count">{positions.length}</span>
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
                    <th>PNL_UNREALIZED (INR)</th>
                  </tr>
                </thead>
                <tbody>
                  {positions.map((pos) => {
                    const wsData = tickers[pos.symbol] || tickers[pos.symbol + 'T'];
                    const ltp = wsData?.price || pos.ltp;
                    const multiplier = pos.side === 'long' ? 1 : -1;
                    const liveUpnl = ltp ? (ltp - parseFloat(pos.entry_price)) * parseFloat(pos.size) * multiplier : pos.unrealized_pnl;

                    return (
                      <tr key={pos.id} className="row-hover">
                        <td className="font-bold">{pos.symbol}</td>
                        <td><span className={`side-badge ${pos.side}`}>{pos.side.toUpperCase()}</span></td>
                        <td>${parseFloat(pos.entry_price).toFixed(2)}</td>
                        <td className={`live-ltp font-mono ${wsData ? 'pop' : ''}`}>
                          ${ltp?.toFixed(2) || '---'}
                        </td>
                        <td>{pos.size}</td>
                        <td className={`font-mono ${liveUpnl >= 0 ? 'pos' : 'neg'}`}>
                          ₹{(liveUpnl * 85.0).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                        </td>
                      </tr>
                    );
                  })}
                  {positions.length === 0 && (
                    <tr><td colSpan={6} className="empty-row">NO_ACTIVE_POSITIONS_FOUND</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>

          {/* Trade History */}
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
                  {trades.map((trade) => (
                    <tr key={trade.id} className="row-hover">
                      <td>{trade.symbol}</td>
                      <td><span className={`side-badge ${trade.side}`}>{trade.side.toUpperCase()}</span></td>
                      <td>${parseFloat(trade.entry_price).toFixed(2)}</td>
                      <td>${parseFloat(trade.exit_price).toFixed(2)}</td>
                      <td className={parseFloat(trade.pnl_usd) >= 0 ? 'pos' : 'neg'}>
                        {parseFloat(trade.pnl_usd) >= 0 ? '+' : ''}₹{(parseFloat(trade.pnl_usd) * 85.0).toLocaleString()}
                      </td>
                      <td className="timestamp">{new Date(trade.closed_at).toLocaleTimeString()}</td>
                    </tr>
                  ))}
                  {trades.length === 0 && (
                    <tr><td colSpan={6} className="empty-row">NO_TRADE_HISTORY_FOUND</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>

        {/* Right Column */}
        <div className="grid-right">
          {/* Wallet */}
          <section className="terminal-section">
            <div className="section-header">
              <div className="header-title-group">
                <Wallet size={18} className="icon-accent" />
                <h2>WALLET_OVERVIEW</h2>
              </div>
              {wallet?.paper_mode && <span className="mode-badge dry_run">PAPER_TRADING</span>}
            </div>
            <div className="wallet-grid">
              <div className="wallet-item">
                <label>CAPITAL (INR)</label>
                <div className="wallet-value">
                  {wallet?.capital_inr != null ? `₹${wallet.capital_inr.toLocaleString()}` : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label>AVAILABLE (USD)</label>
                <div className="wallet-value pos">
                  {wallet?.available_usd != null ? `$${wallet.available_usd.toFixed(2)}` : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label>AVAILABLE (INR)</label>
                <div className="wallet-value pos">
                  {wallet?.available_inr != null ? `₹${wallet.available_inr.toLocaleString()}` : '--'}
                </div>
              </div>
              <div className="wallet-item">
                <label>LAST_SYNC</label>
                <div className="wallet-value timestamp">
                  {wallet?.updated_at ? timeAgo(wallet.updated_at) : 'BOT_OFFLINE'}
                </div>
              </div>
            </div>
            {wallet?.stale && (
              <div className="wallet-stale">⚠ Wallet data sync failed — check bot status</div>
            )}
          </section>

          {/* Equity Curve */}
          <section className="performance-card">
            <div className="chart-mock">
              <div className="label">EQUITY_CURVE_PERFORMANCE_7D</div>
              <div className="bars">
                {stats?.equity_curve?.map((val, i) => {
                  const max = Math.max(...(stats?.equity_curve ?? [1]), 1);
                  const h = Math.max((val / max) * 100, 5);
                  return <div key={i} className={`bar ${val >= 0 ? 'pos-bar' : 'neg-bar'}`} style={{ height: `${Math.abs(h)}%` }}></div>;
                })}
              </div>
            </div>
            <div className="pnl-summary">
              <div className="pnl-item">
                <label>DAILY_EST</label>
                <div className={`value ${(stats?.daily_pnl ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  {stats?.daily_pnl && stats.daily_pnl >= 0 ? '+' : ''}${stats?.daily_pnl?.toFixed(2) ?? '0.00'}
                </div>
              </div>
              <div className="pnl-item">
                <label>WEEKLY_EST</label>
                <div className={`value ${(stats?.weekly_pnl ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  {stats?.weekly_pnl && stats.weekly_pnl >= 0 ? '+' : ''}${stats?.weekly_pnl?.toFixed(2) ?? '0.00'}
                </div>
              </div>
            </div>
          </section>

          {/* System Logs */}
          <section className="terminal-section console-section">
            <div className="section-header">
              <div className="header-title-group">
                <TerminalIcon size={18} className="icon-accent" />
                <h2>SYSTEM_EXECUTION_LOGS</h2>
              </div>
            </div>
            <div className="console-output">
              {logs.map((log, i) => (
                <div key={i} className="log-entry">
                  <span className="message">{log}</span>
                </div>
              ))}
            </div>
          </section>
        </div>
      </main>

      <footer className="terminal-footer">
        <div className="command-line">
          <span className="prompt">root@delta-bot:v2.0#</span>
          <span className="cursor-text">Awaiting input_</span>
        </div>
        <div className="system-metrics">
          <span>MODE: {strategyStatus?.strategy?.mode?.toUpperCase() ?? '--'}</span>
          <span>SESSIONS: {trades.length > 0 ? 'ACTIVE' : 'IDLE'}</span>
          <span>LOAD: 0.24ms</span>
        </div>
      </footer>
    </div>
  );
}

export default App;
