<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick } from 'vue'
import { api } from '@/composables/useApi'

/* ── State ── */
const activity = ref('post')
const devices = ref<{serial: string; nickname?: string; model?: string; label?: string}[]>([])
const selectedDevice = ref('')
const accounts = ref<{handle: string; is_default?: number}[]>([])
const selectedAccount = ref('')
const botRunning = ref(false)
const botStatusLabel = ref('Ожидание')
const botStatusSub = ref('Бот не запущен')
const botStatusDot = ref('#374151')
const botStatusGlow = ref(false)
const logLines = ref<string[]>([])
const logLineCount = ref(0)
const autoScroll = ref(true)
let pollTimer: number | null = null
let logSince = 0

/* ── Post settings ── */
const postVideoSearch = ref('')
const postVideo = ref('')
const postPostId = ref('')
const postVideoLabel = ref('')
const postVideoDropdownVisible = ref(false)
const postVideoResults = ref<any[]>([])
const postHashtags = ref<string[]>([])
const postHashtagInput = ref('')
const postCaption = ref('')
const postAction = ref('draft')
const postInjectTts = ref(true)

/* ── Queue ── */
const queueJobs = ref<any[]>([])

/* ── History ── */
const history = ref<any[]>([])

/* ── Computed ── */
const startButtonLabel = computed(() => {
  const labels: Record<string, string> = {
    post: '📹 Начать загрузку',
    publish_draft: '📤 Опубликовать черновик',
  }
  return labels[activity.value] || '▶ Старт'
})

/* ── Data loading ── */
async function loadDevices() {
  try {
    const resp = await api('/api/phone/devices')
    devices.value = resp.devices || resp || []
    const first = devices.value[0]
    if (first && !selectedDevice.value) selectedDevice.value = first.serial
  } catch { /* ignore */ }
}

function hidePostVideoDropdownLater() {
  window.setTimeout(() => { postVideoDropdownVisible.value = false }, 150)
}

async function loadAccounts() {
  try {
    const resp = await api('/api/accounts')
    accounts.value = Array.isArray(resp) ? resp : []
    const def = accounts.value.find(a => a.is_default)
    if (def) selectedAccount.value = def.handle
  } catch {
    accounts.value = []
  }
}

async function loadHistory() {
  try { history.value = await api('/api/bot/history') } catch { history.value = [] }
}

/* ── Log colour helper ── */
function colorLine(line: string): string {
  if (!line) return '<span style="color:#374151"> </span>'
  const col =
    line.startsWith('[done]')     ? '#22c55e' :
    line.startsWith('[error]') || line.toLowerCase().includes('error') || line.includes('Traceback') ? '#f87171' :
    line.startsWith('[pass')      ? '#a78bfa' :
    line.startsWith('[enrich]') || line.startsWith('[profile]') ? '#38bdf8' :
    line.startsWith('[nav]')   || line.startsWith('[filters]') ? '#6366f1' :
    line.startsWith('[db]')    || line.startsWith('[csv]')     ? '#f59e0b' :
    line.startsWith('  Saved')    ? '#34d399' :
    line.startsWith('  skip')     ? '#475569' :
    line.startsWith('[bot]')      ? '#38bdf8' :
    line.startsWith('[wait]')     ? '#64748b' :
    line.startsWith('[start]')    ? '#a78bfa' :
    line.includes('\u2713')       ? '#22c55e' :
    line.includes('[Step')        ? '#a78bfa' :
    line.includes('[queue]')      ? '#f59e0b' :
    '#94a3b8'
  const safe = line.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  return `<span style="color:${col}">${safe}</span>`
}

