<script setup lang="ts">
import { ref } from 'vue';
import type { Route } from '../router';

defineProps<{ active: Route['name'] }>();
const emit = defineEmits<{ navigate: [path: string]; newEntry: []; backup: [] }>();
const menuOpen = ref(false);

function go(path: string): void {
  menuOpen.value = false;
  emit('navigate', path);
}

function requestBackup(): void {
  menuOpen.value = false;
  emit('backup');
}

function requestNewEntry(): void {
  menuOpen.value = false;
  emit('newEntry');
}
</script>

<template>
  <header class="app-header">
    <div class="header-inner">
      <button class="brand-button" type="button" aria-label="返回首页" @click="go('/')">
        <span class="brand-mark" aria-hidden="true">S</span>
        <span>Smart Ledger</span>
      </button>
      <nav class="main-nav" aria-label="主导航">
        <button type="button" :class="['nav-link', { active: active === 'home' }]" @click="go('/')">首页</button>
        <button type="button" :class="['nav-link', { active: active === 'transactions' }]" @click="go('/transactions')">账单</button>
      </nav>
      <div class="header-actions">
        <button class="button button-primary button-small" type="button" @click="requestNewEntry">
          <span aria-hidden="true">＋</span> 记一笔
        </button>
        <div class="menu-wrap">
          <button class="button button-quiet button-small" type="button" :aria-expanded="menuOpen" @click="menuOpen = !menuOpen">
            <span aria-hidden="true">⋯</span> 更多
          </button>
          <div v-if="menuOpen" class="more-menu" role="menu">
            <button type="button" role="menuitem" @click="requestBackup">
              <span aria-hidden="true">↓</span>
              <span>
                <strong>备份数据</strong>
                <small>下载一份本地账目备份文件</small>
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </header>
</template>
