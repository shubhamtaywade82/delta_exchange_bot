export function formatSignalActivityTimestamp(iso: string | undefined) {
  if (!iso) return '--';
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: 'short', timeStyle: 'medium' });
  } catch {
    return iso;
  }
}

/** Fixed 4 fractional digits when non-whole; trailing zeros; whole values render without a decimal part. */
export const DISPLAY_DECIMAL_PLACES = 4 as const;

export function formatDisplayDecimal(value: unknown): string {
  if (value == null || value === '') return '--';
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return String(value);

  const fixed = n.toFixed(DISPLAY_DECIMAL_PLACES);
  const dot = fixed.indexOf('.');
  const intStr = dot >= 0 ? fixed.slice(0, dot) : fixed;
  const fracStr = dot >= 0 ? fixed.slice(dot + 1) : '';
  const fracIsZero = fracStr === '0'.repeat(DISPLAY_DECIMAL_PLACES);

  if (fracIsZero) {
    return Number(intStr).toLocaleString(undefined, { maximumFractionDigits: 0 });
  }

  const intFormatted = Number(intStr).toLocaleString(undefined, { maximumFractionDigits: 0 });
  return `${intFormatted}.${fracStr}`;
}

export function formatUsd(value: unknown): string {
  const core = formatDisplayDecimal(value);
  if (core === '--') return '--';
  return `$${core}`;
}

export function formatInr(value: unknown): string {
  const core = formatDisplayDecimal(value);
  if (core === '--') return '--';
  return `₹${core}`;
}

/** Quote / mark / entry prices — same rules as all dashboard numerics. */
export function formatQuotePrice(value: unknown): string {
  return formatDisplayDecimal(value);
}

/**
 * Shorter numbers for dense SMC bands (large handles get fewer decimals).
 */
export function formatSmcPrice(value: unknown): string {
  if (value == null || value === '') return '—';
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return '—';
  const abs = Math.abs(n);
  const decimals = abs >= 10_000 ? 1 : abs >= 1_000 ? 2 : abs >= 1 ? 3 : 4;
  return n.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: decimals,
  });
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
