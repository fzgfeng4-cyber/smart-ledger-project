import { ApiRequestError, type LedgerApi } from './api';
import { formatCents, shiftDate, todayIso } from './format';
import { V1_CATEGORIES, type CategoryCode, type CreateTransactionRequest, type ParseResponse, type Transaction, type TransactionDraft, type TransactionType } from './types';
import type { CreateTransactionResponse, DeleteResponse, RestoreResponse, SummaryResponse, TransactionListResponse, UpdateTransactionRequest } from './types';

const wait = (milliseconds = 120) => new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));

function isoAt(offsetMilliseconds = 0): string {
  return new Date(Date.now() + offsetMilliseconds).toISOString();
}

function mockTransaction(
  id: number,
  amount_cents: number,
  type: TransactionType,
  category: CategoryCode,
  note: string | null,
  original_text: string,
  transaction_date: string,
  timestampOffset: number,
): Transaction {
  const timestamp = isoAt(timestampOffset);
  return {
    id,
    amount_cents,
    type,
    category,
    note,
    original_text,
    transaction_date,
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
  };
}

const initialToday = todayIso();
const initialTransactions: Transaction[] = [
  mockTransaction(1, 3580, 'expense', 'groceries_food', '买菜和水果', '昨天35.80买菜和水果', shiftDate(initialToday, -1), -3600000),
  mockTransaction(2, 800000, 'income', 'salary', '工资', '工资8000', initialToday, -1800000),
];

let transactions = initialTransactions;
let nextId = 3;
const restoreExpirations = new Map<number, string>();

function cloneTransaction(transaction: Transaction): Transaction {
  return { ...transaction };
}

function cloneDraft(draft: TransactionDraft): TransactionDraft {
  return { ...draft };
}

function error(status: number, code: string, message: string, field?: string): ApiRequestError {
  return new ApiRequestError(status, code, message, field ? [{ field, message }] : []);
}

function draftResponse(
  status: ParseResponse['status'],
  draft: TransactionDraft,
  missing_fields: string[],
  warnings: ParseResponse['warnings'],
): ParseResponse {
  return {
    status,
    needs_confirmation: status !== 'ready',
    draft,
    missing_fields,
    warnings,
  };
}

function emptyDraftResponse(): ParseResponse {
  return {
    status: 'no_draft',
    needs_confirmation: false,
    draft: null,
    missing_fields: [],
    warnings: [],
  };
}

function parseFixture(original_text: string): ParseResponse {
  const text = original_text.trim();
  const transaction_date = todayIso();
  const ready = (amount_cents: number, type: TransactionType, category: CategoryCode, note: string, date = transaction_date): ParseResponse =>
    draftResponse('ready', { amount_cents, type, category, note, original_text, transaction_date: date }, [], []);

  if (text === '5块买菜') return ready(500, 'expense', 'groceries_food', '买菜');
  if (text === '18块吃面') return ready(1800, 'expense', 'dining', '吃面');
  if (text === '300加油') return ready(30000, 'expense', 'vehicle_fuel', '加油');
  if (text === '20打车') {
    return draftResponse('needs_confirmation', { amount_cents: 2000, type: 'expense', category: 'transportation', note: '打车', original_text, transaction_date }, [], [
      { code: 'BARE_AMOUNT', field: 'amount_cents', message: '未写元/块，请核对金额。', candidates: [] },
    ]);
  }
  if (text === '8000工资' || text === '工资8000') return ready(800000, 'income', 'salary', '工资');
  if (text === '昨天买菜35') return ready(3500, 'expense', 'groceries_food', '买菜', shiftDate(transaction_date, -1));
  if (text === '今天午饭15块') return ready(1500, 'expense', 'dining', '午饭');
  if (text === '给孩子买东西80') return ready(8000, 'expense', 'children', '给孩子买东西');
  if (text === '带孩子吃饭86') {
    return draftResponse('needs_confirmation', { amount_cents: 8600, type: 'expense', category: 'dining', note: '带孩子吃饭', original_text, transaction_date }, [], [
      { code: 'CATEGORY_CONFLICT', field: 'category', message: '同时出现孩子和餐饮信息，已按核心消费行为建议餐饮，可修改。', candidates: ['dining', 'children'] },
    ]);
  }
  if (text === '35') {
    return draftResponse('needs_input', { amount_cents: 3500, type: null, category: null, note: null, original_text, transaction_date }, ['type', 'category'], [
      { code: 'BARE_AMOUNT', field: 'amount_cents', message: '未写元/块，请核对金额。', candidates: [] },
    ]);
  }
  if (text === '买菜') {
    return draftResponse('needs_input', { amount_cents: null, type: 'expense', category: 'groceries_food', note: '买菜', original_text, transaction_date }, ['amount_cents'], [
      { code: 'MISSING_AMOUNT', field: 'amount_cents', message: '缺少金额', candidates: [] },
    ]);
  }
  if (text === '买菜35又打车20') {
    return draftResponse('needs_input', { amount_cents: null, type: 'expense', category: null, note: '买菜又打车', original_text, transaction_date }, ['amount_cents', 'category'], [
      { code: 'MULTIPLE_AMOUNTS', field: 'amount_cents', message: '识别到多个金额，一次只能记一笔账，请拆成两笔记录。', candidates: [] },
      { code: 'CATEGORY_AMBIGUOUS', field: 'category', message: '这句话可能包含多个事项，请选择一笔账对应的分类。', candidates: ['groceries_food', 'transportation'] },
    ]);
  }
  if (text === '奖金500') {
    return draftResponse('needs_confirmation', { amount_cents: 50000, type: 'income', category: 'other_income', note: '奖金', original_text, transaction_date }, [], [
      { code: 'CATEGORY_FALLBACK', field: 'category', message: '暂时没有更明确的收入分类，请确认或改选。', candidates: ['other_income'] },
    ]);
  }
  if (text === '买衣服200') {
    return draftResponse('needs_confirmation', { amount_cents: 20000, type: 'expense', category: 'other_expense', note: '买衣服', original_text, transaction_date }, [], [
      { code: 'CATEGORY_FALLBACK', field: 'category', message: '暂时没有更明确的支出分类，请确认或改选。', candidates: ['other_expense'] },
    ]);
  }
  if (text === '话费50') return ready(5000, 'expense', 'communication', '话费');
  if (text === '医院挂号20') return ready(2000, 'expense', 'medical', '医院挂号');
  if (text === '房租800') return ready(80000, 'expense', 'housing', '房租');
  if (text === '水果28') return ready(2800, 'expense', 'groceries_food', '水果');
  if (text === '麦当劳35') return ready(3500, 'expense', 'dining', '麦当劳');
  if (text === '12月20日买菜35') {
    const futureDate = shiftDate(transaction_date, 14);
    return draftResponse('needs_input', { amount_cents: 3500, type: 'expense', category: 'groceries_food', note: '买菜', original_text, transaction_date: futureDate }, [], [
      { code: 'FUTURE_DATE', field: 'transaction_date', message: '这个日期在未来，请检查日期。', candidates: [] },
    ]);
  }
  if (text === '0' || text === '0元' || text === '-5元' || text === '35.555') {
    const message = text === '35.555' ? '金额最多保留两位小数，请修改。' : '金额必须大于 0，请修改金额。';
    return draftResponse('needs_input', { amount_cents: null, type: 'expense', category: 'other_expense', note: null, original_text, transaction_date }, ['amount_cents'], [
      { code: 'INVALID_AMOUNT', field: 'amount_cents', message, candidates: [] },
    ]);
  }
  return emptyDraftResponse();
}

