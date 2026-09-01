<script setup lang="ts">
import { formatCents } from '../format';
import type { SummaryResponse } from '../types';

defineProps<{ summary: SummaryResponse | null; loading: boolean }>();
</script>

<template>
  <section class="stats-grid" aria-label="账目统计">
    <div class="stat-item">
      <span class="stat-label">今天支出</span>
      <strong v-if="!loading && summary" class="stat-value expense-value">{{ formatCents(summary.today_expense_cents) }}</strong>
      <strong v-else-if="loading" class="stat-value stat-loading">...</strong>
      <strong v-else class="stat-value stat-unavailable">暂不可用</strong>
    </div>
    <div class="stat-item">
      <span class="stat-label">本月支出</span>
      <strong v-if="!loading && summary" class="stat-value expense-value">{{ formatCents(summary.month_expense_cents) }}</strong>
      <strong v-else-if="loading" class="stat-value stat-loading">...</strong>
      <strong v-else class="stat-value stat-unavailable">暂不可用</strong>
    </div>
    <div class="stat-item">
      <span class="stat-label">本月收入</span>
      <strong v-if="!loading && summary" class="stat-value income-value">{{ formatCents(summary.month_income_cents) }}</strong>
      <strong v-else-if="loading" class="stat-value stat-loading">...</strong>
      <strong v-else class="stat-value stat-unavailable">暂不可用</strong>
    </div>
  </section>
</template>
