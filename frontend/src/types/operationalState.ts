export interface OperationalBlocker {
  code: string;
  message: string;
}

export interface SignalActivityEntry {
  id: number;
  trading_session_id?: number;
  symbol: string;
  side: string;
  status: string;
  strategy: string;
  source: string;
  entry_price: number;
  candle_timestamp: number;
  error_message: string | null;
  created_at: string;
}

export interface SignalActivity {
  last_signal: SignalActivityEntry | null;
  last_rejection: SignalActivityEntry | null;
}

export interface OperationalState {
  paper_trading: boolean;
  execution_mode_label: string;
  trading_session: {
    id: number;
    strategy: string;
    status: string;
    capital_usd: number;
    leverage: number | null;
    started_at?: string | null;
  } | null;
  kill_switch: {
    state: string;
    total_pnl_usd: number;
    total_exposure_usd: number;
    halt_if_pnl_at_or_below_usd: number;
    exposure_must_stay_below_usd: number;
    blocks_new_entries: boolean;
  };
  risk_gates: {
    daily_loss_cap: {
      today_realized_pnl_usd: number;
      loss_cap_usd: number;
      loss_cap_pct_of_session_capital: number;
      blocks_new_entries: boolean;
    };
    margin_utilization: {
      margin_used_usd: number;
      utilization_pct: number;
      max_utilization_pct: number;
      blocks_new_entries: boolean;
      note?: string;
    };
    concurrent_positions: {
      current: number;
      max: number;
      blocks_new_entries: boolean;
    };
  } | null;
  blockers: OperationalBlocker[];
  paper_risk_override_active: boolean;
  gates_would_block: boolean;
  auto_entry_allowed: boolean;
  entry_blocked: boolean;
  recent_signals: SignalActivityEntry[];
}
