import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { LayoutDashboard, History, Settings, Activity } from 'lucide-react';

const API_BASE = 'http://localhost:3000/api';

interface DashboardStats {
  open_positions: number;
  total_trades: number;
  total_pnl_usd: number;
  total_pnl_inr: number;
  win_rate: number;
}

interface Position {
  id: number;
  symbol: string;
  side: string;
  entry_price: string;
  size: string;
  leverage: number;
  pnl_usd: string;
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

function App() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [positions, setPositions] = useState<Position[]>([]);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 10000); // Refresh every 10s
    return () => clearInterval(interval);
  }, []);

  const fetchData = async () => {
    try {
      const [statsRes, posRes, tradesRes] = await Promise.all([
        axios.get(`${API_BASE}/dashboard`),
        axios.get(`${API_BASE}/positions`),
        axios.get(`${API_BASE}/trades`),
      ]);
      setStats(statsRes.data);
      setPositions(posRes.data);
      setTrades(tradesRes.data);
      setLoading(false);
    } catch (error) {
      console.error('Error fetching data:', error);
    }
  };

  if (loading) {
    return <div className="loading">Loading Delta Bot...</div>;
  }

  return (
    <div className="container">
      <header>
        <h1>Delta Exchange Bot</h1>
        <div className="status">
          <Activity size={16} /> Live
        </div>
      </header>

      <div className="stats-grid">
        <div className="stat-card">
          <label>Open Positions</label>
          <div className="value">{stats?.open_positions}</div>
        </div>
        <div className="stat-card">
          <label>Total PnL (USD)</label>
          <div className={`value ${stats?.total_pnl_usd && stats.total_pnl_usd >= 0 ? 'positive' : 'negative'}`}>
            ${stats?.total_pnl_usd}
          </div>
        </div>
        <div className="stat-card">
          <label>Total PnL (INR)</label>
          <div className={`value ${stats?.total_pnl_inr && stats.total_pnl_inr >= 0 ? 'positive' : 'negative'}`}>
            ₹{stats?.total_pnl_inr}
          </div>
        </div>
        <div className="stat-card">
          <label>Win Rate</label>
          <div className="value">{stats?.win_rate}%</div>
        </div>
      </div>

      <section>
        <h2><LayoutDashboard size={20} /> Open Positions</h2>
        <table>
          <thead>
            <tr>
              <th>Symbol</th>
              <th>Side</th>
              <th>Entry</th>
              <th>Size</th>
              <th>Lev</th>
              <th>PnL (Est)</th>
            </tr>
          </thead>
          <tbody>
            {positions.map((pos) => (
              <tr key={pos.id}>
                <td>{pos.symbol}</td>
                <td><span className={`badge ${pos.side}`}>{pos.side.toUpperCase()}</span></td>
                <td>${pos.entry_price}</td>
                <td>{pos.size}</td>
                <td>{pos.leverage}x</td>
                <td className={parseFloat(pos.pnl_usd) >= 0 ? 'positive' : 'negative'}>
                  ${pos.pnl_usd || '0.00'}
                </td>
              </tr>
            ))}
            {positions.length === 0 && (
              <tr><td colSpan={6} style={{ textAlign: 'center' }}>No open positions</td></tr>
            )}
          </tbody>
        </table>
      </section>

      <section>
        <h2><History size={20} /> Trade History</h2>
        <table>
          <thead>
            <tr>
              <th>Symbol</th>
              <th>Side</th>
              <th>Entry</th>
              <th>Exit</th>
              <th>PnL</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {trades.map((trade) => (
              <tr key={trade.id}>
                <td>{trade.symbol}</td>
                <td><span className={`badge ${trade.side}`}>{trade.side.toUpperCase()}</span></td>
                <td>${trade.entry_price}</td>
                <td>${trade.exit_price}</td>
                <td className={parseFloat(trade.pnl_usd) >= 0 ? 'positive' : 'negative'}>
                  ${trade.pnl_usd}
                </td>
                <td>{new Date(trade.closed_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <style>{`
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }
        h1 { margin: 0; font-size: 1.5rem; color: #38bdf8; }
        .status { background: #064e3b; color: #4ade80; padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.875rem; display: flex; align-items: center; gap: 0.5rem; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .stat-card { background: #1e293b; padding: 1.5rem; border-radius: 0.75rem; border: 1px solid #334155; }
        .stat-card label { font-size: 0.875rem; color: #94a3b8; display: block; margin-bottom: 0.5rem; }
        .stat-card .value { font-size: 1.5rem; font-weight: bold; }
        section { background: #1e293b; padding: 1.5rem; border-radius: 0.75rem; border: 1px solid #334155; margin-bottom: 2rem; }
        h2 { font-size: 1.25rem; margin-top: 0; margin-bottom: 1.5rem; display: flex; align-items: center; gap: 0.5rem; color: #94a3b8; }
        table { width: 100%; border-collapse: collapse; }
        th { text-align: left; padding: 0.75rem; border-bottom: 1px solid #334155; color: #64748b; font-size: 0.875rem; }
        td { padding: 0.75rem; border-bottom: 1px solid #334155; font-size: 0.875rem; }
        .positive { color: #4ade80; }
        .negative { color: #f87171; }
        .badge { padding: 0.125rem 0.5rem; border-radius: 4px; font-size: 0.75rem; font-weight: bold; }
        .badge.long { background: #064e3b; color: #4ade80; }
        .badge.short { background: #7f1d1d; color: #f87171; }
        .loading { display: flex; justify-content: center; align-items: center; height: 100vh; font-size: 1.5rem; color: #38bdf8; }
      `}</style>
    </div>
  );
}

export default App;
