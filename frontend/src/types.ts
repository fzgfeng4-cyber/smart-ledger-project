export type TransactionType = 'expense' | 'income';

export type CategoryCode =
  | 'dining'
  | 'groceries_food'
  | 'daily_necessities'
  | 'transportation'
  | 'vehicle_fuel'
  | 'housing'
  | 'communication'
  | 'entertainment'
  | 'children'
  | 'medical'
  | 'other_expense'
  | 'salary'
  | 'other_income';

export type ParseStatus = 'ready' | 'needs_confirmation' | 'needs_input' | 'no_draft';

export interface Category {
  code: CategoryCode;
  name: string;
  type: TransactionType;
}

export interface Transaction {
  id: number;
  amount_cents: number;
  type: TransactionType;
  category: CategoryCode;
  note: string | null;
  original_text: string;
  transaction_date: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TransactionDraft {
  amount_cents: number | null;
  type: TransactionType | null;
  category: CategoryCode | null;
  note: string | null;
  original_text: string;
  transaction_date: string | null;
}

export interface ParseWarning {
  code: string;
  field: string | null;
  message: string;
  candidates: string[];
}

export interface ParseResponse {
  status: ParseStatus;
  needs_confirmation: boolean;
  draft: TransactionDraft | null;
  missing_fields: string[];
  warnings: ParseWarning[];
}

export interface TransactionListResponse {
  items: Transaction[];
  page: number;
  page_size: number;
  total: number;
  has_next: boolean;
}

export interface SummaryResponse {
  today_expense_cents: number;
  month_expense_cents: number;
  month_income_cents: number;
}

export interface CreateTransactionRequest {
  amount_cents: number;
  type: TransactionType;
  category: CategoryCode;
  note: string | null;
  original_text: string;
  transaction_date: string;
  confirm_duplicate?: boolean;
}

export interface UpdateTransactionRequest {
  amount_cents: number;
  type: TransactionType;
  category: CategoryCode;
  note: string | null;
  transaction_date: string;
}

export interface CreateTransactionResponse {
  transaction: Transaction | null;
  duplicate_warning: boolean;
  similar_transaction: Transaction | null;
  message?: string;
}

export interface DeleteResponse {
  deleted: true;
  id: number;
  deleted_at: string;
  restore_available_until: string;
  restore_url: string;
  message: string;
}

export interface RestoreResponse {
  restored: true;
  transaction: Transaction;
}

export interface ErrorDetail {
  field: string;
  message: string;
}

export interface ErrorPayload {
  error: {
    code: string;
    message: string;
    details?: ErrorDetail[];
  };
}

export const V1_CATEGORIES: Category[] = [
  { code: 'dining', name: '餐饮', type: 'expense' },
  { code: 'groceries_food', name: '买菜/食品', type: 'expense' },
  { code: 'daily_necessities', name: '日用品', type: 'expense' },
  { code: 'transportation', name: '交通', type: 'expense' },
  { code: 'vehicle_fuel', name: '车辆/加油', type: 'expense' },
  { code: 'housing', name: '居住', type: 'expense' },
  { code: 'communication', name: '通讯', type: 'expense' },
  { code: 'entertainment', name: '娱乐', type: 'expense' },
  { code: 'children', name: '孩子', type: 'expense' },
  { code: 'medical', name: '医疗', type: 'expense' },
  { code: 'other_expense', name: '其他支出', type: 'expense' },
  { code: 'salary', name: '工资', type: 'income' },
  { code: 'other_income', name: '其他收入', type: 'income' },
];