function validateTransactionPayload(payload: CreateTransactionRequest | UpdateTransactionRequest, original_text?: string): void {
  if (!Number.isSafeInteger(payload.amount_cents) || payload.amount_cents <= 0) {
    throw error(400, 'VALIDATION_ERROR', '金额必须大于 0，请修改金额。', 'amount_cents');
  }
  if (payload.type !== 'expense' && payload.type !== 'income') {
    throw error(400, 'VALIDATION_ERROR', '请选择收入或支出。', 'type');
  }
  const category = V1_CATEGORIES.find((item) => item.code === payload.category);
  if (!category || category.type !== payload.type) {
    throw error(400, 'VALIDATION_ERROR', '请选择与收入或支出匹配的分类。', 'category');
  }
  if (payload.note && payload.note.length > 200) {
    throw error(400, 'VALIDATION_ERROR', '备注最多 200 个字符，请修改。', 'note');
  }
  if (original_text !== undefined && (!original_text.trim() || original_text.length > 500)) {
    throw error(400, 'VALIDATION_ERROR', '原始输入不能为空且最多 500 个字符。', 'original_text');
  }
  const datePattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!datePattern.test(payload.transaction_date) || payload.transaction_date > todayIso()) {
    throw error(400, 'VALIDATION_ERROR', '这个日期在未来，请检查日期。', 'transaction_date');
  }
}

function sameBusinessValues(left: Transaction, right: CreateTransactionRequest): boolean {
  return left.deleted_at === null
    && left.transaction_date === right.transaction_date
    && left.amount_cents === right.amount_cents
    && left.type === right.type
    && left.category === right.category
    && left.note === right.note;
}

function sortTransactions(items: Transaction[]): Transaction[] {
  return [...items].sort((left, right) => {
    if (left.transaction_date !== right.transaction_date) return right.transaction_date.localeCompare(left.transaction_date);
    if (left.updated_at !== right.updated_at) return right.updated_at.localeCompare(left.updated_at);
    return right.id - left.id;
  });
}

