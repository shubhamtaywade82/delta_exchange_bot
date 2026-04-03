import React from 'react';
import { 
  X, 
  Info, 
  AlertTriangle, 
  CheckCircle2, 
  Terminal,
  Zap,
  ShieldCheck,
  Activity,
  Target
} from 'lucide-react';

interface AiAnalysis {
  summary: string;
  htf_bias: 'bullish' | 'bearish' | 'mixed';
  scenario: string;
  confidence_0_to_100: number;
  invalidation: string;
  takeaway_bullets: string[];
  comment_on_plan: string;
  trading_recommendation: {
    primary_action: 'long' | 'short' | 'wait';
    conviction_0_to_100: number;
    preferred_entry_model: string;
    entry_guidance: string;
    structural_stop_guidance: string;
    target_guidance: string | string[];
    aligns_with_htf_structure: boolean;
    premium_discount_compliance: string;
    liquidity_context: string;
    key_risks: string[];
    checklist: string[];
  };
}

interface ProductDetailPanelProps {
  symbol: string;
  description: string;
  contractType: string;
  analysis?: AiAnalysis;
  updatedAt?: string;
  onClose: () => void;
}

const ProductDetailPanel: React.FC<ProductDetailPanelProps> = ({ 
  symbol, 
  description, 
  contractType, 
  analysis, 
  updatedAt,
  onClose 
}) => {
  const biasColor = (bias: string) => {
    if (bias === 'bullish') return 'pos';
    if (bias === 'bearish') return 'neg';
    return 'neutral';
  };

  const actionColor = (action: string) => {
    if (action === 'long') return 'long';
    if (action === 'short') return 'short';
    return 'none';
  };

  return (
    <div className="product-detail-panel-overlay" onClick={onClose}>
      <div className="product-detail-panel" onClick={e => e.stopPropagation()}>
        <header className="panel-header">
          <div className="header-info">
            <div className="symbol-row">
              <Terminal size={20} className="text-primary" />
              <h3>{symbol}</h3>
              <span className="contract-badge">{contractType}</span>
            </div>
            <p className="description">{description}</p>
            {updatedAt && (
              <span className="text-[10px] text-muted tracking-wide mt-1 block">
                LAST_REFRESHED: {new Date(updatedAt).toLocaleString()}
              </span>
            )}
          </div>
          <button className="close-btn" onClick={onClose}>
            <X size={20} />
          </button>
        </header>

        <div className="panel-content">
          {!analysis ? (
            <div className="empty-analysis">
              <Info size={32} className="text-muted mb-4" />
              <h4>NO_AI_ANALYSIS_AVAILABLE</h4>
              <p>Execute `Trading::AnalysisDashboardRefreshJob` to generate data for this symbol.</p>
            </div>
          ) : (
            <>
              <section className="analysis-section summary-section">
                <div className="section-title">
                  <Activity size={16} className="text-primary" />
                  <h4>INSTITUTIONAL_SUMMARY</h4>
                </div>
                <div className="summary-pill-row">
                  <div className={`bias-pill ${biasColor(analysis.htf_bias || '')}`}>
                    <label>HTF_BIAS</label>
                    <span>{(analysis.htf_bias || 'UNKNOWN').toUpperCase()}</span>
                  </div>
                  <div className="confidence-pill">
                    <label>CONFIDENCE</label>
                    <div className="progress-bar">
                      <div className="fill" style={{ width: `${analysis.confidence_0_to_100 || 0}%` }}></div>
                    </div>
                    <span>{analysis.confidence_0_to_100 || 0}%</span>
                  </div>
                </div>
                <p className="narrative">{analysis.summary || 'No narrative provided.'}</p>
              </section>

              <section className="analysis-section recommendation-section">
                <div className="section-title">
                  <Target size={16} className="text-primary" />
                  <h4>TRADING_RECOMMENDATION</h4>
                </div>
                <div className="recommendation-grid">
                  <div className="rec-item action-item">
                    <label>PRIMARY_ACTION</label>
                    <span className={`side-badge ${actionColor(analysis.trading_recommendation?.primary_action || '')}`}>
                      {(analysis.trading_recommendation?.primary_action || 'WAIT').toUpperCase()}
                    </span>
                  </div>
                  <div className="rec-item">
                    <label>CONVICTION</label>
                    <span className="font-mono">{analysis.trading_recommendation?.conviction_0_to_100 || 0}%</span>
                  </div>
                  <div className="rec-item">
                    <label>ENTRY_MODEL</label>
                    <span className="value">{(analysis.trading_recommendation?.preferred_entry_model || 'none').replace(/_/g, ' ').toUpperCase()}</span>
                  </div>
                  <div className="rec-item">
                    <label>HTF_ALIGNMENT</label>
                    <span className={analysis.trading_recommendation?.aligns_with_htf_structure ? 'pos' : 'neg'}>
                      {analysis.trading_recommendation?.aligns_with_htf_structure ? 'CONFIRMED' : 'DIVERGED'}
                    </span>
                  </div>
                </div>

                <div className="guidance-grid">
                  <div className="guidance-box">
                    <label><Zap size={12} /> ENTRY_GUIDANCE</label>
                    <p>{analysis.trading_recommendation?.entry_guidance || 'N/A'}</p>
                  </div>
                  <div className="guidance-box stop">
                    <label><ShieldCheck size={12} /> INVALIDATION_STOP</label>
                    <p>{analysis.invalidation || analysis.trading_recommendation?.structural_stop_guidance || 'N/A'}</p>
                  </div>
                </div>

                <div className="guidance-box targets">
                  <label><Target size={12} /> LIQUIDITY_TARGETS</label>
                  {Array.isArray(analysis.trading_recommendation?.target_guidance) ? (
                    <ul>
                      {analysis.trading_recommendation?.target_guidance.map((t, i) => <li key={i}>{t}</li>)}
                    </ul>
                  ) : (
                    <p>{analysis.trading_recommendation?.target_guidance || 'N/A'}</p>
                  )}
                </div>
              </section>

              <div className="analysis-sub-grid">
                <section className="analysis-section bullets-section">
                  <div className="section-title">
                    <CheckCircle2 size={16} className="text-primary" />
                    <h4>KEY_TAKEAWAYS</h4>
                  </div>
                  <ul>
                    {(analysis.takeaway_bullets || []).map((b, i) => <li key={i}>{b}</li>)}
                  </ul>
                </section>

                <section className="analysis-section risks-section">
                  <div className="section-title">
                    <AlertTriangle size={16} className="text-primary" />
                    <h4>EXECUTION_RISKS</h4>
                  </div>
                  <ul>
                    {(analysis.trading_recommendation?.key_risks || []).map((r, i) => <li key={i}>{r}</li>)}
                  </ul>
                </section>
              </div>

              <section className="analysis-section plan-critique">
                <div className="section-title">
                  <Info size={16} className="text-primary" />
                  <h4>STRATEGY_CRITIQUE</h4>
                </div>
                <p>{analysis.comment_on_plan}</p>
              </section>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ProductDetailPanel;
