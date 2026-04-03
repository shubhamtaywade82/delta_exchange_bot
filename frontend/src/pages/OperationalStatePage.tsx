import React, { useState, useEffect, useCallback } from 'react';
import axios from 'axios';
import { Terminal as TerminalIcon } from 'lucide-react';
import type { OperationalState } from '../types/operationalState';
import {
  formatDisplayDecimal,
  formatSignalActivityTimestamp,
  formatUsd,
  sideBadgeMeta,
} from '../utils/tradingDisplay';

function localCalendarDateISO(d = new Date()) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

const OperationalStatePage: React.FC = () => {
  const [operationalState, setOperationalState] = useState<OperationalState | null>(null);
  const [paperOverrideBusy, setPaperOverrideBusy] = useState(false);

  const todayLocal = useCallback(() => localCalendarDateISO(), []);

  const load = async () => {
    try {
      const params = new URLSearchParams();
      params.set('trades_limit', '500');
      params.set('trades_day', todayLocal());
      params.set('calendar_day', todayLocal());
      const { data } = await axios.get(`/api/dashboard?${params.toString()}`);
      setOperationalState(data.operational_state ?? null);
    } catch (err) {
      console.error('Operational state sync error', err);
    }
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [todayLocal]);

  const setPaperRiskOverride = async (enabled: boolean) => {
    if (!operationalState?.paper_trading) return;
    setPaperOverrideBusy(true);
    try {
      await axios.post('/api/dashboard/paper_risk_override', { ignore_entry_risk_gates: enabled });
      await load();
    } catch (err) {
      console.error('paper_risk_override failed', err);
    } finally {
      setPaperOverrideBusy(false);
    }
  };

  return (
    <div className="dashboard-content pt-4 operational-page">
      <main className="operational-page-main">
        <section className="terminal-section operational-state-section">
          <div className="section-header">
            <div className="header-title-group">
              <TerminalIcon size={18} className="icon-accent" />
              <h2>GATES · SESSION · SIGNAL_TIMELINE</h2>
            </div>
            <div className="header-badge-group">
              <span className="section-badge operational-mode-badge">
                {(operationalState?.execution_mode_label ?? '—').toUpperCase()}
                {operationalState?.paper_trading ? ' · PAPER' : ''}
              </span>
              {!operationalState?.auto_entry_allowed && (
                <span className="mode-badge blocked">ENTRY_BLOCKED</span>
              )}
            </div>
          </div>
          <div className="operational-state-body">
            {operationalState?.paper_trading && (
              <div className="paper-override-actions">
                <button
                  type="button"
                  className="paper-override-btn primary"
                  disabled={paperOverrideBusy || operationalState.paper_risk_override_active === true}
                  onClick={() => setPaperRiskOverride(true)}
                >
                  OVERRIDE_GATES (PAPER)
                </button>
                <button
                  type="button"
                  className="paper-override-btn"
                  disabled={paperOverrideBusy || operationalState.paper_risk_override_active !== true}
                  onClick={() => setPaperRiskOverride(false)}
                >
                  RESTORE_GATES
                </button>
                <span className="paper-override-hint font-mono text-muted">
                  Skips RiskManager + kill-switch only. Requires running session + healthy execution.
                </span>
              </div>
            )}

            {operationalState?.paper_risk_override_active && operationalState?.gates_would_block && (
              <div className="paper-override-banner">
                PAPER_OVERRIDE_ACTIVE — gates would block, but entries are allowed for testing.
              </div>
            )}

            {operationalState?.trading_session && (
              <div className="operational-session-line font-mono text-muted">
                SESSION #{operationalState.trading_session.id} ·{' '}
                {operationalState.trading_session.strategy?.toUpperCase()} · capital{' '}
                {formatUsd(operationalState.trading_session.capital_usd)} · lev{' '}
                {operationalState.trading_session.leverage != null
                  ? formatDisplayDecimal(operationalState.trading_session.leverage)
                  : '—'}
              </div>
            )}

            {operationalState?.kill_switch && (
              <div className="operational-kill-line font-mono text-muted">
                KILL_SWITCH: {operationalState.kill_switch.state?.toUpperCase()} · portfolio PnL{' '}
                {formatUsd(operationalState.kill_switch.total_pnl_usd)} · exposure{' '}
                {formatUsd(operationalState.kill_switch.total_exposure_usd)}
              </div>
            )}

            {operationalState?.blockers && operationalState.blockers.length > 0 && (
              <div className="operational-blockers">
                <div className="operational-blockers-title">ACTIVE_BLOCKERS</div>
                {operationalState.blockers.map((b) => (
                  <div key={b.code} className="operational-blocker-row">
                    <span className="blocker-code">{b.code}</span>
                    <span className="blocker-msg">{b.message}</span>
                  </div>
                ))}
              </div>
            )}

            {operationalState?.risk_gates && (
              <div className="operational-gates-table-wrap">
                <table className="operational-gates-table">
                  <thead>
                    <tr>
                      <th>GATE</th>
                      <th>CURRENT</th>
                      <th>LIMIT</th>
                      <th>STATUS</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td>DAILY_REALIZED_PNL</td>
                      <td className="font-mono">
                        {formatUsd(operationalState.risk_gates.daily_loss_cap.today_realized_pnl_usd)}
                      </td>
                      <td className="font-mono">
                        floor -{formatUsd(operationalState.risk_gates.daily_loss_cap.loss_cap_usd)} (
                        {formatDisplayDecimal(
                          operationalState.risk_gates.daily_loss_cap.loss_cap_pct_of_session_capital * 100
                        )}
                        %)
                      </td>
                      <td>
                        {operationalState.risk_gates.daily_loss_cap.blocks_new_entries ? (
                          <span className="gate-bad">BLOCKS</span>
                        ) : (
                          <span className="gate-ok">OK</span>
                        )}
                      </td>
                    </tr>
                    <tr>
                      <td>MARGIN_UTIL</td>
                      <td className="font-mono">
                        {formatDisplayDecimal(operationalState.risk_gates.margin_utilization.utilization_pct)}%
                        {operationalState.risk_gates.margin_utilization.note
                          ? ` (${operationalState.risk_gates.margin_utilization.note})`
                          : ''}
                      </td>
                      <td className="font-mono">
                        max {formatDisplayDecimal(operationalState.risk_gates.margin_utilization.max_utilization_pct)}%
                      </td>
                      <td>
                        {operationalState.risk_gates.margin_utilization.blocks_new_entries ? (
                          <span className="gate-bad">BLOCKS</span>
                        ) : (
                          <span className="gate-ok">OK</span>
                        )}
                      </td>
                    </tr>
                    <tr>
                      <td>POSITIONS</td>
                      <td className="font-mono">
                        {operationalState.risk_gates.concurrent_positions.current}
                      </td>
                      <td className="font-mono">max {operationalState.risk_gates.concurrent_positions.max}</td>
                      <td>
                        {operationalState.risk_gates.concurrent_positions.blocks_new_entries ? (
                          <span className="gate-bad">BLOCKS</span>
                        ) : (
                          <span className="gate-ok">OK</span>
                        )}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            )}

            <div className="operational-recent-signals">
              <div className="operational-recent-title">RECENT_SIGNALS (latest 30)</div>
              <div className="table-wrapper operational-signals-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>TIME</th>
                      <th>SESS</th>
                      <th>SYMBOL</th>
                      <th>SIDE</th>
                      <th>STATUS</th>
                      <th>STRATEGY</th>
                      <th>OUTCOME / ERROR</th>
                    </tr>
                  </thead>
                  <tbody>
                    {operationalState?.recent_signals?.length ? (
                      operationalState.recent_signals.map((s) => (
                        <tr key={s.id} className="row-hover">
                          <td className="text-muted">{formatSignalActivityTimestamp(s.created_at)}</td>
                          <td className="font-mono">#{s.trading_session_id ?? '—'}</td>
                          <td className="font-bold">{s.symbol}</td>
                          <td>
                            <span className={`side-badge ${sideBadgeMeta(s.side).css}`}>
                              {sideBadgeMeta(s.side).label}
                            </span>
                          </td>
                          <td>
                            <span className={`signal-status-pill status-${s.status}`}>
                              {s.status.toUpperCase()}
                            </span>
                          </td>
                          <td className="font-mono text-muted">
                            {s.strategy} · {s.source}
                          </td>
                          <td className={s.error_message ? 'signal-err-cell' : 'text-muted'}>
                            {s.error_message ||
                              (s.status === 'executed'
                                ? 'EXECUTED (risk + engine)'
                                : s.status === 'skipped_duplicate'
                                  ? 'SKIPPED (duplicate candle key)'
                                  : '—')}
                          </td>
                        </tr>
                      ))
                    ) : (
                      <tr>
                        <td colSpan={7} className="text-center text-muted table-empty-row">
                          NO_SIGNALS_IN_DB
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
};

export default OperationalStatePage;