/* ── Polling ── */
async function pollOnce() {
  try {
    const d = await api<any>(`/api/bot/logs?since=${logSince}`)
    if (!d) return

    if (d.lines?.length) {
      const logEl = document.getElementById('bot-log')
      if (logSince === 0 && logEl) logEl.innerHTML = ''
      if (logEl) {
        logEl.innerHTML += d.lines.map(colorLine).join('\n') + '\n'
      }
      logSince = d.total
      logLineCount.value = d.total
      if (autoScroll.value && logEl) {
        nextTick(() => { logEl!.scrollTop = logEl!.scrollHeight })
      }
    } else {
      logLineCount.value = d.total || logSince
    }

    // Queue + status
    queueJobs.value = d.jobs || []
    updateStatus(d.running, d.returncode, d.jobs || [])

    const hasPending = (d.jobs || []).some((j: any) => j.status === 'pending' || j.status === 'running')
    if (!d.running && !hasPending) pollStop()
  } catch { /* ignore */ }
}

function updateStatus(running: boolean, returncode: number | null, jobs: any[]) {
  const pending = jobs.filter(j => j.status === 'pending').length
  const runningJob = jobs.find(j => j.status === 'running')

  if (running) {
    botStatusDot.value = '#22c55e'
    botStatusGlow.value = true
    const jt = runningJob?.job_type || 'post'
    const typeLabel: Record<string, string> = {
      post: 'Загрузка видео', publish_draft: 'Публикация черновика',
    }
    botStatusLabel.value = 'Выполняется'
    botStatusSub.value = pending
      ? `${typeLabel[jt] || 'Активно'} \u00b7 в очереди: ${pending}`
      : typeLabel[jt] || 'Бот активен'
    botRunning.value = true
  } else {
    const lastDone = jobs.filter(j => j.status === 'done' || j.status === 'stopped').pop()
    const rc = returncode ?? lastDone?.returncode
    botStatusDot.value = pending ? '#f59e0b' : rc === 0 ? '#6366f1' : rc != null ? '#f87171' : '#374151'
    botStatusGlow.value = false
    botStatusLabel.value = pending ? 'В очереди' : rc === 0 ? 'Готово' : rc != null ? 'Остановлено' : 'Ожидание'
    botStatusSub.value = pending ? `Ожидает запуск: ${pending}`
      : rc === 0 ? 'Последний запуск завершился успешно'
      : rc != null ? `Код выхода: ${rc}` : 'Бот не запущен'
    botRunning.value = false
  }
}

function pollStart() {
  pollOnce()
  if (!pollTimer) pollTimer = window.setInterval(pollOnce, 2000)
}

function pollStop() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
}

/* ── Post video search helpers ── */
async function pbVideoFilter(q: string) {
  if (!q.trim()) { postVideoResults.value = []; return }
  try {
    const r = await api(`/api/gen/videos?q=${encodeURIComponent(q)}`)
    postVideoResults.value = Array.isArray(r) ? r : (r as any).videos || []
  } catch { postVideoResults.value = [] }
}

function pbVideoSelect(v: any) {
  postVideo.value = v.path || v.video || v.url || ''
  postPostId.value = v.post_id || v.id || ''
  postVideoLabel.value = v.label || v.handle || v.path || ''
  postVideoSearch.value = ''
  postVideoDropdownVisible.value = false
  postVideoResults.value = []
}

function pbVideoClear() {
  postVideo.value = ''
  postPostId.value = ''
  postVideoLabel.value = ''
}

