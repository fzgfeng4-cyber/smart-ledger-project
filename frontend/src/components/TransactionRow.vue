<script setup lang="ts">
import { formatCents, formatDate, typeLabel } from '../format';
import type { Category, Transaction } from '../types';

const props = defineProps<{ transaction: Transaction; categories: Category[] }>();
const emit = defineEmits<{ open: [id: number] }>();

function categoryName(): string {
  return props.categories.find((category) => category.code === props.transaction.category)?.name ?? '未分类';
}
</script>

<template>
  <button class="transaction-row" type="button" @click="emit('open', transaction.id)">
    <span :class="['type-chip', transaction.type]">{{ typeLabel(transaction.type) }}</span>
    <strong class="row-amount">{{ formatCents(transaction.amount_cents) }}</strong>
    <span class="row-category">{{ categoryName() }}</span>
    <span class="row-note">{{ transaction.note || '未填写' }}</span>
    <span class="row-date">{{ formatDate(transaction.transaction_date) }}</span>
    <span class="row-arrow" aria-hidden="true">→</span>
  </button>
</template>
