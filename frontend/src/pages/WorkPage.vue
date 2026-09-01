<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue';
import { api, userFacingError } from '../api';
import { formatCents, formatDate, formatYuanInput, isFutureDate, isValidDateText, normalizeNote, parseYuanToCents, todayIso, typeLabel } from '../format';
import { navigate } from '../router';
import { appState, bumpRefresh, setToast, setUndo } from '../state';
import type { Category, CategoryCode, CreateTransactionResponse, ParseWarning, Transaction, TransactionDraft, TransactionType } from '../types';

const props = defineProps<{ id: number | null; source: 'home' | 'transactions'; categories: Category[] }>();

const isEditMode = computed(() => props.id !== null);
const pageTitle = computed(() => isEditMode.value ? '编辑账目' : '新增账目');
const primaryLabel = computed(() => isEditMode.value ? '保存修改' : '确认记账');
const draft = reactive<TransactionDraft>({ amount_cents: null, type: null, category: null, note: null, original_text: '', transaction_date: null });
const amountText = ref('');
const warnings = ref<ParseWarning[]>([]);
const acknowledgedWarningCodes = ref<string[]>([]);
const loading = ref(true);
const loadError = ref('');
const saving = ref(false);
const parsing = ref(false);
const awaitingInput = ref(false);
const entryText = ref(appState.composerText);
const deleting = ref(false);
const showDeleteConfirm = ref(false);
const fieldError = ref('');
const duplicateResponse = ref<CreateTransactionResponse | null>(null);
const showSimilar = ref(false);

const categoryOptions = computed(() => props.categories.filter((category) => category.type === draft.type));
const categoryName = computed(() => props.categories.find((category) => category.code === draft.category)?.name ?? '待选择');
const hasWarning = (code: string): boolean => warnings.value.some((warning) => warning.code === code);
const isAcknowledged = (code: string): boolean => acknowledgedWarningCodes.value.includes(code);

function markAcknowledged(...codes: string[]): void {
  const merged = new Set(acknowledgedWarningCodes.value);
  codes.forEach((code) => merged.add(code));
  acknowledgedWarningCodes.value = [...merged];
}

function applyDraft(source: TransactionDraft, nextWarnings: ParseWarning[] = []): void {
  Object.assign(draft, {
    amount_cents: source.amount_cents,
    type: source.type,
    category: source.category,
    note: source.note,
    original_text: source.original_text,
    transaction_date: source.transaction_date,
  });
  amountText.value = formatYuanInput(source.amount_cents);
  warnings.value = nextWarnings;
  acknowledgedWarningCodes.value = [];
  awaitingInput.value = false;
}

async function load(): Promise<void> {
  loading.value = true;
  loadError.value = '';
  duplicateResponse.value = null;
  if (!isEditMode.value) {
    const pending = appState.pendingDraft;
    if (!pending?.response.draft) {
      entryText.value = appState.composerText;
      awaitingInput.value = true;
      loading.value = false;
      return;
    }
    applyDraft(pending.response.draft, pending.response.warnings);
    appState.pendingDraft = null;
    loading.value = false;
    return;
  }
  try {
    const transaction = await api.getTransaction(props.id as number);
    applyDraft({
      amount_cents: transaction.amount_cents,
      type: transaction.type,
      category: transaction.category,
      note: transaction.note,
      original_text: transaction.original_text,
      transaction_date: transaction.transaction_date,
    });
  } catch (error) {
    loadError.value = userFacingError(error, '找不到这笔账。');
  } finally {
    loading.value = false;
  }
}

async function parseEntry(): Promise<void> {
  fieldError.value = '';
  if (!entryText.value.trim()) {
    fieldError.value = '请输入一笔账，例如：35块买菜。';
    return;
  }
  parsing.value = true;
  appState.composerText = entryText.value;
  try {
    const response = await api.parse(entryText.value);
    if (response.status === 'no_draft' || !response.draft) {
      fieldError.value = '暂时没看懂这句话，请输入“金额 + 事项”，原输入已保留。';
      return;
    }
    appState.composerText = '';
    applyDraft(response.draft, response.warnings);
  } catch (error) {
    fieldError.value = userFacingError(error, '暂时无法连接本地服务，请确认 Smart Ledger 已启动。');
  } finally {
    parsing.value = false;
  }
}

