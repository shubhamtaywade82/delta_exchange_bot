import React, { useEffect, useMemo, useState } from 'react';
import axios from 'axios';
import { Settings, Save } from 'lucide-react';

type ValueType = 'string' | 'integer' | 'float' | 'boolean';

type SettingWidget = 'toggle' | 'select' | 'number' | 'text' | 'password';

interface SettingUi {
  widget: SettingWidget;
  options?: Array<{ value: string; label: string }>;
  value_kind?: 'integer' | 'float';
  min?: number | null;
  max?: number | null;
  step?: number | 'any' | null;
}

interface RuntimeSetting {
  key: string;
  value: string;
  value_type: ValueType;
  typed_value: string | number | boolean | null;
  ui?: SettingUi | null;
}

function effectiveUi(setting: RuntimeSetting): SettingUi {
  if (setting.ui?.widget) return setting.ui;
  const vt = setting.value_type ?? 'string';
  if (vt === 'boolean') return { widget: 'toggle' };
  if (vt === 'integer') return { widget: 'number', value_kind: 'integer', step: 1 };
  if (vt === 'float') return { widget: 'number', value_kind: 'float', step: 'any' };
  return { widget: 'text' };
}

function isTruthyString(raw: string): boolean {
  return ['true', '1', 'yes', 'on'].includes(raw.trim().toLowerCase());
}

interface SettingChange {
  key: string;
  old_value: string | null;
  new_value: string;
  source: string;
  reason: string | null;
  created_at: string;
}

interface SettingGroupRule {
  id: string;
  label: string;
  match: (key: string) => boolean;
}

function domainPrefixMatch(key: string, domain: string): boolean {
  const x = key.toLowerCase();
  const d = domain.toLowerCase();
  return x === d || x.startsWith(`${d}.`);
}

function matchesSmcGroup(key: string): boolean {
  const x = key.toLowerCase();
  if (x.startsWith('smc.')) return true;
  if (/^strategy\.smc[._]/i.test(key)) return true;
  if (x.startsWith('strategy.str_smc')) return true;
  if (x.includes('smc_confluence')) return true;
  if (/^smc[._]/i.test(key)) return true;
  if (x.includes('smc_fvg') || x.includes('smc_daily')) return true;
  return false;
}

function matchesZScoreGroup(key: string): boolean {
  const x = key.toLowerCase();
  return x.includes('z_score') || x.includes('zscore');
}

function matchesObPoolGroup(key: string): boolean {
  return key.toLowerCase().includes('ob_pool');
}

/** First matching rule wins (keep SMC / z-score / OB pool before broad `strategy.`). */
const SETTING_GROUP_RULES: SettingGroupRule[] = [
  { id: 'bot', label: 'Bot', match: k => domainPrefixMatch(k, 'bot') },
  { id: 'smc', label: 'SMC', match: matchesSmcGroup },
  { id: 'zscore', label: 'Z-score', match: matchesZScoreGroup },
  { id: 'ob_pool', label: 'OB pool', match: matchesObPoolGroup },
  { id: 'strategy', label: 'Strategy', match: k => domainPrefixMatch(k, 'strategy') },
  { id: 'risk', label: 'Risk', match: k => domainPrefixMatch(k, 'risk') },
  { id: 'safety', label: 'Safety', match: k => domainPrefixMatch(k, 'safety') },
  { id: 'runner', label: 'Runner', match: k => domainPrefixMatch(k, 'runner') },
  { id: 'regime', label: 'Regime', match: k => domainPrefixMatch(k, 'regime') },
  {
    id: 'notifications',
    label: 'Notifications',
    match: k => domainPrefixMatch(k, 'notifications')
  },
  { id: 'logging', label: 'Logging', match: k => domainPrefixMatch(k, 'logging') },
  {
    id: 'general',
    label: 'General',
    match: k => {
      const x = k.toLowerCase();
      return domainPrefixMatch(k, 'general') || x.startsWith('general_');
    }
  },
  { id: 'learning', label: 'Learning', match: k => domainPrefixMatch(k, 'learning') },
  { id: 'ai', label: 'AI', match: k => domainPrefixMatch(k, 'ai') },
  { id: 'paper', label: 'Paper trading', match: k => domainPrefixMatch(k, 'paper') }
];

const RULE_ORDER = SETTING_GROUP_RULES.map(r => r.id);

const FALLBACK_PREFIX_LABELS: Record<string, string> = {
  other: 'Other'
};

function fallbackGroupId(key: string): string {
  const dot = key.indexOf('.');
  return dot === -1 ? 'other' : key.slice(0, dot).toLowerCase();
}