export const mockApi: LedgerApi = {
  async parse(text) {
    await wait(260);
    if (!text.trim()) return emptyDraftResponse();
    return parseFixture(text);
  },

  async getCategories() {
    await wait();
    return { items: V1_CATEGORIES.map((category) => ({ ...category })) };
  },

  async createTransaction(payload) {
    await wait(220);
    validateTransactionPayload(payload, payload.original_text);
    const previous = [...transactions]
      .filter((transaction) => transaction.deleted_at === null)
      .sort((left, right) => right.created_at.localeCompare(left.created_at))[0];
    const isRecent = previous ? Date.now() - Date.parse(previous.created_at) <= 10 * 60 * 1000 : false;
    if (!payload.confirm_duplicate && previous && isRecent && sameBusinessValues(previous, payload)) {
      return {
        transaction: null,
        duplicate_warning: true,
        similar_transaction: cloneTransaction(previous),
        message: `刚刚似乎记过一笔 ${formatCents(payload.amount_cents)} ${payload.note ?? ''}`.trim(),
      };
    }
    const timestamp = isoAt();
    const transaction: Transaction = {
      id: nextId++,
      amount_cents: payload.amount_cents,
      type: payload.type,
      category: payload.category,
      note: payload.note,
      original_text: payload.original_text,
      transaction_date: payload.transaction_date,
      created_at: timestamp,
      updated_at: timestamp,
      deleted_at: null,
    };
    transactions = [...transactions, transaction];
    return { transaction: cloneTransaction(transaction), duplicate_warning: false, similar_transaction: null };
  },

  async listTransactions(params = {}) {
    await wait();
    const page = params.page ?? 1;
    const page_size = params.page_size ?? 50;
    const visible = sortTransactions(transactions.filter((transaction) => transaction.deleted_at === null));
    const start = (page - 1) * page_size;
    const items = visible.slice(start, start + page_size).map(cloneTransaction);
    return { items, page, page_size, total: visible.length, has_next: start + page_size < visible.length };
  },

  async getTransaction(id) {
    await wait();
    const transaction = transactions.find((item) => item.id === id && item.deleted_at === null);
    if (!transaction) throw error(404, 'NOT_FOUND', '找不到这笔账。');
    return cloneTransaction(transaction);
  },

  async updateTransaction(id, payload) {
    await wait(180);
    validateTransactionPayload(payload);
    const index = transactions.findIndex((item) => item.id === id && item.deleted_at === null);
    if (index < 0) throw error(404, 'NOT_FOUND', '找不到这笔账。');
    const current = transactions[index];
    const updated: Transaction = {
      ...current,
      amount_cents: payload.amount_cents,
      type: payload.type,
      category: payload.category,
      note: payload.note,
      transaction_date: payload.transaction_date,
      updated_at: isoAt(),
    };
    transactions = transactions.map((item, itemIndex) => itemIndex === index ? updated : item);
    return cloneTransaction(updated);
  },

  async deleteTransaction(id): Promise<DeleteResponse> {
    await wait(180);
    const index = transactions.findIndex((item) => item.id === id && item.deleted_at === null);
    if (index < 0) throw error(404, 'NOT_FOUND', '找不到这笔账。');
    const deleted_at = isoAt();
    const restore_available_until = new Date(Date.now() + 10000).toISOString();
    restoreExpirations.set(id, restore_available_until);
    transactions = transactions.map((item, itemIndex) => itemIndex === index ? { ...item, deleted_at, updated_at: deleted_at } : item);
    return { deleted: true, id, deleted_at, restore_available_until, restore_url: `/api/transactions/${id}/restore`, message: '已删除这笔账' };
  },

  async restoreTransaction(id): Promise<RestoreResponse> {
    await wait(180);
    const index = transactions.findIndex((item) => item.id === id);
    if (index < 0) throw error(404, 'NOT_FOUND', '找不到这笔账。');
    const current = transactions[index];
    if (current.deleted_at === null) throw error(409, 'NOT_DELETED', '这笔账当前没有被删除。');
    const expiration = restoreExpirations.get(id);
    if (!expiration || Date.now() > Date.parse(expiration)) throw error(409, 'RESTORE_WINDOW_EXPIRED', '撤销时间已过，暂时无法恢复。');
    const restored: Transaction = { ...current, deleted_at: null, updated_at: isoAt() };
    transactions = transactions.map((item, itemIndex) => itemIndex === index ? restored : item);
    restoreExpirations.delete(id);
    return { restored: true, transaction: cloneTransaction(restored) };
  },

  async getSummary(): Promise<SummaryResponse> {
    await wait();
    const currentDate = todayIso();
    const monthPrefix = currentDate.slice(0, 7);
    const valid = transactions.filter((transaction) => transaction.deleted_at === null);
    return {
      today_expense_cents: valid.filter((item) => item.type === 'expense' && item.transaction_date === currentDate).reduce((sum, item) => sum + item.amount_cents, 0),
      month_expense_cents: valid.filter((item) => item.type === 'expense' && item.transaction_date.startsWith(monthPrefix)).reduce((sum, item) => sum + item.amount_cents, 0),
      month_income_cents: valid.filter((item) => item.type === 'income' && item.transaction_date.startsWith(monthPrefix)).reduce((sum, item) => sum + item.amount_cents, 0),
    };
  },

  async downloadBackup(): Promise<Blob> {
    await wait(260);
    return new Blob(['Smart Ledger mock backup. Backend will provide a real SQLite backup.'], { type: 'application/vnd.sqlite3' });
  },
};