function setAmount(value: string): void {
  amountText.value = value;
  const result = parseYuanToCents(value);
  draft.amount_cents = result.amount_cents;
  fieldError.value = result.error ?? '';
  if (result.amount_cents !== null) {
    warnings.value = warnings.value.filter((warning) => warning.code !== 'MISSING_AMOUNT' && warning.code !== 'INVALID_AMOUNT');
    markAcknowledged('BARE_AMOUNT');
  }
}

function formatAmountOnBlur(): void {
  if (draft.amount_cents !== null && !fieldError.value) amountText.value = formatYuanInput(draft.amount_cents);
}

function setType(type: TransactionType): void {
  fieldError.value = '';
  draft.type = type;
  const selected = props.categories.find((category) => category.code === draft.category);
  if (!selected || selected.type !== type) draft.category = null;
  markAcknowledged('TYPE_UNKNOWN', 'TYPE_CONFLICT');
}

function setCategory(category: CategoryCode): void {
  fieldError.value = '';
  draft.category = category;
  markAcknowledged('CATEGORY_FALLBACK', 'CATEGORY_CONFLICT', 'CATEGORY_AMBIGUOUS');
}

function confirmSuggestedCategory(): void {
  fieldError.value = '';
  markAcknowledged('CATEGORY_FALLBACK', 'CATEGORY_CONFLICT', 'CATEGORY_AMBIGUOUS');
}

function setDate(value: string): void {
  fieldError.value = '';
  draft.transaction_date = value || null;
  if (isValidDateText(value) && !isFutureDate(value)) {
    warnings.value = warnings.value.filter((warning) => warning.code !== 'FUTURE_DATE' && warning.code !== 'INVALID_DATE');
  }
}

function warningForField(field: string): ParseWarning | undefined {
  return warnings.value.find((warning) => warning.field === field);
}

function fieldStatus(field: string): string {
  const warning = warningForField(field);
  if (warning && !isAcknowledged(warning.code) && warning.code !== 'FUTURE_DATE') {
    if (warning.code === 'MISSING_AMOUNT' && draft.amount_cents === null) return '待选择';
    if (warning.code === 'BARE_AMOUNT') return '待确认';
    return warning.code === 'CATEGORY_FALLBACK' || warning.code.startsWith('CATEGORY_') ? '待确认' : '待修改';
  }
  if (field === 'amount_cents' && draft.amount_cents === null) return '待选择';
  if (field === 'type' && draft.type === null) return '待选择';
  if (field === 'category' && draft.category === null) return '待选择';
  if (field === 'transaction_date' && (!draft.transaction_date || isFutureDate(draft.transaction_date))) return '待修改';
  return '已识别';
}

const localValidationMessage = computed(() => {
  if (fieldError.value) return fieldError.value;
  if (draft.amount_cents === null || draft.amount_cents <= 0) return '请输入大于 0 的金额。';
  if (!draft.type) return '请选择收入或支出。';
  const category = props.categories.find((item) => item.code === draft.category);
  if (!category || category.type !== draft.type) return '请选择与收入或支出匹配的分类。';
  if (!draft.transaction_date || !isValidDateText(draft.transaction_date)) return '这个日期无法识别，请选择有效的今天或历史日期。';
  if (isFutureDate(draft.transaction_date)) return '这个日期在未来，请检查日期。';
  if (draft.note && draft.note.length > 200) return '备注最多 200 个字符，请修改。';
  if (!draft.original_text.trim() || draft.original_text.length > 500) return '原始输入不能为空且最多 500 个字符。';
  return '';
});

const unresolvedWarnings = computed(() => warnings.value.filter((warning) => {
  if (warning.code === 'FUTURE_DATE') return !draft.transaction_date || isFutureDate(draft.transaction_date);
  if (warning.code === 'MISSING_AMOUNT' || warning.code === 'INVALID_AMOUNT') return draft.amount_cents === null || draft.amount_cents <= 0;
  if (warning.code === 'MULTIPLE_AMOUNTS') return true;
  if (warning.code === 'CATEGORY_FALLBACK' || warning.code === 'CATEGORY_CONFLICT' || warning.code === 'CATEGORY_AMBIGUOUS') return !isAcknowledged(warning.code);
  if (warning.code === 'BARE_AMOUNT') return draft.amount_cents === null || !isAcknowledged(warning.code);
  return !isAcknowledged(warning.code);
}));

