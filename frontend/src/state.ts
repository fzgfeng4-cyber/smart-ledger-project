import { reactive, ref } from 'vue';
import type { ParseResponse } from './types';

export interface PendingDraft {
  response: ParseResponse;
  source: 'home' | 'transactions';
}

export const appState = reactive({
  composerText: '',
  pendingDraft: null as PendingDraft | null,
  toast: null as { message: string; tone: 'success' | 'error' | 'info' } | null,
  undo: null as { id: number; expiresAt: number } | null,
});

export const refreshVersion = ref(0);
let toastTimer: number | undefined;
let undoTimer: number | undefined;

export function bumpRefresh(): void {
  refreshVersion.value += 1;
}

export function setToast(message: string, tone: 'success' | 'error' | 'info' = 'info'): void {
  appState.toast = { message, tone };
  if (toastTimer !== undefined) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    appState.toast = null;
    toastTimer = undefined;
  }, 4200);
}

export function setUndo(id: number, duration = 10000): void {
  if (undoTimer !== undefined) window.clearTimeout(undoTimer);
  appState.undo = { id, expiresAt: Date.now() + duration };
  undoTimer = window.setTimeout(() => {
    appState.undo = null;
    undoTimer = undefined;
  }, duration);
}

export function clearUndo(): void {
  if (undoTimer !== undefined) window.clearTimeout(undoTimer);
  undoTimer = undefined;
  appState.undo = null;
}
