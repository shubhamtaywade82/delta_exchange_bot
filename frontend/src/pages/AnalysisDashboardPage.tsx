import React, { useCallback, useEffect, useState } from 'react';
import axios from 'axios';
import { LineChart, RefreshCw } from 'lucide-react';
import { formatQuotePrice, formatSignalActivityTimestamp } from '../utils/tradingDisplay';

interface OrderBlockRow {
  side: string;
  high: number;
  low: number;
  age_bars: number;
  fresh: boolean;
  strength_pct: number;
}

interface SymbolDigest {
  symbol: string;
  error?: string | null;
  updated_at?: string;
  ai_insight?: string | null;
  price_action?: {
    last_close: number;
    ltp: number | null;
    entry_timeframe: string;
    last_bar_at: string;
  };
  market_structure?: {
    bias: string;
    h1: string;
    m15: string;
    m5: string;
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
  smc?: {
    bos: {
      direction: string | null;
      level: number | null;
      confirmed: boolean;
    };
    order_blocks: OrderBlockRow[];
  };
}

interface AnalysisPayload {
  updated_at: string | null;
  symbols: SymbolDigest[];
  meta?: { source?: string; symbol_count?: number; error?: string | null };
}

function dirClass(dir: string | null | undefined): string {
  const d = (dir ?? '').toLowerCase();
  if (d.includes('bullish_aligned')) return 'analysis-dir-bullish-aligned analysis-dir-bull';
  if (d.includes('bearish_aligned')) return 'analysis-dir-bearish-aligned analysis-dir-bear';
  if (d === 'bullish' || d === 'bull') return 'analysis-dir-bull';
  if (d === 'bearish' || d === 'bear') return 'analysis-dir-bear';
  return 'analysis-dir-neutral';
}

const AnalysisDashboardPage: React.FC = () => {
  const [data, setData] = useState<AnalysisPayload | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [inFlight, setInFlight] = useState(false);
  const [hadFirstLoad, setHadFirstLoad] = useState(false);

  const fetchData = useCallback(async (opts?: { silent?: boolean }) => {
    if (!opts?.silent) setInFlight(true);
    try {
      const { data: body } = await axios.get<AnalysisPayload>('/api/analysis_dashboard');
      setData(body);
      setLoadError(null);
    } catch (e) {
      setLoadError('Failed to load analysis snapshot');
      console.error(e);
    } finally {
      if (!opts?.silent) setInFlight(false);
      setHadFirstLoad(true);
    }
  }, []);

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
              Multi-timeframe structure, SMC (BOS + order blocks), and ADX — refreshed every 15 minutes per
              enabled symbol (Solid Queue). This page polls the latest snapshot every 30s.
            </p>
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

      <div className="analysis-symbol-grid">
        {(data?.symbols ?? []).map(row => (
          <section key={row.symbol} className="terminal-section analysis-card">
            <div className="section-header analysis-card-head">
              <h2>{row.symbol}</h2>
              {row.error ? (
                <span className="mode-badge blocked">ERROR</span>
              ) : (
                <span className="mode-badge live">OK</span>
              )}
            </div>

            {row.error ? (
              <p className="analysis-error">{row.error}</p>
            ) : (
              <div className="analysis-dense-body">
                <div className="dense-main-row">
                  <div className="dense-group">
                    <span className="dense-label">LTP / CLOSE</span>
                    <span className="dense-val">
                      {row.price_action?.ltp ? formatQuotePrice(row.price_action.ltp) : formatQuotePrice(row.price_action?.last_close)}
                    </span>
                  </div>
                  
                  <div className="dense-group">
                    <span className="dense-label">BIAS</span>
                    <span className={`dense-bias ${dirClass(row.market_structure?.bias)}`}>
                      {(row.market_structure?.bias ?? '—').replace(/_/g, ' ')}
                    </span>
                  </div>
                  
                  <div className="dense-group">
                    <span className="dense-label">ADX (15m)</span>
                    <span className="dense-val">
                      {formatQuotePrice(row.market_structure?.adx)}{' '}
                      <span className={row.market_structure?.trending ? 'text-trend' : 'text-range'}>
                        {row.market_structure?.trending ? 'TREND' : 'RANGE'}
                      </span>
                    </span>
                  </div>
                </div>

                <div className="dense-multi-row">
                  <div className="dense-group">
                    <span className="dense-label">STRUCTURE (H1/M15/M5)</span>
                    <div className="dense-pills">
                      <span className={dirClass(row.market_structure?.h1)}>{row.market_structure?.h1?.substring(0,4).toUpperCase() || '—'}</span>
                      <span className={dirClass(row.market_structure?.m15)}>{row.market_structure?.m15?.substring(0,4).toUpperCase() || '—'}</span>
                      <span className={dirClass(row.market_structure?.m5)}>{row.market_structure?.m5?.substring(0,4).toUpperCase() || '—'}</span>
                    </div>
                  </div>

                  <div className="dense-group">
                    <span className="dense-label">STREND (H1/M15/M5)</span>
                    <div className="dense-pills">
                      {row.timeframes && ['trend', 'confirm', 'entry'].map(tfKey => {
                        const tf = row.timeframes![tfKey];
                        if (!tf) return <span key={tfKey}>—</span>;
                        return <span key={tfKey} className={dirClass(tf.supertrend_direction)}>{tf.supertrend_direction?.substring(0,4).toUpperCase() || '—'}</span>;
                      })}
                    </div>
                  </div>
                </div>

                <div className="dense-multi-row">
                  <div className="dense-group full-width">
                    <span className="dense-label">BOS (ENTRY TF)</span>
                    <span className={`dense-val ${dirClass(row.smc?.bos?.direction ?? undefined)}`}>
                      {(row.smc?.bos?.direction ?? '—').toUpperCase()} @ {formatQuotePrice(row.smc?.bos?.level)}
                      {row.smc?.bos?.confirmed && ' ✓'}
                    </span>
                  </div>
                </div>

                <div className="dense-group full-width border-top">
                  <span className="dense-label">ORDER BLOCKS</span>
                  <div className="dense-ob-list">
                    {(row.smc?.order_blocks?.length ?? 0) === 0 ? (
                      <span className="text-muted small">NO BLOCKS</span>
                    ) : (
                      row.smc!.order_blocks.map((ob, i) => (
                        <div key={i} className={`ob-compact-pill ${dirClass(ob.side === 'bull' ? 'bullish' : 'bearish')}`}>
                          <span className="ob-side">{ob.side.toUpperCase()}</span>
                          <span className="ob-range">{formatQuotePrice(ob.low)}-{formatQuotePrice(ob.high)}</span>
                          <span className="ob-meta">{ob.age_bars}B • {ob.fresh ? 'F' : 'U'}</span>
                        </div>
                      ))
                    )}
                  </div>
                </div>

                {row.ai_insight && (
                  <div className="dense-group full-width border-top ai-insight-block">
                    <span className="dense-label ai-label">AI SYNTHESIS</span>
                    <p className="ai-insight-text">
                      <span className="ai-sparkle">✨</span> {row.ai_insight}
                    </p>
                  </div>
                )}
              </div>
            )}
          </section>
        ))}
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
