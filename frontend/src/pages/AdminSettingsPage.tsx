import React, { useEffect, useMemo, useState } from 'react';
import axios from 'axios';
import { Settings, Save } from 'lucide-react';

type ValueType = 'string' | 'integer' | 'float' | 'boolean';

interface RuntimeSetting {
  key: string;
  value: string;
  value_type: ValueType;
  typed_value: string | number | boolean | null;
}

interface SettingChange {
  key: string;
  old_value: string | null;
  new_value: string;
  source: string;
  reason: string | null;
  created_at: string;
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
    } catch (e) {
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
    } catch (_e) {
      setError(`Failed to save setting: ${key}`);
    } finally {
      setSavingKey(null);
    }
  };

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

      <section className="terminal-section">
        <div className="section-header">
          <div className="header-title-group">
            <Settings size={16} className="icon-accent" />
            <h2>RUNTIME_SETTINGS</h2>
          </div>
          <span className="section-badge">{loading ? 'LOADING' : 'LIVE'}</span>
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
            <tbody>
              {settings.map(setting => {
                const draft = drafts[setting.key] || { value: setting.value, value_type: setting.value_type };
                const dirty = draft.value !== setting.value || draft.value_type !== setting.value_type;
                return (
                  <tr key={setting.key} className="row-hover">
                    <td className="font-bold">{setting.key}</td>
                    <td>
                      <select
                        value={draft.value_type}
                        onChange={e => updateDraft(setting.key, { value_type: e.target.value as ValueType })}
                        className="search-input"
                        style={{ padding: '0.45rem 0.75rem', maxWidth: '130px' }}
                      >
                        <option value="string">string</option>
                        <option value="integer">integer</option>
                        <option value="float">float</option>
                        <option value="boolean">boolean</option>
                      </select>
                    </td>
                    <td>
                      <input
                        value={draft.value}
                        onChange={e => updateDraft(setting.key, { value: e.target.value })}
                        className="search-input"
                        style={{ padding: '0.45rem 0.75rem' }}
                      />
                    </td>
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
              })}
              {!loading && settings.length === 0 && (
                <tr>
                  <td colSpan={4} className="text-center text-muted">NO_SETTINGS_FOUND</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

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