const canSave = computed(() => !loading.value && !saving.value && !localValidationMessage.value && unresolvedWarnings.value.length === 0);
const blockedReason = computed(() => {
  if (localValidationMessage.value) return localValidationMessage.value;
  if (unresolvedWarnings.value.some((warning) => warning.code === 'MULTIPLE_AMOUNTS')) return '请把原句改写成一笔账，再重新识别。';
  if (unresolvedWarnings.value.some((warning) => warning.code.startsWith('CATEGORY_'))) return '请先处理分类提示。';
  if (unresolvedWarnings.value.some((warning) => warning.code === 'FUTURE_DATE')) return '请把日期改为今天或过去的日期。';
  return '请先检查并确认待处理字段。';
});

const deleteSummary = computed(() => `${formatDate(draft.transaction_date)}  ${typeLabel(draft.type)}  ${formatCents(draft.amount_cents)}  ${categoryName.value}  ${draft.note || '未填写'}`);

function payloadForCreate(confirm_duplicate = false) {
  return {
    amount_cents: draft.amount_cents as number,
    type: draft.type as TransactionType,
    category: draft.category as CategoryCode,
    note: normalizeNote(draft.note),
    original_text: draft.original_text,
    transaction_date: draft.transaction_date as string,
    confirm_duplicate,
  };
}

function payloadForUpdate() {
  return {
    amount_cents: draft.amount_cents as number,
    type: draft.type as TransactionType,
    category: draft.category as CategoryCode,
    note: normalizeNote(draft.note),
    transaction_date: draft.transaction_date as string,
  };
}

async function save(): Promise<void> {
  if (!canSave.value) return;
  saving.value = true;
  fieldError.value = '';
  try {
    if (isEditMode.value) {
      await api.updateTransaction(props.id as number, payloadForUpdate());
      bumpRefresh();
      setToast(`已保存修改 ${formatCents(draft.amount_cents)} ${categoryName.value}`, 'success');
      navigate(props.source === 'home' ? '/' : '/transactions');
      return;
    }
    const result = await api.createTransaction(payloadForCreate());
    if (result.duplicate_warning) {
      duplicateResponse.value = result;
      showSimilar.value = false;
      return;
    }
    bumpRefresh();
    setToast(`已记账 ${formatCents(draft.amount_cents)} ${categoryName.value}`, 'success');
    navigate(props.source === 'home' ? '/' : '/transactions');
  } catch (error) {
    fieldError.value = userFacingError(error, '这笔账还没有保存成功，内容已保留，请重试。');
  } finally {
    saving.value = false;
  }
}

async function saveDespiteDuplicate(): Promise<void> {
  if (!canSave.value || saving.value) return;
  saving.value = true;
  try {
    const result = await api.createTransaction(payloadForCreate(true));
    if (!result.transaction) throw new Error('duplicate save did not return a transaction');
    duplicateResponse.value = null;
    bumpRefresh();
    setToast(`已记账 ${formatCents(draft.amount_cents)} ${categoryName.value}`, 'success');
    navigate(props.source === 'home' ? '/' : '/transactions');
  } catch (error) {
    fieldError.value = userFacingError(error, '这笔账还没有保存成功，内容已保留，请重试。');
  } finally {
    saving.value = false;
  }
}

function backToInput(): void {
  appState.composerText = draft.original_text;
  entryText.value = draft.original_text;
  awaitingInput.value = true;
  warnings.value = [];
  acknowledgedWarningCodes.value = [];
  duplicateResponse.value = null;
  fieldError.value = '';
}

function separateEntries(): void {
  appState.composerText = draft.original_text;
  entryText.value = draft.original_text;
  awaitingInput.value = true;
  warnings.value = [];
  acknowledgedWarningCodes.value = [];
  duplicateResponse.value = null;
  setToast('请返回输入框，分别输入两笔账。', 'info');
  fieldError.value = '';
}

