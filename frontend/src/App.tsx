import React, { useState, useEffect, useMemo } from 'react';
import { useLiveLtp } from './liveLtp/liveLtpContext';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import axios from 'axios';
import Navbar from './components/Navbar';
import BotStatusBar, { type BotStatusBarProps } from './components/BotStatusBar';
import AppFooter from './components/AppFooter';
import { formatDisplayDecimal, formatUsd } from './utils/tradingDisplay';
import DashboardPage from './pages/DashboardPage';
import OperationalStatePage from './pages/OperationalStatePage';
import CatalogPage from './pages/CatalogPage';
import AdminSettingsPage from './pages/AdminSettingsPage';
import AnalysisDashboardPage from './pages/AnalysisDashboardPage';
import { FlashValue } from './components/common/FlashValue';

interface SymbolState {
  symbol: string;
  funding_rate?: number;
  oi_usd?: number;
  oi_trend?: string;
}

function trendArrow(trend?: string) {
  return trend === 'rising' || trend === 'bullish' ? '▲' : '▼';
}

/** Single strip: LTP + open interest + funding per watchlist symbol (strategy list + dashboard cache). */
function WatchlistMarketStrip({
  symbols,
  ltpBySymbol,
}: {
  symbols: SymbolState[];
  ltpBySymbol: Record<string, number>;
}) {
  if (symbols.length === 0) return null;

  return (
    <div
      className="ticker-bar watchlist-market-strip"
      role="region"
      aria-label="Watchlist last traded price, open interest, and funding"
    >
      <div className="watchlist-market-strip-heading">MARKET</div>
      <div className="watchlist-market-strip-items">
        {symbols.map(s => {
          const ltp = ltpBySymbol[s.symbol];
          const hasLtp = ltp != null && Number.isFinite(ltp) && ltp > 0;
          const symShort = s.symbol.replace('USDT', '').replace('USD', '');
          return (
            <div key={s.symbol} className="ticker-item watchlist-market-item">
              <span className="symbol">{symShort}</span>
              <FlashValue
                value={ltp}
                className="price"
                title="Last traded price (Rails cache ltp:SYMBOL; written by market feed / runner)"
              >
                {hasLtp ? formatUsd(ltp) : '--'}
              </FlashValue>
              <span className="watchlist-metric-sep" aria-hidden />
              <span
                className={`watchlist-metric oi ${s.oi_trend === 'rising' ? 'pos' : 'neg'}`}
                title="Open interest notional + trend from strategy feed"
              >
                OI {s.oi_usd ? `$${formatDisplayDecimal(s.oi_usd / 1_000_000)}M` : '--'}
                {s.oi_trend ? ` ${trendArrow(s.oi_trend)}` : ''}
              </span>
              <span className="watchlist-metric-sep" aria-hidden />
              <span
                className={`watchlist-metric fund ${(s.funding_rate ?? 0) > 0.0005 ? 'neg' : 'pos'}`}
                title="Perpetual funding rate (8h-style fraction from ticker)"
              >
                FUND {formatDisplayDecimal((s.funding_rate ?? 0) * 100)}%
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

const App: React.FC = () => {
  const liveLtp = useLiveLtp();
  const [ltpBySymbol, setLtpBySymbol] = useState<Record<string, number>>({});
  const [symbols, setSymbols] = useState<SymbolState[]>([]);
  const [shellLatencyMs, setShellLatencyMs] = useState<number | null>(null);
  const [shellStats, setShellStats] = useState<BotStatusBarProps['stats']>(null);
  const [shellWallet, setShellWallet] = useState<BotStatusBarProps['wallet']>(null);
  const [shellExecutionHealth, setShellExecutionHealth] = useState<BotStatusBarProps['executionHealth']>(null);
  const [shellOperationalState, setShellOperationalState] = useState<BotStatusBarProps['operationalState']>(null);

  useEffect(() => {
    const fetchGlobal = async () => {
      try {
        const started = performance.now();
        const { data: dash } = await axios.get('/api/dashboard');
        setShellLatencyMs(Math.round(performance.now() - started));
        setShellStats(dash.stats ?? null);
        setShellWallet(dash.wallet ?? null);
        setShellExecutionHealth(dash.execution_health ?? null);
        setShellOperationalState(dash.operational_state ?? null);

        if (dash.market) {
          const ltpMap: Record<string, number> = {};
          (dash.market as { symbol: string; price?: number }[]).forEach(m => {
            if (!m.symbol) return;
            const p = Number(m.price);
            ltpMap[m.symbol] = Number.isFinite(p) ? p : 0;
          });
          setLtpBySymbol(ltpMap);
        } else {
          setLtpBySymbol({});
        }

        const { data: strat } = await axios.get('/api/strategy_status');
        setSymbols(strat.symbols || []);
      } catch (err) {
        console.error('Global shell sync error', err);
      }
    };

    fetchGlobal();
    const interval = setInterval(fetchGlobal, 5000);
    return () => clearInterval(interval);
  }, []);

  const mergedLtpBySymbol = useMemo(
    () => ({ ...ltpBySymbol, ...liveLtp }),
    [ltpBySymbol, liveLtp]
  );

  return (
    <BrowserRouter>
      <div className="terminal-container">
        <BotStatusBar
          latencyMs={shellLatencyMs}
          stats={shellStats}
          wallet={shellWallet}
          executionHealth={shellExecutionHealth}
          operationalState={shellOperationalState}
        />
        <WatchlistMarketStrip symbols={symbols} ltpBySymbol={mergedLtpBySymbol} />
        <Navbar />
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/signals" element={<Navigate to="/operational" replace />} />
          <Route path="/operational" element={<OperationalStatePage />} />
          <Route path="/catalog" element={<CatalogPage />} />
          <Route path="/analysis" element={<AnalysisDashboardPage />} />
          <Route path="/admin/settings" element={<AdminSettingsPage />} />
        </Routes>
        <AppFooter />
      </div>
    </BrowserRouter>
  );
};

export default App;