function fallbackLabel(segment: string): string {
  if (FALLBACK_PREFIX_LABELS[segment]) return FALLBACK_PREFIX_LABELS[segment];
  return segment
    .split(/[._]/g)
    .filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');
}

function resolveGroupForKey(key: string): { id: string; label: string } {
  for (const rule of SETTING_GROUP_RULES) {
    if (rule.match(key)) return { id: rule.id, label: rule.label };
  }
  const seg = fallbackGroupId(key);
  return { id: seg, label: fallbackLabel(seg) };
}

interface SettingGroupSection {
  id: string;
  label: string;
  items: RuntimeSetting[];
}

function buildSettingGroupSections(settings: RuntimeSetting[]): SettingGroupSection[] {
  const buckets: Record<string, { label: string; items: RuntimeSetting[] }> = {};

  settings.forEach(s => {
    const { id, label } = resolveGroupForKey(s.key);
    if (!buckets[id]) buckets[id] = { label, items: [] };
    buckets[id].items.push(s);
  });

  Object.values(buckets).forEach(b => b.items.sort((a, c) => a.key.localeCompare(c.key)));

  const seen = new Set<string>();
  const sections: SettingGroupSection[] = [];

  RULE_ORDER.forEach(id => {
    const b = buckets[id];
    if (!b?.items.length) return;
    sections.push({ id, label: b.label, items: b.items });
    seen.add(id);
  });

  Object.keys(buckets)
    .filter(id => !seen.has(id))
    .sort()
    .forEach(id => {
      const b = buckets[id];
      if (!b.items.length) return;
      sections.push({ id, label: b.label, items: b.items });
    });

  return sections;
}

const AUDIT_PANEL_ID = 'setting_changes';

