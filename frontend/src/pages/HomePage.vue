<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import { api, userFacingError, usingMockApi } from '../api';
import { formatCents } from '../format';
import { navigate } from '../router';
import { appState, refreshVersion, setToast } from '../state';
import type { Category, SummaryResponse, Transaction } from '../types';
import StatsStrip from '../components/StatsStrip.vue';
import TransactionRow from '../components/TransactionRow.vue';

const props = defineProps<{ categories: Category[] }>();
const quickText = ref(appState.composerText);
const summary = ref<SummaryResponse | null>(null);
const recentTransactions = ref<Transaction[]>([]);
const summaryLoading = ref(true);
const listLoading = ref(true);
const summaryError = ref(false);
const listError = ref(false);
const isParsing = ref(false);
const inputError = ref('');

watch(() => appState.composerText, (value) => {
  if (value !== quickText.value) quickText.value = value;
});

async function loadSummary(): Promise<void> {
  summaryLoading.value = true;
  summaryError.value = false;
  try {
    summary.value = await api.getSummary();
  } catch (error) {
    summary.value = null;
    summaryError.value = true;
    setToast(userFacingError(error, '统计暂时不可用，请重试。'), 'error');
  } finally {
    summaryLoading.value = false;
  }
}

async function loadRecent(): Promise<void> {
  listLoading.value = true;
  listError.value = false;
  try {
    recentTransactions.value = (await api.listTransactions({ page: 1, page_size: 5 })).items;
  } catch (error) {
    recentTransactions.value = [];
    listError.value = true;
    setToast(userFacingError(error, '账单暂时加载失败，请重试。'), 'error');
  } finally {
    listLoading.value = false;
  }
}

async function load(): Promise<void> {
  await Promise.all([loadSummary(), loadRecent()]);
}

async function parseInput(): Promise<void> {
  inputError.value = '';
  if (!quickText.value.trim()) {
    inputError.value = '请输入一笔账，例如：35块买菜。';
    return;
  }
  isParsing.value = true;
  appState.composerText = quickText.value;
  try {
    const response = await api.parse(quickText.value);
    if (response.status === 'no_draft' || !response.draft) {
      inputError.value = '暂时没看懂这句话，请输入“金额 + 事项”，原输入已保留。';
      return;
    }
    appState.pendingDraft = { response, source: 'home' };
    appState.composerText = '';
    navigate('/transactions/new');
  } catch (error) {
    inputError.value = userFacingError(error, '暂时无法连接本地服务，请确认 Smart Ledger 已启动。');
  } finally {
    isParsing.value = false;
  }
}

function openTransaction(id: number): void {
  navigate(`/transactions/${id}?source=home`);
}

onMounted(load);
watch(refreshVersion, load);
</script>

<template>
  <div class="page-content home-page">
    <section class="page-intro">
      <div>
        <p class="eyebrow">个人账本</p>
        <h1>今天的账，记得简单一点。</h1>
        <p class="intro-copy">把发生过的一笔账说出来，确认后再保存。</p>
      </div>
      <span class="date-stamp">本地账本</span>
    </section>

    <StatsStrip :summary="summary" :loading="summaryLoading" />

    <div v-if="summaryError" class="inline-error">
      <span>统计暂时不可用，请重试。</span>
      <button type="button" class="text-button" @click="loadSummary">重试</button>
    </div>

    <section class="quick-entry surface-panel" aria-labelledby="quick-entry-title">
      <div class="section-heading compact-heading">
        <div>
          <p class="eyebrow">快速记录</p>
          <h2 id="quick-entry-title">快速记账</h2>
        </div>
        <span class="section-hint">先识别，再确认</span>
      </div>
      <form class="quick-form" @submit.prevent="parseInput">
        <label class="sr-only" for="quick-text">一句话记账</label>
        <input
          id="quick-text"
          v-model="quickText"
          class="quick-input"
          type="text"
          autocomplete="off"
          placeholder="例如：35块买菜"
          @keydown.enter.exact.prevent="parseInput"
        />
        <button class="button button-primary parse-button" type="submit" :disabled="isParsing">
          <span aria-hidden="true">✦</span>
          {{ isParsing ? '识别中' : '识别' }}
        </button>
      </form>
      <p v-if="inputError" class="field-error" role="alert">{{ inputError }}</p>
      <p v-else class="quick-footnote">例如：35块买菜、昨天午饭18块、8000工资</p>
    </section>

    <section class="recent-section" aria-labelledby="recent-title">
      <div class="section-heading">
        <div>
          <p class="eyebrow">最近动态</p>
          <h2 id="recent-title">最近账目</h2>
        </div>
        <button class="text-button with-arrow" type="button" @click="navigate('/transactions')">查看全部 <span aria-hidden="true">→</span></button>
      </div>

      <div v-if="listLoading" class="loading-state">正在加载账目…</div>
      <div v-else-if="listError" class="error-state">
        <p>账单暂时加载失败，请重试。</p>
        <button type="button" class="button button-secondary" @click="loadRecent">重试</button>
      </div>
      <div v-else-if="recentTransactions.length" class="transaction-list">
        <TransactionRow
          v-for="transaction in recentTransactions"
          :key="transaction.id"
          :transaction="transaction"
          :categories="props.categories"
          @open="openTransaction"
        />
      </div>
      <div v-else class="empty-state">
        <span class="empty-icon" aria-hidden="true">＋</span>
        <h3>还没有账目</h3>
        <p>输入第一笔，例如“35块买菜”。</p>
      </div>
    </section>

    <p v-if="usingMockApi" class="mock-note">当前使用前端 mock API 演示，确认后的账目仅在本次页面运行期间保留。</p>
  </div>
</template>
