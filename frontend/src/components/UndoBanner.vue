<script setup lang="ts">
import { ref } from 'vue';
import { api, userFacingError } from '../api';
import { appState, bumpRefresh, clearUndo, setToast } from '../state';

const restoring = ref(false);

async function restore(): Promise<void> {
  if (!appState.undo || restoring.value) return;
  restoring.value = true;
  const id = appState.undo.id;
  try {
    await api.restoreTransaction(id);
    clearUndo();
    bumpRefresh();
    setToast('已恢复这笔账。', 'success');
  } catch (error) {
    setToast(userFacingError(error, '恢复没有完成，请重试。'), 'error');
  } finally {
    restoring.value = false;
  }
}
</script>

<template>
  <div v-if="appState.undo" class="undo-banner" role="status" aria-live="polite">
    <span>已删除这笔账</span>
    <button type="button" :disabled="restoring" @click="restore">{{ restoring ? '恢复中…' : '撤销' }}</button>
  </div>
</template>
