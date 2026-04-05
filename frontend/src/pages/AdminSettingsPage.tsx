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

const SETTING_GROUP_ORDER = [
  'bot',
  'strategy',
  'risk',
  'runner',
  'regime',
  'notifications',
  'logging',
  'learning',
  'ai',
] as const;

const SETTING_GROUP_LABELS: Record<string, string> = {
  bot: 'BOT',
  strategy: 'STRATEGY',
  risk: 'RISK',
  runner: 'RUNNER',
  regime: 'REGIME',
  notifications: 'NOTIFICATIONS',
  logging: 'LOGGING',
  learning: 'LEARNING',
  ai: 'AI',
};

function settingGroupPrefix(key: string): string {
  const dot = key.indexOf('.');
  return dot === -1 ? 'other' : key.slice(0, dot).toLowerCase();
}

interface SettingGroupSection {
  id: string;
  label: string;
  items: RuntimeSetting[];
}

function buildSettingGroupSections(settings: RuntimeSetting[]): SettingGroupSection[] {
  const buckets: Record<string, RuntimeSetting[]> = {};
  settings.forEach(s => {
    const g = settingGroupPrefix(s.key);
    if (!buckets[g]) buckets[g] = [];
    buckets[g].push(s);
  });
  Object.values(buckets).forEach(list => list.sort((a, b) => a.key.localeCompare(b.key)));

  const seen = new Set<string>();
  const sections: SettingGroupSection[] = [];

  SETTING_GROUP_ORDER.forEach(id => {
    const items = buckets[id];
    if (!items?.length) return;
    sections.push({ id, label: SETTING_GROUP_LABELS[id] ?? id.toUpperCase(), items });
    seen.add(id);
  });

  Object.keys(buckets)
    .filter(id => !seen.has(id))
    .sort()
    .forEach(id => {
      const items = buckets[id];
      if (!items?.length) return;
      sections.push({ id, label: id === 'other' ? 'OTHER' : id.toUpperCase(), items });
    });

  return sections;
}

const AdminSettingsPage: React.FC = () => {
  const [settings, setSettings] = useState<RuntimeSetting[]>([]);
  const [changes, setChanges] = useState<SettingChange[]>([]);
  const [drafts, setDrafts] = useState<Record<string, { value: string; value_type: ValueType }>>({});
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string>('');

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

      <div className="admin-settings-panel-stack">
        {loading && settings.length === 0 && (
          <section className="terminal-section admin-settings-panel-span-full">
            <div className="section-header">
              <div className="header-title-group">
                <Settings size={16} className="icon-accent" />
                <h2>LOADING</h2>
              </div>
            </div>
            <p className="text-muted" style={{ padding: '1rem 1.25rem', margin: 0 }}>
              LOADING_RUNTIME_SETTINGS
            </p>
          </section>
        )}

        {!loading && settings.length === 0 && (
          <section className="terminal-section admin-settings-panel-span-full">
            <div className="section-header">
              <div className="header-title-group">
                <Settings size={16} className="icon-accent" />
                <h2>RUNTIME</h2>
              </div>
            </div>
            <p className="text-muted" style={{ padding: '1rem 1.25rem', margin: 0 }}>
              NO_SETTINGS_FOUND
            </p>
          </section>
        )}

        {!loading &&
          settingSections.map(section => (
            <section key={section.id} className="terminal-section admin-settings-group-panel">
              <div className="section-header">
                <div className="header-title-group">
                  <Settings size={16} className="icon-accent" />
                  <h2>{section.label}</h2>
                </div>
                <span className="section-badge">{section.items.length}</span>
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
                  <tbody>{renderSettingTableRows(section.items)}</tbody>
                </table>
              </div>
            </section>
          ))}
      </div>

      <section className="terminal-section">
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
                  <td colSpan={6} className="text-center text-muted">NO_CHANGE_HISTORY</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
};

export default AdminSettingsPage;
