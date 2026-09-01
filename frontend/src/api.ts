import { mockApi } from './mock-api';
import type {
  Category,
  CreateTransactionRequest,
  CreateTransactionResponse,
  DeleteResponse,
  ErrorDetail,
  ErrorPayload,
  ParseResponse,
  RestoreResponse,
  SummaryResponse,
  Transaction,
  TransactionListResponse,
  UpdateTransactionRequest,
} from './types';

export class ApiRequestError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: ErrorDetail[];

  constructor(status: number, code: string, message: string, details: ErrorDetail[] = []) {
    super(message);
    this.name = 'ApiRequestError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export interface LedgerApi {
  parse(text: string): Promise<ParseResponse>;
  getCategories(): Promise<{ items: Category[] }>;
  createTransaction(payload: CreateTransactionRequest): Promise<CreateTransactionResponse>;
  listTransactions(params?: { page?: number; page_size?: number }): Promise<TransactionListResponse>;
  getTransaction(id: number): Promise<Transaction>;
  updateTransaction(id: number, payload: UpdateTransactionRequest): Promise<Transaction>;
  deleteTransaction(id: number): Promise<DeleteResponse>;
  restoreTransaction(id: number): Promise<RestoreResponse>;
  getSummary(): Promise<SummaryResponse>;
  downloadBackup(): Promise<Blob>;
}

async function readError(response: Response): Promise<ApiRequestError> {
  let payload: ErrorPayload | null = null;
  try {
    payload = (await response.json()) as ErrorPayload;
  } catch {
    payload = null;
  }
  return new ApiRequestError(
    response.status,
    payload?.error?.code ?? 'INTERNAL_ERROR',
    payload?.error?.message ?? '请求暂时失败，请稍后重试。',
    payload?.error?.details ?? [],
  );
}

class HttpApi implements LedgerApi {
  private readonly baseUrl = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8000';

  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}${path}`, {
        ...init,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          ...(init?.headers ?? {}),
        },
      });
    } catch {
      throw new ApiRequestError(0, 'SERVICE_UNAVAILABLE', '暂时无法连接本地服务，请确认 Smart Ledger 已启动。');
    }
    if (!response.ok) {
      throw await readError(response);
    }
    return (await response.json()) as T;
  }

  parse(text: string): Promise<ParseResponse> {
    return this.request<ParseResponse>('/api/parse', {
      method: 'POST',
      body: JSON.stringify({ text }),
    });
  }

  getCategories(): Promise<{ items: Category[] }> {
    return this.request<{ items: Category[] }>('/api/categories');
  }

  createTransaction(payload: CreateTransactionRequest): Promise<CreateTransactionResponse> {
    return this.request<CreateTransactionResponse>('/api/transactions', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  listTransactions(params: { page?: number; page_size?: number } = {}): Promise<TransactionListResponse> {
    const page = params.page ?? 1;
    const page_size = params.page_size ?? 50;
    return this.request<TransactionListResponse>(`/api/transactions?page=${page}&page_size=${page_size}`);
  }

  getTransaction(id: number): Promise<Transaction> {
    return this.request<Transaction>(`/api/transactions/${id}`);
  }

  updateTransaction(id: number, payload: UpdateTransactionRequest): Promise<Transaction> {
    return this.request<Transaction>(`/api/transactions/${id}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }

  deleteTransaction(id: number): Promise<DeleteResponse> {
    return this.request<DeleteResponse>(`/api/transactions/${id}`, { method: 'DELETE' });
  }

  restoreTransaction(id: number): Promise<RestoreResponse> {
    return this.request<RestoreResponse>(`/api/transactions/${id}/restore`, { method: 'POST' });
  }

  getSummary(): Promise<SummaryResponse> {
    return this.request<SummaryResponse>('/api/summary');
  }

  async downloadBackup(): Promise<Blob> {
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/api/backup`);
    } catch {
      throw new ApiRequestError(0, 'SERVICE_UNAVAILABLE', '暂时无法连接本地服务，请确认 Smart Ledger 已启动。');
    }
    if (!response.ok) {
      throw await readError(response);
    }
    return response.blob();
  }
}

export const usingMockApi = import.meta.env.VITE_USE_MOCK === 'true';
export const api: LedgerApi = usingMockApi ? mockApi : new HttpApi();

export function userFacingError(error: unknown, fallback: string): string {
  if (error instanceof ApiRequestError) {
    return error.message;
  }
  return fallback;
}
