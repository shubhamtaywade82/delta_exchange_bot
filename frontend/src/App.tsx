import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import axios from 'axios';
import Navbar from './components/Navbar';
import { formatDisplayDecimal, formatUsd } from './utils/tradingDisplay';
import DashboardPage from './pages/DashboardPage';
import OperationalStatePage from './pages/OperationalStatePage';
import CatalogPage from './pages/CatalogPage';
import AdminSettingsPage from './pages/AdminSettingsPage';
import AnalysisDashboardPage from './pages/AnalysisDashboardPage';

interface TickerData {
  symbol: string;
  price: number;
  change?: number;
}

interface SymbolState {
  symbol: string;
  funding_rate?: number;
  oi_usd?: number;
  oi_trend?: string;
}

function trendArrow(trend?: string) {
  return trend === 'rising' || trend === 'bullish' ? '▲' : '▼';
}

function TickerBar({ tickers }: { tickers: TickerData[] }) {
  return (
    <div className="ticker-bar">
      {tickers.map(data => {
        return (
          <div key={data.symbol} className="ticker-item">
            <span className="symbol">{data.symbol.replace('USDT', '').replace('USD', '')}</span>
            <span className={`price ${data.price ? 'pop' : ''}`}>{formatUsd(data.price)}</span>
            <span className={`change ${(data.change ?? 0) >= 0 ? 'pos' : 'neg'}`}>
              {data.change != null && Number.isFinite(data.change)
                ? `${data.change > 0 ? '+' : ''}${formatDisplayDecimal(data.change)}%`
                : '--'}
            </span>
          </div>
        );
      })}
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
  const [tickers, setTickers] = useState<TickerData[]>([]);
  const [symbols, setSymbols] = useState<SymbolState[]>([]);

  useEffect(() => {
    const fetchGlobal = async () => {
      try {
        const { data: dash } = await axios.get('/api/dashboard');
        
        // Use backend market data directly for tickers
        if (dash.market) {
          const newTickers = dash.market.map((m: any) => ({
            symbol: m.symbol,
            price: m.price || 0.0,
            change: (Math.random() - 0.5) * 5 // Mock change until added to backend
          }));
          setTickers(newTickers);
        }

        const { data: strat } = await axios.get('/api/strategy_status');
        setSymbols(strat.symbols || []);
      } catch (err) {
        console.error("Global shell sync error", err);
      }
    };

    fetchGlobal();
    const interval = setInterval(fetchGlobal, 5000); 
    return () => clearInterval(interval);
  }, []);

  return (
    <BrowserRouter>
      <div className="terminal-container">
        <TickerBar tickers={tickers} />
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
      </div>
    </BrowserRouter>
  );
};

export default App;
