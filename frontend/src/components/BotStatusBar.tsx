import React from 'react';
import { NavLink } from 'react-router-dom';
import { Terminal as TerminalIcon } from 'lucide-react';
import { formatDisplayDecimal, formatInr, formatUsd } from '../utils/tradingDisplay';

export interface BotStatusBarProps {
  latencyMs: number | null;
  stats: { win_rate?: number; total_pnl_usd?: number; total_pnl_inr?: number } | null;
  wallet: {
    paper_mode?: boolean;
    total_equity_inr?: number | null;
    available_usd?: number | null;
  } | null;
  executionHealth: { healthy?: boolean; category?: string } | null;
  operationalState: { auto_entry_allowed?: boolean } | null;
}

const BotStatusBar: React.FC<BotStatusBarProps> = ({
  latencyMs,
  stats,
  wallet,
  executionHealth,
  operationalState,
}) => {
  return (
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
            <span className="status-latency">
              {latencyMs != null && Number.isFinite(latencyMs) ? `${latencyMs}ms` : '—'}
            </span>
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
  );
};

export default BotStatusBar;
