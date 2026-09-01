<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import { api, userFacingError } from '../api';
import { navigate } from '../router';
import { refreshVersion, setToast } from '../state';
import type { Category, Transaction } from '../types';
import TransactionRow from '../components/TransactionRow.vue';

const props = defineProps<{ categories: Category[] }>();
const PAGE_SIZE = 50;
const transactions = ref<Transaction[]>([]);
const loading = ref(true);
const loadingMore = ref(false);
const loadError = ref(false);
const page = ref(1);
const total = ref(0);
const hasNext = ref(false);

async function loadPage(nextPage: number, append = false): Promise<void> {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    loadError.value = false;
  }
  try {
    const result = await api.listTransactions({ page: nextPage, page_size: PAGE_SIZE });
    transactions.value = append ? [...transactions.value, ...result.items] : result.items;
    page.value = result.page;
    total.value = result.total;
    hasNext.value = result.has_next;
  } catch (error) {
    if (!append) {
      transactions.value = [];
      total.value = 0;
      hasNext.value = false;
      loadError.value = true;
    }
    setToast(userFacingError(error, '账单暂时加载失败，请重试。'), 'error');
  } finally {
    loading.value = false;
    loadingMore.value = false;
  }
}

async function load(): Promise<void> {
  await loadPage(1);
}

async function loadMore(): Promise<void> {
  if (!hasNext.value || loadingMore.value) return;
  await loadPage(page.value + 1, true);
}

onMounted(load);
watch(refreshVersion, load);
</script>

<template>
  <div class="page-content list-page">
    <section class="page-title-row">
      <div>
        <p class="eyebrow">全部账目</p>
        <h1>账单</h1>
        <p class="page-subtitle">按账务日期查看所有有效账目</p>
      </div>
      <button class="button button-primary" type="button" @click="navigate('/transactions/new?source=transactions')">
        <span aria-hidden="true">＋</span> 记一笔
      </button>
    </section>

    <div v-if="loading" class="loading-state">正在加载账目…</div>
    <div v-else-if="loadError" class="error-state page-error-state">
      <div>
        <h2>账单暂时加载失败，请重试。</h2>
        <p>当前页面没有用空列表代替读取失败。</p>
      </div>
      <button type="button" class="button button-secondary" @click="load">重试</button>
    </div>
    <div v-else-if="transactions.length" class="list-panel surface-panel">
      <div class="list-toolbar">
        <span>全部账目</span>
        <span class="muted-label">已显示 {{ transactions.length }} / 共 {{ total }} 笔</span>
      </div>
      <div class="transaction-list">
        <TransactionRow
          v-for="transaction in transactions"
          :key="transaction.id"
          :transaction="transaction"
          :categories="props.categories"
          @open="(id) => navigate(`/transactions/${id}`)"
        />
      </div>
      <div v-if="hasNext" class="load-more-row">
        <button class="button button-secondary" type="button" :disabled="loadingMore" @click="loadMore">
          {{ loadingMore ? '加载中' : '加载更多' }}
        </button>
      </div>
    </div>
    <div v-else class="empty-state list-empty-state">
      <span class="empty-icon" aria-hidden="true">＋</span>
      <h2>还没有账单</h2>
      <p>记下第一笔实际发生的账目。</p>
      <button type="button" class="button button-primary" @click="navigate('/transactions/new?source=transactions')">记一笔</button>
    </div>
  </div>
</template>