/* ── Hashtag pill helpers ── */
function addHashtag(e?: KeyboardEvent) {
  const raw = postHashtagInput.value.trim().replace(/^#/, '')
  if (!raw) return
  if (e) e.preventDefault()
  const tags = raw.split(',').map(t => t.trim().replace(/^#/, '')).filter(Boolean)
  for (const tag of tags) {
    if (!postHashtags.value.includes(tag)) postHashtags.value.push(tag)
  }
  postHashtagInput.value = ''
}

function removeHashtag(tag: string) {
  postHashtags.value = postHashtags.value.filter(t => t !== tag)
}

/* ── Actions ── */
async function botStart() {
  const device = selectedDevice.value
  const account = selectedAccount.value.replace(/^@/, '') || undefined
  const payload: any = { job_type: activity.value, device, account }

  if (activity.value === 'post') {
    if (!postVideo.value.trim()) { alert('Укажите путь к видео'); return }
    Object.assign(payload, {
      video: postVideo.value.trim(),
      post_id: postPostId.value || undefined,
      hashtags: postHashtags.value.join(','),
      caption: postCaption.value.trim(),
      inject_tts: postInjectTts.value,
      action: postAction.value,
    })
  }

  try {
    const r = await api<any>('/api/bot/queue/add', {
      method: 'POST', body: JSON.stringify(payload),
    })
    if (r && r.ok) {
      pollStart()
      loadHistory()
    } else {
      alert((r && r.error) || 'Не удалось добавить задачу')
    }
  } catch (e: any) {
    alert('Ошибка: ' + e.message)
  }
}

async function botStop() {
  await api('/api/bot/stop', { method: 'POST' })
  pollStop()
  setTimeout(pollOnce, 800)
}

async function queueClear() {
  await api('/api/bot/queue/clear', { method: 'POST' })
  pollOnce()
}

async function removeJob(id: number) {
  await api(`/api/bot/queue/${id}`, { method: 'DELETE' })
  pollOnce()
}

function clearLog() {
  logSince = 0
  logLineCount.value = 0
  const el = document.getElementById('bot-log')
  if (el) el.innerHTML = '<span style="color:#374151">\u2014 очищено \u2014</span>'
}

/* ── History helpers ── */
const TYPE_BADGE: Record<string, string> = {
  post: '📹', publish_draft: '📤',
}

function phoneName(serial: string): string {
  if (!serial) return '?'
  const ph = devices.value.find(p => p.serial === serial)
  if (ph) return ph.nickname || ph.model || ph.label || serial.slice(0, 5)
  return serial.slice(0, 5)
}

function historyName(r: any): string {
  return r.video_name || r.name || `#${r.id}`
}

function historyDetail(r: any): string {
  return r.post_action || 'черновик'
}

function historyTime(r: any): string {
  return (r.started_at || '').slice(5, 16).replace('T', ' ')
}

function historyDuration(r: any): string {
  const endKey = r.ended_at || r.finished_at
  if (r.duration_s != null) {
    const s = r.duration_s
    return s < 60 ? `${s}с` : `${Math.floor(s / 60)}м${String(s % 60).padStart(2, '0')}с`
  }
  if (!endKey || !r.started_at) return '...'
  const s = Math.round((new Date(endKey).getTime() - new Date(r.started_at).getTime()) / 1000)
  return s < 60 ? `${s}с` : `${Math.floor(s / 60)}м${String(s % 60).padStart(2, '0')}с`
}

function historyStatusColor(r: any): string {
  const endKey = r.ended_at || r.finished_at
  if (!endKey) return '#fbbf24'
  if (r.exit_code === 0 || r.status === 'completed') return '#34d399'
  return '#f87171'
}

function historyStatusText(r: any): string {
  const endKey = r.ended_at || r.finished_at
  if (!endKey) return 'выполняется'
  if (r.exit_code === 0 || r.status === 'completed') return 'успешно'
  if (r.status === 'failed') return 'ошибка'
  if (r.status === 'stopped') return 'остановлено'
  return r.status || 'ошибка'
}

function historyStats(r: any): string {
  if (r.error_msg) return r.error_msg
  return ''
}

/* ── Queue helpers ── */
function queueLabel(j: any): string {
  const jt = j.job_type || 'post'
  if (jt === 'post') {
    const vname = (j.video || '').split('/').pop() || '?'
    return `📹 пост \u00b7 ${vname} \u00b7 ${j.action || 'черновик'}`
  }
  if (jt === 'publish_draft') return `📤 публикация черновика \u00b7 #${j.id}`
  return `🤖 #${j.run_id || j.id} \u00b7 ${jt}`
}

const QUEUE_DOT: Record<string, string> = {
  pending: '#64748b', running: '#22c55e', done: '#6366f1', stopped: '#f87171',
}

/* ── Lifecycle ── */
onMounted(async () => {
  await Promise.all([loadDevices(), loadAccounts(), loadHistory()])
  pollStart()
})
onUnmounted(() => { pollStop() })
</script>

<template>
  <div>
    <!-- 2-col: Settings | Status + Controls -->
    <div class="grid grid-cols-2 gap-4 mb-4">

      <!-- Left: Config (swaps based on activity) -->
      <div class="card" style="padding: 16px">

        <!-- Activity row -->
        <div class="bot-row" style="margin-bottom: 12px">
          <label class="bot-label" style="font-weight: 600; color: #94a3b8">Действие</label>
          <select v-model="activity" class="bot-select" style="flex: 1; max-width: 180px; font-weight: 600">
            <option value="post">📹 Пост</option>
            <option value="publish_draft">📤 Опубликовать черновик</option>
          </select>
        </div>

        <!-- ── Post settings ── -->
        <div v-show="activity === 'post'">
          <div class="section-title">Настройки загрузки</div>
          <div class="bot-row" style="align-items: flex-start">
            <label class="bot-label" style="padding-top: 6px">Видео</label>
            <div style="flex: 1; position: relative">
              <input v-model="postVideoSearch" type="text" placeholder="Поиск по handle или шаблону\u2026"
                autocomplete="off" class="bot-input" style="width: 100%; box-sizing: border-box; max-width: none"
                @input="pbVideoFilter(postVideoSearch)"
                @focus="postVideoDropdownVisible = true"
                @blur="hidePostVideoDropdownLater" />
              <div v-if="postVideoDropdownVisible && postVideoResults.length"
                style="position: absolute; top: 100%; left: 0; right: 0; z-index: 200;
                  background: #0f172a; border: 1px solid #1e293b; border-radius: 6px;
                  max-height: 220px; overflow-y: auto; margin-top: 3px; box-shadow: 0 8px 24px #0006">
                <div v-for="v in postVideoResults" :key="v.id || v.path"
                  style="padding: 8px 12px; cursor: pointer; font-size: 12px; color: #cbd5e1; border-bottom: 1px solid #1e293b"
                  @mousedown.prevent="pbVideoSelect(v)">
                  {{ v.label || v.handle || v.path || v.id }}
                </div>
              </div>
              <div v-if="postVideoLabel"
                style="margin-top: 6px; padding: 7px 10px; background: #0f172a; border: 1px solid #1e293b;
                  border-radius: 6px; font-size: 12px; color: #a78bfa; display: flex; align-items: center;
                  gap: 8px; cursor: pointer"
                @click="pbVideoClear">
                <span style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap">{{ postVideoLabel }}</span>
                <span style="color: #374151; font-size: 11px">&times; очистить</span>
              </div>
              <input v-model="postVideo" type="text" placeholder="/path/to/video.mp4" class="bot-input"
                style="width: 100%; box-sizing: border-box; max-width: none; margin-top: 6px" />
            </div>
          </div>
          <div class="bot-row" style="align-items: flex-start">
            <label class="bot-label" style="padding-top: 6px">Хэштеги</label>
            <div class="pb-hashtag-box"
              style="flex: 1; min-height: 36px; display: flex; flex-wrap: wrap; gap: 5px; align-items: center;
                background: #0f172a; border: 1px solid #1e293b; border-radius: 6px; padding: 5px 8px; cursor: text">
              <span v-for="tag in postHashtags" :key="tag"
                style="display: inline-flex; align-items: center; gap: 4px; background: #1e2d4a;
                  color: #93c5fd; border-radius: 4px; padding: 2px 7px; font-size: 12px">
                #{{ tag }}
                <span style="cursor: pointer; color: #475569; font-size: 14px" @click="removeHashtag(tag)">&times;</span>
              </span>
              <input v-model="postHashtagInput" type="text" placeholder="введите тег + Enter или ,"
                style="background: transparent; border: none; outline: none; color: #cbd5e1;
                  font-size: 13px; min-width: 120px; flex: 1; padding: 1px 0"
                @keydown.enter.prevent="addHashtag()" @keydown.,="addHashtag($event)" />
            </div>
          </div>
          <div class="bot-row">
            <label class="bot-label">Описание</label>
            <input v-model="postCaption" type="text" placeholder="Подписывайтесь, чтобы увидеть больше!" class="bot-input" style="flex: 1; max-width: none">
          </div>
          <div class="bot-row" style="align-items: center; gap: 8px; padding-left: 2px">
            <label style="display: flex; align-items: center; gap: 8px; cursor: pointer; font-weight: 400; color: #64748b; font-size: 12px">
              <input type="checkbox" v-model="postInjectTts" style="width: 13px; height: 13px; accent-color: #6366f1">
              Встроить TTS-аудио в видео (ttsvibes.com)
            </label>
            <span style="font-size: 11px; color: #374151">&mdash; выключено = TikTok popup TTS</span>
          </div>
          <div class="bot-row">
            <label class="bot-label">Действие</label>
            <select v-model="postAction" class="bot-select" style="flex: 1; max-width: none">
              <option value="draft">Сохранить как черновик</option>
              <option value="post">Опубликовать</option>
            </select>
          </div>
        </div>

      </div><!-- /left col -->

      <!-- Right: Status + Controls -->
      <div class="card" style="padding: 20px; display: flex; flex-direction: column; gap: 16px">

        <!-- Status indicator -->
        <div style="display: flex; align-items: center; gap: 12px">
          <div :style="{
            width: '12px', height: '12px', borderRadius: '50%', flexShrink: 0,
            background: botStatusDot, transition: 'background 0.3s',
            boxShadow: botStatusGlow ? '0 0 8px ' + botStatusDot + '88' : 'none',
          }"></div>
          <div>
            <div style="font-size: 14px; font-weight: 600; color: white">{{ botStatusLabel }}</div>
            <div style="font-size: 11px; color: #64748b; margin-top: 2px">{{ botStatusSub }}</div>
          </div>
        </div>

        <div class="divider" style="margin: 0"></div>

        <!-- Start / Stop -->
        <div style="display: flex; flex-direction: column; gap: 8px">
          <button v-if="!botRunning" class="btn btn-primary" style="width: 100%; justify-content: center; display: flex; align-items: center; gap: 6px" @click="botStart">
            {{ startButtonLabel }}
          </button>
          <button v-else style="width: 100%; justify-content: center; display: flex; align-items: center; gap: 6px;
            background: #7f1d1d; color: #fca5a5; border: none; padding: 6px 14px; border-radius: 6px;
            font-size: 13px; font-weight: 600; cursor: pointer" @click="botStop">
            &#9632; Стоп
          </button>
        </div>

        <div class="divider" style="margin: 0"></div>

        <!-- Device selector -->
        <div class="bot-row">
          <label class="bot-label">Устройство</label>
          <select v-model="selectedDevice" class="bot-select" style="flex: 1">
            <option v-for="d in devices" :key="d.serial" :value="d.serial">{{ (d.nickname || d.model || d.label || d.serial) + ' (' + d.serial.slice(0, 4) + '\u2026)' }}</option>
          </select>
        </div>

        <!-- Account selector -->
        <div class="bot-row">
          <label class="bot-label">Аккаунт</label>
          <select v-model="selectedAccount" class="bot-select" style="flex: 1; font-size: 12px">
            <option value="">авто-определение</option>
            <option v-for="a in accounts" :key="a.handle" :value="a.handle">@{{ a.handle }}</option>
          </select>
        </div>

      </div><!-- /right col -->
    </div><!-- /2-col grid -->

    <!-- Queue panel -->
    <div class="card" style="padding: 0; overflow: hidden; margin-bottom: 16px">
      <div style="display: flex; align-items: center; justify-content: space-between; padding: 10px 16px; border-bottom: 1px solid #1e293b">
        <div style="font-size: 13px; font-weight: 600; color: #cbd5e1">
          Очередь
          <span v-if="queueJobs.length" style="font-size: 11px; color: #64748b; font-weight: normal; margin-left: 4px">({{ queueJobs.length }})</span>
        </div>
        <button @click="queueClear" style="font-size: 11px; color: #475569; background: none; border: none; cursor: pointer; padding: 0"
          onmouseover="this.style.color='#94a3b8'" onmouseout="this.style.color='#475569'">Очистить ожидание</button>
      </div>
      <div style="min-height: 38px; padding: 6px 0">
        <div v-if="!queueJobs.length" style="font-size: 11px; color: #475569; padding: 8px 16px">&mdash; очередь пуста &mdash;</div>
        <div v-for="j in queueJobs" :key="j.id"
          style="display: flex; align-items: center; gap: 8px; padding: 5px 16px; border-bottom: 1px solid #1e293b; font-size: 11px; color: #94a3b8">
          <span style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap" :title="queueLabel(j)">
            {{ queueLabel(j) }}
            <span v-if="j.profiles_added != null" style="color: #6366f1; margin-left: 6px">+{{ j.profiles_added }} новых</span>
          </span>
          <span style="white-space: nowrap; display: flex; align-items: center">
            <span :style="{ display: 'inline-block', width: '7px', height: '7px', borderRadius: '50%', background: QUEUE_DOT[j.status] || '#374151', marginRight: '4px', verticalAlign: 'middle', flexShrink: 0 }"></span>
            {{ j.status }}
          </span>
          <button v-if="j.status === 'running'" @click="botStop"
            style="color: #f87171; background: none; border: none; cursor: pointer; font-size: 11px; padding: 0 2px" title="Остановить задачу">&times;</button>
          <button v-else @click="removeJob(j.id)"
            style="color: #475569; background: none; border: none; cursor: pointer; font-size: 11px; padding: 0 2px" title="Удалить">&times;</button>
        </div>
      </div>
    </div>

    <!-- Log viewer -->
    <div class="card" style="padding: 0; overflow: hidden">
      <div style="display: flex; align-items: center; justify-content: space-between; padding: 10px 16px; border-bottom: 1px solid #1e293b">
        <div style="font-size: 13px; font-weight: 600; color: #cbd5e1">Логи</div>
        <div style="display: flex; align-items: center; gap: 12px">
          <label style="display: flex; align-items: center; gap: 6px; font-size: 11px; color: #64748b; cursor: pointer">
            <input type="checkbox" v-model="autoScroll" style="width: 12px; height: 12px; accent-color: #6366f1; border: none; padding: 0">
            Автопрокрутка
          </label>
          <button @click="clearLog" style="font-size: 11px; color: #475569; background: none; border: none; cursor: pointer; padding: 0"
            onmouseover="this.style.color='#94a3b8'" onmouseout="this.style.color='#475569'">Очистить</button>
        </div>
      </div>
      <div id="bot-log"
        style="font-family: monospace; font-size: 12px; line-height: 1.6; color: #94a3b8;
          background: #080b10; padding: 14px 16px; height: 360px; overflow-y: auto;
          white-space: pre-wrap; word-break: break-all">
        <span style="color: #374151">&mdash; логов пока нет &mdash;</span>
      </div>
    </div>

    <!-- Run History (table) -->
    <div class="card" style="padding: 0; overflow: hidden; margin-top: 16px">
      <div style="display: flex; align-items: center; justify-content: space-between; padding: 10px 16px; border-bottom: 1px solid #1e293b">
        <div style="font-size: 13px; font-weight: 600; color: #cbd5e1">История запусков</div>
        <button @click="loadHistory" style="font-size: 11px; color: #475569; background: none; border: none; cursor: pointer; padding: 0"
          onmouseover="this.style.color='#94a3b8'" onmouseout="this.style.color='#475569'">Обновить</button>
      </div>
      <div style="min-height: 50px; max-height: 320px; overflow-y: auto">
        <div v-if="!history.length" style="font-size: 11px; color: #475569; padding: 12px 16px">&mdash; запусков пока нет &mdash;</div>
        <div v-else style="overflow-x: auto">
          <table style="width: 100%; border-collapse: collapse; font-size: 11px">
            <thead>
              <tr style="border-bottom: 1px solid #1e2438">
                <th class="hist-th" style="text-align: center">Тип</th>
                <th class="hist-th" style="text-align: left">Название</th>
                <th class="hist-th" style="text-align: left">Детали</th>
                <th class="hist-th" style="text-align: left">Телефон</th>
                <th class="hist-th" style="text-align: center">Триггер</th>
                <th class="hist-th" style="text-align: left">Старт</th>
                <th class="hist-th" style="text-align: left">Длительность</th>
                <th class="hist-th" style="text-align: left">Статус</th>
                <th class="hist-th" style="text-align: left">Сводка</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in history" :key="r.id" class="hist-row">
                <td style="padding: 5px 8px; text-align: center">{{ TYPE_BADGE[r.job_type] || r.job_type }}</td>
                <td style="padding: 5px 8px; color: #a5b4fc">{{ historyName(r) }}</td>
                <td style="padding: 5px 8px; color: #64748b">{{ historyDetail(r) }}</td>
                <td style="padding: 5px 8px; color: #94a3b8">{{ phoneName(r.phone_serial || r.device_serial || '') }}</td>
                <td style="padding: 5px 8px; text-align: center">
                  <span v-if="r.trigger === 'manual'" style="color: #f59e0b; font-size: 10px">вручную</span>
                  <span v-else style="color: #64748b; font-size: 10px">план</span>
                </td>
                <td style="padding: 5px 8px; color: #64748b; font-family: monospace">{{ historyTime(r) }}</td>
                <td style="padding: 5px 8px; color: #64748b">{{ historyDuration(r) }}</td>
                <td style="padding: 5px 8px">
                  <span :style="{ color: historyStatusColor(r) }">{{ historyStatusText(r) }}</span>
                </td>
                <td style="padding: 5px 8px">
                  <span v-if="historyStats(r)" style="color: #34d399">{{ historyStats(r) }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.bot-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}
.bot-label {
  font-size: 11px;
  color: #64748b;
  width: 100px;
  flex-shrink: 0;
}
.bot-select,
.bot-input {
  flex: 1;
  padding: 5px 8px;
  font-size: 12px;
  background: var(--bg-deep);
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--text-1);
}
.bot-input-num {
  max-width: 80px;
  flex: none;
  padding: 5px 8px;
  font-size: 12px;
  background: var(--bg-deep);
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--text-1);
}
.section-title {
  font-size: 11px;
  font-weight: 600;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 12px;
}
.divider {
  height: 1px;
  background: #1e293b;
  margin: 8px 0;
}
.ob-label-box {
  flex: 1;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  background: #0f1117;
  border: 1px solid #2a3044;
  border-radius: 8px;
  padding: 7px 10px;
  min-height: 32px;
  max-height: 90px;
  overflow-y: auto;
}
.ob-label-item {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: #93c5fd;
  cursor: pointer;
}
.ob-preview {
  font-size: 12px;
  color: #94a3b8;
  background: #070a0f;
  border: 1px solid #1e293b;
  border-radius: 8px;
  padding: 10px 12px;
  white-space: pre-wrap;
  line-height: 1.6;
  max-height: 110px;
  overflow-y: auto;
}
.hist-th {
  padding: 4px 8px;
  font-size: 10px;
  color: #475569;
  font-weight: 600;
  text-transform: uppercase;
}
.hist-row {
  border-bottom: 1px solid #1e2438;
}
.hist-row:hover {
  background: #0f1523;
}
</style>
