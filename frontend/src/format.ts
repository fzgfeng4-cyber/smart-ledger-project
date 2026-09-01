import type { TransactionType } from './types';

export function todayIso(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function shiftDate(dateText: string, days: number): string {
  const [year, month, day] = dateText.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  date.setDate(date.getDate() + days);
  const nextYear = date.getFullYear();
  const nextMonth = String(date.getMonth() + 1).padStart(2, '0');
  const nextDay = String(date.getDate()).padStart(2, '0');
  return `${nextYear}-${nextMonth}-${nextDay}`;
}

export function formatCents(amount_cents: number | null): string {
  if (amount_cents === null || !Number.isSafeInteger(amount_cents)) {
    return '待选择';
  }
  const absolute = Math.abs(amount_cents);
  const yuan = Math.floor(absolute / 100).toLocaleString('zh-CN');
  const cents = String(absolute % 100).padStart(2, '0');
  return `¥${yuan}.${cents}`;
}

export function formatYuanInput(amount_cents: number | null): string {
  if (amount_cents === null || !Number.isSafeInteger(amount_cents)) {
    return '';
  }
  const yuan = Math.floor(amount_cents / 100);
  const cents = String(amount_cents % 100).padStart(2, '0');
  return `${yuan}.${cents}`;
}

export function parseYuanToCents(value: string): { amount_cents: number | null; error: string | null } {
  const text = value.trim();
  if (!text) {
    return { amount_cents: null, error: '请输入金额。' };
  }
  if (text.startsWith('-')) {
    return { amount_cents: null, error: '金额必须大于 0，请修改金额。' };
  }
  if (!/^\d+(?:\.\d*)?$/.test(text)) {
    return { amount_cents: null, error: '请输入有效金额，例如 35 或 35.80。' };
  }
  const [wholeText, fractionText = ''] = text.split('.');
  if (fractionText.length > 2) {
    return { amount_cents: null, error: '金额最多保留两位小数，请修改。' };
  }
  try {
    const centsBigInt = BigInt(wholeText) * 100n + BigInt(fractionText.padEnd(2, '0') || '0');
    if (centsBigInt <= 0n || centsBigInt > BigInt(Number.MAX_SAFE_INTEGER)) {
      return { amount_cents: null, error: '金额必须大于 0，且不能超过可安全表示的范围。' };
    }
    return { amount_cents: Number(centsBigInt), error: null };
  } catch {
    return { amount_cents: null, error: '请输入有效金额。' };
  }
}

export function normalizeNote(note: string | null): string | null {
  const normalized = note?.trim() ?? '';
  return normalized ? normalized : null;
}

export function isValidDateText(dateText: string | null): boolean {
  if (!dateText || !/^\d{4}-\d{2}-\d{2}$/.test(dateText)) {
    return false;
  }
  const [year, month, day] = dateText.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

export function isFutureDate(dateText: string | null): boolean {
  return Boolean(dateText && dateText > todayIso());
}

export function formatDate(dateText: string | null): string {
  if (!dateText || !isValidDateText(dateText)) {
    return '待修改';
  }
  const today = todayIso();
  if (dateText === today) {
    return `今天 · ${formatAbsoluteDate(dateText)}`;
  }
  if (dateText === shiftDate(today, -1)) {
    return `昨天 · ${formatAbsoluteDate(dateText)}`;
  }
  if (dateText === shiftDate(today, -2)) {
    return `前天 · ${formatAbsoluteDate(dateText)}`;
  }
  return formatAbsoluteDate(dateText);
}

export function formatAbsoluteDate(dateText: string): string {
  const [year, month, day] = dateText.split('-');
  return `${year}年${Number(month)}月${Number(day)}日`;
}

export function typeLabel(type: TransactionType | null): string {
  return type === 'income' ? '收入' : type === 'expense' ? '支出' : '待选择';
}
