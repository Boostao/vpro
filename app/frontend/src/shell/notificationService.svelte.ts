import { writable } from 'svelte/store';

type NotificationSeverity = 'info' | 'success' | 'warning' | 'error';
export type NotificationCategory = 'general' | 'entry' | 'lmh25' | 'reports' | 'admin' | 'background';
export type NotificationFilter = 'all' | 'errors' | 'entry' | 'lmh25' | 'reports' | 'background';

interface NotificationAction {
  label: string;
  onTrigger: () => void;
}

interface NotificationEntry {
  id: string;
  severity: NotificationSeverity;
  category: NotificationCategory;
  title: string;
  message: string;
  source?: string;
  contextTag?: string;
  action?: NotificationAction;
  timestampIso: string;
  createdAtMs: number;
  read: boolean;
  repeatCount: number;
}

interface ActiveToast {
  id: string;
  entryId: string;
  severity: NotificationSeverity;
  title: string;
  message: string;
  contextTag?: string;
  action?: NotificationAction;
  repeatCount: number;
  durationMs: number;
  remainingMs: number;
  startedAtMs: number;
  paused: boolean;
}

export interface NotificationStateSnapshot {
  entries: NotificationEntry[];
  toasts: ActiveToast[];
  unreadCount: number;
  unreadErrorCount: number;
  unreadWarningCount: number;
  badgeSeverity: 'error' | 'warning' | 'info' | 'none';
}

interface PushNotificationInput {
  severity: NotificationSeverity;
  category?: NotificationCategory;
  title: string;
  message?: string;
  source?: string;
  contextTag?: string;
  action?: NotificationAction;
  toast?: boolean;
  durationMs?: number;
}

const DEFAULT_TOAST_DURATION_MS = 4500;
const DEDUPE_WINDOW_MS = 2500;
const MAX_HISTORY_ENTRIES = 150;
const MAX_VISIBLE_TOASTS = 4;

function computeUnreadSummary(entries: readonly NotificationEntry[]) {
  let unreadCount = 0;
  let unreadErrorCount = 0;
  let unreadWarningCount = 0;
  for (const item of entries) {
    if (!item.read) {
      unreadCount++;
      if (item.severity === 'error') unreadErrorCount++;
      else if (item.severity === 'warning') unreadWarningCount++;
    }
  }
  const badgeSeverity: NotificationStateSnapshot['badgeSeverity'] =
    unreadErrorCount > 0 ? 'error'
    : unreadWarningCount > 0 ? 'warning'
    : unreadCount > 0 ? 'info'
    : 'none';
  return { unreadCount, unreadErrorCount, unreadWarningCount, badgeSeverity };
}

export function filterNotificationEntries(
  entries: readonly NotificationEntry[],
  filter: NotificationFilter,
): NotificationEntry[] {
  if (filter === 'errors') {
    return entries.filter((item) => item.severity === 'error');
  }
  if (filter === 'entry') {
    return entries.filter((item) => item.category === 'entry');
  }
  if (filter === 'lmh25') {
    return entries.filter((item) => item.category === 'lmh25' || (item.severity === 'warning' && item.category === 'general'));
  }
  if (filter === 'reports') {
    return entries.filter((item) => item.category === 'reports');
  }
  if (filter === 'background') {
    return entries.filter((item) => item.category === 'background' || item.category === 'admin');
  }
  return [...entries];
}

