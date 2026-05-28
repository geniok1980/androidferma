<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { useEmulatorStore } from '@/stores/emulators'
import EmulatorList from './EmulatorList.vue'
import CreateEmulatorForm from './CreateEmulatorForm.vue'
import EmulatorPoolPanel from './EmulatorPoolPanel.vue'

const store = useEmulatorStore()
const activeSubTab = ref<'emulators' | 'pool'>('emulators')
const toast = ref<{ msg: string; type: 'ok' | 'err' } | null>(null)

let pollTimer: ReturnType<typeof setInterval> | null = null

function showToast(msg: string, type: 'ok' | 'err' = 'ok') {
  toast.value = { msg, type }
  setTimeout(() => { toast.value = null }, 4000)
}

async function handleStart(name: string) {
  try {
    const r = await store.startAvd(name)
    showToast(`${name}: запуск → ${r.serial}`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleStop(name: string) {
  try {
    await store.stopAvd(name)
    showToast(`${name}: остановлено`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleDelete(name: string) {
  if (!confirm(`Удалить эмулятор «${name}»? Будут удалены AVD и все данные.`)) return
  try {
    await store.deleteAvd(name)
    showToast(`${name}: удалено`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleSetup(name: string) {
  try {
    await store.setupAvd(name)
    showToast(`${name}: настроено для автоматизации`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleCreate(payload: Record<string, any>) {
  try {
    await store.createAvd(payload as any)
    showToast(`Создано: ${payload.name}`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleScaleUp(count: number) {
  try {
    await store.poolScaleUp(count)
    showToast(`Увеличиваю пул на ${count} эмуляторов...`)
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleScaleDown(count?: number) {
  try {
    await store.poolScaleDown(count)
    showToast('Уменьшил пул: простаивающие эмуляторы остановлены')
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

async function handleStopAll() {
  if (!confirm('Остановить ВСЕ эмуляторы в пуле?')) return
  try {
    await store.poolStopAll()
    showToast('Все эмуляторы пула остановлены')
  } catch (e: any) {
    showToast(e.message, 'err')
  }
}

onMounted(async () => {
  await Promise.all([
    store.fetchPrerequisites(),
    store.fetchAvds(true),   // show spinner on first load only
    store.fetchSystemImages(),
    store.fetchPoolStatus(),
  ])
  // Poll AVD status every 5s (silent — no loading flash)
  pollTimer = setInterval(() => {
    store.fetchAvds()
    if (activeSubTab.value === 'pool') store.fetchPoolStatus()
  }, 5000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
})
</script>

<template>
  <div>
    <!-- Toast -->
    <Transition name="fade">
      <div
        v-if="toast"
        class="fixed top-4 right-4 z-50 px-4 py-2 rounded-lg text-sm font-medium shadow-lg"
        :style="{
          background: toast.type === 'ok' ? '#065f46' : '#7f1d1d',
          color: toast.type === 'ok' ? '#6ee7b7' : '#fca5a5',
          border: `1px solid ${toast.type === 'ok' ? '#059669' : '#dc2626'}`,
        }"
      >
        {{ toast.msg }}
      </div>
    </Transition>

    <!-- Prerequisites warning -->
    <div
      v-if="store.prerequisites && !store.prerequisites.emulator_binary"
      class="card mb-4 px-4 py-3"
      style="border-color: #ef4444; background: #ef444410"
    >
      <div class="text-sm font-semibold" style="color: #ef4444">Android SDK не найден</div>
      <div class="text-xs mt-1" style="color: var(--text-3)">
        Бинарник emulator не найден по пути {{ store.prerequisites.sdk_root }}/emulator/emulator.
        Установите Android SDK или задайте ANDROID_SDK_ROOT.
      </div>
    </div>

    <div
      v-if="store.prerequisites && !store.prerequisites.hw_accel"
      class="card mb-4 px-4 py-3"
      style="border-color: #f59e0b; background: #f59e0b10"
    >
      <div class="text-sm font-semibold" style="color: #f59e0b">Аппаратное ускорение недоступно</div>
      <div class="text-xs mt-1" style="color: var(--text-3)">
        {{ store.prerequisites.hw_accel_type }} недоступно. Эмуляторы будут работать без ускорения (очень медленно).
      </div>
    </div>

    <!-- Sub-tabs -->
    <div class="flex gap-2 mb-4">
      <button
        class="px-4 py-1.5 text-sm font-semibold rounded-lg transition-colors"
        :class="activeSubTab === 'emulators'
          ? 'text-indigo-400 bg-indigo-500/10'
          : 'text-slate-500 hover:text-slate-300'"
        @click="activeSubTab = 'emulators'"
      >Эмуляторы</button>
      <button
        class="px-4 py-1.5 text-sm font-semibold rounded-lg transition-colors"
        :class="activeSubTab === 'pool'
          ? 'text-indigo-400 bg-indigo-500/10'
          : 'text-slate-500 hover:text-slate-300'"
        @click="activeSubTab = 'pool'; store.fetchPoolStatus()"
      >Пул</button>
    </div>

    <!-- Emulators sub-tab -->
    <div v-show="activeSubTab === 'emulators'" class="space-y-4">
      <!-- Summary cards -->
      <div class="grid grid-cols-3 gap-3">
        <div class="stat-card">
          <h3 style="color: #34d399">{{ store.runningCount }}</h3>
          <p>Запущено</p>
        </div>
        <div class="stat-card">
          <h3 style="color: var(--text-3)">{{ store.stoppedCount }}</h3>
          <p>Остановлено</p>
        </div>
        <div class="stat-card">
          <h3 style="color: var(--accent-lt)">{{ store.systemImages.length }}</h3>
          <p>Образы системы</p>
        </div>
      </div>

      <EmulatorList
        :avds="store.avds"
        :loading="store.loading"
        @start="handleStart"
        @stop="handleStop"
        @delete="handleDelete"
        @setup="handleSetup"
      />

      <CreateEmulatorForm
        :system-images="store.systemImages"
        :has-cmdline-tools="store.prerequisites?.cmdline_tools ?? false"
        @create="handleCreate"
      />
    </div>

    <!-- Pool sub-tab -->
    <div v-show="activeSubTab === 'pool'">
      <EmulatorPoolPanel
        :pool="store.poolStatus"
        @scale-up="handleScaleUp"
        @scale-down="handleScaleDown"
        @stop-all="handleStopAll"
        @refresh="store.fetchPoolStatus()"
      />
    </div>

    <!-- Error display -->
    <div v-if="store.error" class="mt-4 card px-4 py-3" style="border-color: #ef4444">
      <div class="text-xs" style="color: #ef4444">{{ store.error }}</div>
    </div>
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