const AdminSettingsPage: React.FC = () => {
  const [settings, setSettings] = useState<RuntimeSetting[]>([]);
  const [changes, setChanges] = useState<SettingChange[]>([]);
  const [drafts, setDrafts] = useState<Record<string, { value: string; value_type: ValueType }>>({});
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string>('');
  const [activePanelId, setActivePanelId] = useState<string>('');

  const loadData = async () => {
    try {
      setLoading(true);
      setError('');
      const [{ data: settingsData }, { data: changeData }] = await Promise.all([
        axios.get('/api/settings'),
        axios.get('/api/settings/changes', { params: { limit: 50 } })
      ]);

      const nextSettings = Array.isArray(settingsData) ? settingsData : [];
      setSettings(nextSettings);
      setChanges(Array.isArray(changeData) ? changeData : []);

      const nextDrafts: Record<string, { value: string; value_type: ValueType }> = {};
      nextSettings.forEach((setting: RuntimeSetting) => {
        nextDrafts[setting.key] = {
          value: setting.value ?? '',
          value_type: (setting.value_type ?? 'string') as ValueType
        };
      });
      setDrafts(nextDrafts);
    } catch {
      setError('Failed to load settings panel data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const hasChanges = useMemo(() => {
    return settings.some(setting => {
      const draft = drafts[setting.key];
      if (!draft) return false;
      return draft.value !== setting.value || draft.value_type !== setting.value_type;
    });
  }, [drafts, settings]);

  const settingSections = useMemo(() => buildSettingGroupSections(settings), [settings]);

  const resolvedPanelId = useMemo(() => {
    if (activePanelId === AUDIT_PANEL_ID) return AUDIT_PANEL_ID;
    if (settingSections.some(s => s.id === activePanelId)) return activePanelId;
    return settingSections[0]?.id ?? '';
  }, [activePanelId, settingSections]);

  const dirtyKeySet = useMemo(() => {
    const keys = new Set<string>();
    settings.forEach(setting => {
      const draft = drafts[setting.key];
      if (!draft) return;
      if (draft.value !== setting.value || draft.value_type !== setting.value_type) keys.add(setting.key);
    });
    return keys;
  }, [drafts, settings]);

  const dirtyCountInSection = (section: SettingGroupSection) =>
    section.items.reduce((n, s) => n + (dirtyKeySet.has(s.key) ? 1 : 0), 0);

  const activeSection = settingSections.find(s => s.id === resolvedPanelId);
  const showAuditPanel = resolvedPanelId === AUDIT_PANEL_ID;

  const updateDraft = (key: string, patch: Partial<{ value: string; value_type: ValueType }>) => {
    setDrafts(prev => ({
      ...prev,
      [key]: {
        value: patch.value ?? prev[key]?.value ?? '',
        value_type: patch.value_type ?? prev[key]?.value_type ?? 'string'
      }
    }));
  };

  const saveSetting = async (key: string) => {
    const draft = drafts[key];
    if (!draft) return;

    try {
      setSavingKey(key);
      await axios.patch(`/api/settings/${encodeURIComponent(key)}`, {
        key,
        value: draft.value,
        value_type: draft.value_type
      });
      await loadData();
    } catch {
      setError(`Failed to save setting: ${key}`);
    } finally {
      setSavingKey(null);
    }
  };

  const renderSettingTableRows = (items: RuntimeSetting[]) =>
    items.map(setting => {
      const draft = drafts[setting.key] || { value: setting.value, value_type: setting.value_type };
      const dirty = draft.value !== setting.value || draft.value_type !== setting.value_type;
      const ui = effectiveUi(setting);
      const showTypeEditor = ui.widget === 'text';

      const renderTypeCell = () => {
        if (showTypeEditor) {
          return (
            <select
              value={draft.value_type}
              onChange={e => updateDraft(setting.key, { value_type: e.target.value as ValueType })}
              className="search-input setting-type-select"
            >
              <option value="string">string</option>
              <option value="integer">integer</option>
              <option value="float">float</option>
              <option value="boolean">boolean</option>
            </select>
          );
        }
        return <span className="setting-type-badge font-mono">{draft.value_type}</span>;
      };

      const renderValueCell = () => {
        switch (ui.widget) {
          case 'toggle': {
            const on = isTruthyString(draft.value);
            return (
              <button
                type="button"
                role="switch"
                aria-checked={on}
                className={`setting-toggle-track${on ? ' setting-toggle-track--on' : ''}`}
                onClick={() => updateDraft(setting.key, { value: on ? 'false' : 'true' })}
              >
                <span className="setting-toggle-thumb" />
                <span className="setting-toggle-label">{on ? 'ON' : 'OFF'}</span>
              </button>
            );
          }
          case 'select': {
            const opts = ui.options ?? [];
            const known = new Set(opts.map(o => o.value));
            const currentMissing = draft.value !== '' && !known.has(draft.value);
            return (
              <select
                value={draft.value}
                onChange={e => updateDraft(setting.key, { value: e.target.value })}
                className="search-input setting-value-select"
              >
                {currentMissing && (
                  <option value={draft.value}>{draft.value} (current)</option>
                )}
                {opts.map(opt => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            );
          }
          case 'number': {
            const stepProp = ui.step === 'any' || ui.step == null ? 'any' : String(ui.step);
            return (
              <input
                type="number"
                value={draft.value}
                onChange={e => updateDraft(setting.key, { value: e.target.value })}
                className="search-input setting-value-number"
                min={ui.min ?? undefined}
                max={ui.max ?? undefined}
                step={stepProp}
              />
            );
          }
          case 'password':
            return (
              <input
                type="password"
                value={draft.value}
                onChange={e => updateDraft(setting.key, { value: e.target.value })}
                className="search-input setting-value-text"
                autoComplete="off"
              />
            );
          default:
            return (
              <input
                type="text"
                value={draft.value}
                onChange={e => updateDraft(setting.key, { value: e.target.value })}
                className="search-input setting-value-text"
              />
            );
        }
      };

      return (
        <tr key={setting.key} className="row-hover">
          <td className="font-bold">{setting.key}</td>
          <td>{renderTypeCell()}</td>
          <td>{renderValueCell()}</td>
          <td>
            <button
              className="btn-add"
              onClick={() => saveSetting(setting.key)}
              disabled={!dirty || savingKey === setting.key}
            >
              <Save size={14} style={{ marginRight: 6 }} />
              {savingKey === setting.key ? 'SAVING' : 'SAVE'}
            </button>
          </td>
        </tr>
      );
    });

  return (
    <div className="catalog-page">
      <div className="catalog-header">
        <div>
          <h2>ADMIN_SETTINGS</h2>
          <p className="text-muted">Live runtime configuration and recent changes</p>
        </div>
        <div className="catalog-controls">
          <span className="section-badge">{settings.length} KEYS</span>
          {hasChanges && <span className="mode-badge dry_run">UNSAVED_CHANGES</span>}
        </div>
      </div>

      {error && (
        <section className="terminal-section">
          <div className="section-header">
            <div className="header-title-group">
              <Settings size={16} className="icon-accent" />
              <h2>ERROR</h2>
            </div>
          </div>
          <div style={{ padding: '1rem 1.25rem' }} className="neg">{error}</div>
        </section>
      )}

      <div className="admin-settings-runtime-strip">
        <div className="header-title-group">
          <Settings size={16} className="icon-accent" />
          <h2 className="admin-settings-runtime-title">RUNTIME_SETTINGS</h2>
        </div>
        <span className="section-badge">{loading ? 'LOADING' : 'LIVE'}</span>
      </div>

      <div className="admin-settings-shell">
        <nav className="admin-settings-sidebar" aria-label="Settings categories">
          {settingSections.map(section => {
            const dirty = dirtyCountInSection(section);
            const isActive = resolvedPanelId === section.id;
            return (
              <button
                key={section.id}
                type="button"
                className={`admin-settings-nav-item${isActive ? ' admin-settings-nav-item--active' : ''}`}
                onClick={() => setActivePanelId(section.id)}
              >
                <span className="admin-settings-nav-label">{section.label}</span>
                <span className="admin-settings-nav-meta">
                  <span className="section-badge admin-settings-nav-count">{section.items.length}</span>
                  {dirty > 0 && (
                    <span className="admin-settings-nav-dirty" title={`${dirty} unsaved`}>
                      {dirty}
                    </span>
                  )}
                </span>
              </button>
            );
          })}
          <button
            type="button"
            className={`admin-settings-nav-item admin-settings-nav-item--audit${showAuditPanel ? ' admin-settings-nav-item--active' : ''}`}
            onClick={() => setActivePanelId(AUDIT_PANEL_ID)}
          >
            <span className="admin-settings-nav-label">AUDIT_LOG</span>
            <span className="section-badge admin-settings-nav-count" title="Rows loaded (max 50 from API)">
              {changes.length}
            </span>
          </button>
        </nav>

        <div className="admin-settings-content">
          {loading && settings.length === 0 && (
            <section className="terminal-section admin-settings-main-panel">
              <div className="section-header">
                <div className="header-title-group">
                  <Settings size={16} className="icon-accent" />
                  <h2>LOADING</h2>
                </div>
              </div>
              <p className="text-muted admin-settings-main-body">LOADING_RUNTIME_SETTINGS</p>
            </section>
          )}

          {!loading && settings.length === 0 && (
            <section className="terminal-section admin-settings-main-panel">
              <div className="section-header">
                <div className="header-title-group">
                  <Settings size={16} className="icon-accent" />
                  <h2>RUNTIME</h2>
                </div>
              </div>
              <p className="text-muted admin-settings-main-body">NO_SETTINGS_FOUND</p>
            </section>
          )}

          {!loading && settings.length > 0 && activeSection && !showAuditPanel && (
            <section className="terminal-section admin-settings-main-panel admin-settings-group-panel">
              <div className="section-header">
                <div className="header-title-group">
                  <Settings size={16} className="icon-accent" />
                  <h2>{activeSection.label}</h2>
                </div>
                <span className="section-badge">{activeSection.items.length}</span>
              </div>
              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>KEY</th>
                      <th>TYPE</th>
                      <th>VALUE</th>
                      <th>ACTION</th>
                    </tr>
                  </thead>
                  <tbody>{renderSettingTableRows(activeSection.items)}</tbody>
                </table>
              </div>
            </section>
          )}

          {!loading && showAuditPanel && (
            <section className="terminal-section admin-settings-main-panel">
              <div className="section-header">
                <div className="header-title-group">
                  <Settings size={16} className="icon-accent" />
                  <h2>SETTING_CHANGES</h2>
                </div>
                <span className="section-badge">RECENT_50</span>
              </div>
              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>TIME</th>
                      <th>KEY</th>
                      <th>OLD</th>
                      <th>NEW</th>
                      <th>SOURCE</th>
                      <th>REASON</th>
                    </tr>
                  </thead>
                  <tbody>
                    {changes.map((change, index) => (
                      <tr key={`${change.key}-${change.created_at}-${index}`} className="row-hover">
                        <td className="text-muted">{new Date(change.created_at).toLocaleString()}</td>
                        <td className="font-bold">{change.key}</td>
                        <td>{change.old_value ?? '--'}</td>
                        <td>{change.new_value}</td>
                        <td>{change.source}</td>
                        <td>{change.reason ?? '--'}</td>
                      </tr>
                    ))}
                    {changes.length === 0 && (
                      <tr>
                        <td colSpan={6} className="text-center text-muted">
                          NO_CHANGE_HISTORY
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          )}
        </div>
      </div>
    </div>
  );
};

export default AdminSettingsPage;