export function createNotificationController(options: {
  now?: () => number;
  schedule?: (fn: () => void, ms: number) => ReturnType<typeof setTimeout>;
  cancelSchedule?: (handle: ReturnType<typeof setTimeout>) => void;
} = {}) {
  const now = options.now ?? (() => Date.now());
  const schedule = options.schedule ?? ((fn, ms) => setTimeout(fn, ms));
  const cancelSchedule = options.cancelSchedule ?? ((h) => clearTimeout(h));

  let seq = 0;
  let entries: NotificationEntry[] = [];
  let toasts: ActiveToast[] = [];
  const timers = new Map<string, ReturnType<typeof setTimeout>>();

  function snapshot(): NotificationStateSnapshot {
    return {
      entries: [...entries],
      toasts: [...toasts],
      ...computeUnreadSummary(entries),
    };
  }

  const store = writable<NotificationStateSnapshot>(snapshot());

  function emit() {
    store.set(snapshot());
  }

  function clearTimer(toastId: string) {
    const existing = timers.get(toastId);
    if (existing !== undefined) {
      cancelSchedule(existing);
      timers.delete(toastId);
    }
  }

  function armTimer(toastId: string, ms: number) {
    clearTimer(toastId);
    if (ms <= 0) {
      dismissToast(toastId);
      return;
    }
    const handle = schedule(() => {
      timers.delete(toastId);
      dismissToast(toastId);
    }, ms);
    timers.set(toastId, handle);
  }

  function dismissToast(toastId: string) {
    clearTimer(toastId);
    const next = toasts.filter((t) => t.id !== toastId);
    if (next.length !== toasts.length) {
      toasts = next;
      emit();
    }
  }

  function pauseToast(toastId: string) {
    const idx = toasts.findIndex((t) => t.id === toastId);
    if (idx === -1 || toasts[idx].paused) return;
    clearTimer(toastId);
    const current = toasts[idx];
    const elapsed = Math.max(0, now() - current.startedAtMs);
    const remainingMs = Math.max(400, current.remainingMs - elapsed);
    toasts = toasts.map((t, i) => (i === idx ? { ...t, paused: true, remainingMs } : t));
    emit();
  }

  function resumeToast(toastId: string) {
    const idx = toasts.findIndex((t) => t.id === toastId);
    if (idx === -1 || !toasts[idx].paused) return;
    const current = toasts[idx];
    const startedAtMs = now();
    toasts = toasts.map((t, i) => (i === idx ? { ...t, paused: false, startedAtMs } : t));
    armTimer(toastId, current.remainingMs);
    emit();
  }

  function push(input: PushNotificationInput): NotificationEntry {
    const ts = now();
    const cleanTitle = String(input.title ?? '').trim() || 'Notification';
    const cleanMsg = String(input.message ?? '').trim();
    const cleanContextTag =
      input.contextTag === undefined ? undefined : (String(input.contextTag).trim() || undefined);
    const category: NotificationCategory = input.category ?? 'general';
    const showToast = input.toast ?? (input.severity === 'success' || input.severity === 'info' || input.severity === 'error');
    const durationMs = input.durationMs ?? DEFAULT_TOAST_DURATION_MS;

    const recentIdx = entries.findIndex(
      (item) =>
        item.severity === input.severity &&
        item.category === category &&
        item.title === cleanTitle &&
        item.message === cleanMsg &&
        (!item.contextTag || !cleanContextTag || item.contextTag === cleanContextTag) &&
        ts - item.createdAtMs <= DEDUPE_WINDOW_MS,
    );

    if (recentIdx !== -1) {
      const existing = entries[recentIdx];
      const updated: NotificationEntry = {
        ...existing,
        source: input.source ?? existing.source,
        contextTag: cleanContextTag ?? existing.contextTag,
        action: input.action ?? existing.action,
        createdAtMs: ts,
        timestampIso: new Date(ts).toISOString(),
        repeatCount: existing.repeatCount + 1,
        read: false,
      };
      entries = [updated, ...entries.filter((_, idx) => idx !== recentIdx)];

      if (showToast) {
        const toastIdx = toasts.findIndex((t) => t.entryId === existing.id);
        if (toastIdx !== -1) {
          const prevToast = toasts[toastIdx];
          const refreshed: ActiveToast = {
            ...prevToast,
            contextTag: updated.contextTag,
            action: updated.action,
            repeatCount: updated.repeatCount,
            remainingMs: durationMs,
            startedAtMs: ts,
          };
          toasts = toasts.map((t, idx) => (idx === toastIdx ? refreshed : t));
          if (!refreshed.paused) armTimer(refreshed.id, durationMs);
        } else {
          const toastId = `toast-${++seq}`;
          const createdToast: ActiveToast = {
            id: toastId,
            entryId: updated.id,
            severity: updated.severity,
            title: updated.title,
            message: updated.message,
            contextTag: updated.contextTag,
            action: updated.action,
            repeatCount: updated.repeatCount,
            durationMs,
            remainingMs: durationMs,
            startedAtMs: ts,
            paused: false,
          };
          toasts = [...toasts.slice(-(MAX_VISIBLE_TOASTS - 1)), createdToast];
          armTimer(toastId, durationMs);
        }
      }
      emit();
      return updated;
    }

    const entry: NotificationEntry = {
      id: `notif-${++seq}`,
      severity: input.severity,
      category,
      title: cleanTitle,
      message: cleanMsg,
      source: input.source,
      contextTag: cleanContextTag,
      action: input.action,
      timestampIso: new Date(ts).toISOString(),
      createdAtMs: ts,
      read: input.severity === 'success' && category === 'general',
      repeatCount: 1,
    };
    entries = [entry, ...entries].slice(0, MAX_HISTORY_ENTRIES);

    if (showToast) {
      if (toasts.length >= MAX_VISIBLE_TOASTS) {
        const evicted = toasts[0];
        clearTimer(evicted.id);
        toasts = toasts.slice(1);
      }
      const toastId = `toast-${++seq}`;
      const toastItem: ActiveToast = {
        id: toastId,
        entryId: entry.id,
        severity: entry.severity,
        title: entry.title,
        message: entry.message,
        contextTag: entry.contextTag,
        action: entry.action,
        repeatCount: 1,
        durationMs,
        remainingMs: durationMs,
        startedAtMs: ts,
        paused: false,
      };
      toasts = [...toasts, toastItem];
      armTimer(toastId, durationMs);
    }

    emit();
    return entry;
  }

  function markRead(entryId: string) {
    let changed = false;
    entries = entries.map((item) => {
      if (item.id === entryId && !item.read) {
        changed = true;
        return { ...item, read: true };
      }
      return item;
    });
    if (changed) emit();
  }

  function markAllRead() {
    let changed = false;
    entries = entries.map((item) => {
      if (!item.read) {
        changed = true;
        return { ...item, read: true };
      }
      return item;
    });
    if (changed) emit();
  }

  function triggerAction(entryId: string): boolean {
    const entry = entries.find((item) => item.id === entryId);
    let changed = false;
    entries = entries.map((item) => {
      if (item.id === entryId && !item.read) {
        changed = true;
        return { ...item, read: true };
      }
      return item;
    });
    const nextToasts = toasts.filter((t) => {
      if (t.entryId === entryId) {
        clearTimer(t.id);
        changed = true;
        return false;
      }
      return true;
    });
    if (nextToasts.length !== toasts.length) {
      toasts = nextToasts;
    }
    if (changed || Boolean(entry?.action)) emit();
    entry?.action?.onTrigger?.();
    return Boolean(entry?.action);
  }

  function clearHistory() {
    for (const id of timers.keys()) clearTimer(id);
    entries = [];
    toasts = [];
    emit();
  }

  return {
    subscribe: store.subscribe,
    getSnapshot: snapshot,
    push,
    dismissToast,
    pauseToast,
    resumeToast,
    markRead,
    markAllRead,
    triggerAction,
    clearHistory,
    success: (title: string, message = '', opts: Partial<PushNotificationInput> = {}) =>
      push({ ...opts, severity: 'success', title, message, toast: opts.toast ?? true }),
    info: (title: string, message = '', opts: Partial<PushNotificationInput> = {}) =>
      push({ ...opts, severity: 'info', title, message, toast: opts.toast ?? true }),
    warning: (title: string, message = '', opts: Partial<PushNotificationInput> = {}) =>
      push({ ...opts, severity: 'warning', title, message, toast: opts.toast ?? false }),
    error: (title: string, message = '', opts: Partial<PushNotificationInput> = {}) =>
      push({ ...opts, severity: 'error', title, message, toast: opts.toast ?? true }),
  };
}

export const notifications = createNotificationController();
