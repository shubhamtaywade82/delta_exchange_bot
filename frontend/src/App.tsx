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

/** Between DELTA_BOT header and derivatives (OI/FUND). Uses strategy symbol list + dashboard ltp:SYMBOL cache. */
function WatchlistLtpBar({
  symbols,
  ltpBySymbol,
}: {
  symbols: SymbolState[];
  ltpBySymbol: Record<string, number>;
}) {
  if (symbols.length === 0) return null;

  return (
    <div
      className="ticker-bar watchlist-ltp-bar"
      role="region"
      aria-label="Watchlist last traded prices"
    >
      <div className="watchlist-ltp-bar-heading">LTP</div>
      <div className="watchlist-ltp-bar-items">
        {symbols.map(s => {
          const ltp = ltpBySymbol[s.symbol];
          const hasLtp = ltp != null && Number.isFinite(ltp) && ltp > 0;
          return (
            <div key={s.symbol} className="ticker-item">
              <span className="symbol">{s.symbol.replace('USDT', '').replace('USD', '')}</span>
              <FlashValue
                value={ltp}
                className="price"
                title="Last traded price (Rails cache ltp:SYMBOL; written by market feed / runner)"
              >
                {hasLtp ? formatUsd(ltp) : '--'}
              </FlashValue>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function DerivativesStrip({ symbols }: { symbols: SymbolState[] }) {
  return (
    <div className="derivatives-marquee">
      <div className="marquee-content">
        {symbols.map(s => (
          <div key={s.symbol} className="deriv-item-modern">
            <span className="symbol-tag">{s.symbol.replace('USDT', '').replace('USD', '')}</span>
            <div className="metrics">
              <span className={s.oi_trend === 'rising' ? 'pos' : 'neg'}>
                OI {s.oi_usd ? `$${formatDisplayDecimal(s.oi_usd / 1_000_000)}M` : '--'} {trendArrow(s.oi_trend)}
              </span>
              <span className="sep"></span>
              <span className={(s.funding_rate ?? 0) > 0.0005 ? 'neg' : 'pos'}>
                FUND {formatDisplayDecimal((s.funding_rate ?? 0) * 100)}%
              </span>
            </div>
          </div>
        ))}
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
        <WatchlistLtpBar symbols={symbols} ltpBySymbol={mergedLtpBySymbol} />
        <DerivativesStrip symbols={symbols} />
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
