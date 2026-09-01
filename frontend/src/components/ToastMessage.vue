<script setup lang="ts">
import { appState } from '../state';
</script>

<template>
  <div v-if="appState.toast" :class="['toast-message', appState.toast.tone]" role="status" aria-live="polite">
    <span class="toast-dot" aria-hidden="true"></span>
    {{ appState.toast.message }}
  </div>
</template>
