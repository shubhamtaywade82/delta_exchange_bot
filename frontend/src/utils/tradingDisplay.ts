export function formatSignalActivityTimestamp(iso: string | undefined) {
  if (!iso) return '--';
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: 'short', timeStyle: 'medium' });
  } catch {
    return iso;
  }
}

export function sideBadgeMeta(side: unknown) {
  const normalized = String(side ?? '').trim().toLowerCase();
  if (normalized === 'buy' || normalized === 'long') {
    return { css: 'long', label: 'LONG' };
  }
  if (normalized === 'sell' || normalized === 'short') {
    return { css: 'short', label: 'SHORT' };
  }
  return { css: 'none', label: 'UNKNOWN' };
}