async function confirmDelete(): Promise<void> {
  if (!isEditMode.value || deleting.value) return;
  deleting.value = true;
  try {
    await api.deleteTransaction(props.id as number);
    setUndo(props.id as number);
    bumpRefresh();
    setToast('已删除这笔账。', 'success');
    navigate(props.source === 'home' ? '/' : '/transactions');
  } catch (error) {
    fieldError.value = userFacingError(error, '删除没有完成，原账仍保留，请重试。');
  } finally {
    deleting.value = false;
    showDeleteConfirm.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="page-content work-page">
    <div v-if="loading" class="loading-state">正在打开账目…</div>
    <div v-else-if="loadError" class="error-state page-error-state">
      <div>
        <h1>{{ loadError }}</h1>
        <p>这笔账可能已经被删除，或暂时无法读取。</p>
      </div>
      <button type="button" class="button button-secondary" @click="navigate(props.source === 'home' ? '/' : '/transactions')">返回</button>
    </div>
    <template v-else-if="awaitingInput && !isEditMode">
      <section class="work-heading">
        <button class="back-link" type="button" @click="navigate(props.source === 'transactions' ? '/transactions' : '/')">
          <span aria-hidden="true">←</span>
          返回{{ props.source === 'transactions' ? '账单' : '首页' }}
        </button>
        <div class="work-title-line">
          <div>
            <p class="eyebrow">新增账目</p>
            <h1>记一笔</h1>
          </div>
          <span class="draft-status is-blocked">等待输入</span>
        </div>
      </section>

      <section class="quick-entry surface-panel" aria-labelledby="work-quick-entry-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">快速记录</p>
            <h2 id="work-quick-entry-title">一句话记账</h2>
          </div>
          <span class="section-hint">先识别，再确认</span>
        </div>
        <form class="quick-form" @submit.prevent="parseEntry">
          <label class="sr-only" for="work-quick-text">一句话记账</label>
          <input
            id="work-quick-text"
            v-model="entryText"
            class="quick-input"
            type="text"
            autocomplete="off"
            placeholder="例如：35块买菜"
            @keydown.enter.exact.prevent="parseEntry"
          />
          <button class="button button-primary parse-button" type="submit" :disabled="parsing">
            <span aria-hidden="true">✦</span>
            {{ parsing ? '识别中' : '识别' }}
          </button>
        </form>
        <p v-if="fieldError" class="field-error" role="alert">{{ fieldError }}</p>
        <p v-else class="quick-footnote">输入后会进入确认页，不会自动保存。</p>
      </section>
    </template>

    <template v-else>
      <section class="work-heading">
        <button class="back-link" type="button" @click="isEditMode ? navigate(props.source === 'home' ? '/' : '/transactions') : backToInput()">
          <span aria-hidden="true">←</span>
          {{ isEditMode ? '返回账单' : '返回修改原句' }}
        </button>
        <div class="work-title-line">
          <div>
            <p class="eyebrow">{{ isEditMode ? '编辑账目' : '确认账目' }}</p>
            <h1>{{ pageTitle }}</h1>
          </div>
          <span :class="['draft-status', { 'is-blocked': !canSave }]">{{ canSave ? '可以保存' : '需要确认' }}</span>
        </div>
      </section>

      <section class="original-text-panel surface-panel">
        <span class="field-label">{{ isEditMode ? '最初输入' : '原始输入' }}</span>
        <p>{{ draft.original_text }}</p>
        <span v-if="isEditMode" class="readonly-note">只读，普通编辑不会修改原始输入</span>
      </section>

      <section v-if="warnings.length" class="warning-stack" aria-label="识别提示">
        <div v-for="warning in warnings" :key="warning.code" :class="['warning-card', { resolved: !unresolvedWarnings.includes(warning) }]">
          <span class="warning-icon" aria-hidden="true">!</span>
          <div>
            <strong>{{ unresolvedWarnings.includes(warning) ? '需要确认' : '已处理' }}</strong>
            <p>{{ warning.message }}</p>
          </div>
        </div>
      </section>

      <section class="editor-panel surface-panel" aria-label="账目字段">
        <div :class="['editor-row', { 'has-error': fieldStatus('amount_cents') === '待修改' }]">
          <div class="editor-label"><span>金额</span><small>{{ fieldStatus('amount_cents') }}</small></div>
          <div class="editor-control amount-control">
            <span class="currency-symbol">¥</span>
            <input v-model="amountText" type="text" inputmode="decimal" placeholder="请输入金额" aria-label="金额" @input="setAmount(amountText)" @blur="formatAmountOnBlur" />
          </div>
          <button v-if="hasWarning('BARE_AMOUNT') && !isAcknowledged('BARE_AMOUNT') && draft.amount_cents !== null" type="button" class="confirm-inline-button amount-confirm-button" @click="markAcknowledged('BARE_AMOUNT')">金额无误</button>
        </div>

        <div :class="['editor-row', { 'has-error': !draft.type }]">
          <div class="editor-label"><span>收入/支出</span><small>{{ fieldStatus('type') }}</small></div>
          <div class="segmented-control" role="group" aria-label="收入或支出">
            <button type="button" :class="{ selected: draft.type === 'expense' }" @click="setType('expense')">支出</button>
            <button type="button" :class="{ selected: draft.type === 'income' }" @click="setType('income')">收入</button>
          </div>
        </div>

        <div :class="['editor-row category-row', { 'has-error': fieldStatus('category') !== '已识别' }]">
          <div class="editor-label"><span>分类</span><small>{{ fieldStatus('category') }}</small></div>
          <div class="category-control">
            <div class="category-current">{{ categoryName }}</div>
            <div v-if="categoryOptions.length" class="category-options">
              <button v-for="category in categoryOptions" :key="category.code" type="button" :class="{ selected: draft.category === category.code }" @click="setCategory(category.code)">{{ category.name }}</button>
            </div>
            <div v-if="unresolvedWarnings.some((warning) => warning.code === 'CATEGORY_CONFLICT')" class="category-actions">
              <button type="button" class="choice-button" @click="setCategory('dining')">保留餐饮</button>
              <button type="button" class="choice-button" @click="setCategory('children')">改为孩子</button>
            </div>
            <button v-if="unresolvedWarnings.some((warning) => warning.code === 'CATEGORY_FALLBACK')" type="button" class="confirm-inline-button" @click="confirmSuggestedCategory">保留 {{ categoryName }}</button>
          </div>
        </div>

        <div class="editor-row">
          <div class="editor-label"><span>备注</span><small>{{ draft.note ? '已识别' : '未填写' }}</small></div>
          <input v-model="draft.note" class="text-input" type="text" maxlength="200" placeholder="未填写" aria-label="备注" @input="fieldError = ''" />
        </div>

        <div :class="['editor-row', { 'has-error': fieldStatus('transaction_date') === '待修改' }]">
          <div class="editor-label"><span>日期</span><small>{{ fieldStatus('transaction_date') }}</small></div>
          <div class="date-control">
            <input :value="draft.transaction_date ?? ''" type="date" :max="todayIso()" aria-label="账务日期" @input="setDate(($event.target as HTMLInputElement).value)" />
            <span class="date-preview">{{ formatDate(draft.transaction_date) }}</span>
          </div>
        </div>
      </section>

      <div v-if="fieldError" class="form-error" role="alert">{{ fieldError }}</div>
      <div v-if="!canSave" class="save-hint">{{ blockedReason }}</div>

      <section v-if="duplicateResponse?.duplicate_warning" class="duplicate-panel surface-panel">
        <div class="duplicate-heading"><span class="warning-icon" aria-hidden="true">!</span><div><strong>{{ duplicateResponse.message || '刚刚似乎记过一笔相同账目' }}</strong><p>你可以返回修改，也可以明确继续保存。</p></div></div>
        <button type="button" class="text-button" @click="showSimilar = !showSimilar">{{ showSimilar ? '收起上一笔' : '查看上一笔' }}</button>
        <div v-if="showSimilar && duplicateResponse.similar_transaction" class="similar-summary">
          {{ formatDate(duplicateResponse.similar_transaction.transaction_date) }} · {{ typeLabel(duplicateResponse.similar_transaction.type) }} · {{ formatCents(duplicateResponse.similar_transaction.amount_cents) }} · {{ categoryName }} · {{ duplicateResponse.similar_transaction.note || '未填写' }}
        </div>
        <button class="button button-primary" type="button" :disabled="saving" @click="saveDespiteDuplicate">{{ saving ? '保存中' : '仍然记账' }}</button>
      </section>

      <div class="work-actions">
        <button class="button button-primary save-button" type="button" :disabled="!canSave" @click="save">
          <span aria-hidden="true">✓</span> {{ saving ? '保存中' : primaryLabel }}
        </button>
        <button v-if="isEditMode" class="danger-link" type="button" :disabled="deleting" @click="showDeleteConfirm = true">删除账目</button>
      </div>

      <div v-if="unresolvedWarnings.some((warning) => warning.code === 'MULTIPLE_AMOUNTS')" class="secondary-actions">
        <button type="button" class="button button-secondary" @click="backToInput">返回修改原句</button>
        <button type="button" class="text-button" @click="separateEntries">分别输入两笔</button>
      </div>
    </template>

    <div v-if="showDeleteConfirm" class="modal-backdrop" role="presentation">
      <section class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="delete-title">
        <div class="modal-icon" aria-hidden="true">!</div>
        <h2 id="delete-title">确定删除这笔账吗？</h2>
        <p>{{ deleteSummary }}</p>
        <div class="modal-actions">
          <button type="button" class="button button-secondary" @click="showDeleteConfirm = false">取消</button>
          <button type="button" class="button button-danger" :disabled="deleting" @click="confirmDelete">{{ deleting ? '删除中' : '删除' }}</button>
        </div>
      </section>
    </div>
  </div>
</template>
