<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, userFacingError } from './api';
import { currentRoute, navigate } from './router';
import { appState, setToast } from './state';
import type { Category } from './types';
import AppHeader from './components/AppHeader.vue';
import ToastMessage from './components/ToastMessage.vue';
import UndoBanner from './components/UndoBanner.vue';
import HomePage from './pages/HomePage.vue';
import TransactionsPage from './pages/TransactionsPage.vue';
import WorkPage from './pages/WorkPage.vue';

const categories = ref<Category[]>([]);

async function loadCategories(): Promise<void> {
  try {
    categories.value = (await api.getCategories()).items;
  } catch (error) {
    setToast(userFacingError(error, '分类暂时加载失败，请重试。'), 'error');
  }
}

async function downloadBackup(): Promise<void> {
  setToast('正在准备备份。', 'info');
  try {
    const blob = await api.downloadBackup();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    const now = new Date();
    const date = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
    const time = `${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}${String(now.getSeconds()).padStart(2, '0')}`;
    link.download = `smart-ledger-backup-${date}-${time}.sqlite`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    setToast('备份文件已开始下载。', 'success');
  } catch (error) {
    setToast(userFacingError(error, '备份暂时失败，请稍后重试。'), 'error');
  }
}

function startNewEntry(): void {
  if (currentRoute.value.name === 'work') {
    setToast('请先保存或返回，避免丢失当前内容。', 'info');
    return;
  }
  const source = currentRoute.value.name === 'transactions' ? 'transactions' : 'home';
  if (appState.pendingDraft?.response.draft) {
    navigate(`/transactions/new?source=${source}`);
    return;
  }
  navigate(`/transactions/new?source=${source}`);
}

onMounted(loadCategories);
</script>

<template>
  <div class="app-shell">
    <AppHeader :active="currentRoute.name" @navigate="navigate" @new-entry="startNewEntry" @backup="downloadBackup" />
    <main class="main-content">
      <HomePage v-if="currentRoute.name === 'home'" :key="'home'" :categories="categories" />
      <TransactionsPage v-else-if="currentRoute.name === 'transactions'" :key="'transactions'" :categories="categories" />
      <WorkPage v-else :key="`${currentRoute.id ?? 'new'}-${currentRoute.source}`" :id="currentRoute.id" :source="currentRoute.source" :categories="categories" />
    </main>
    <ToastMessage />
    <UndoBanner />
  </div>
</template>
