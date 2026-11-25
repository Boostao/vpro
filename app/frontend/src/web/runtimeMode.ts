declare const __VPRO_WEB_READONLY__: boolean | undefined;

export const WEB_SESSION_HEADER = 'X-VPro-Session';

const SESSION_STORAGE_KEY = 'vpro:web-session-id';

let fallbackSessionId = '';

export const IS_WEB_READONLY: boolean = typeof __VPRO_WEB_READONLY__ !== 'undefined' && __VPRO_WEB_READONLY__ === true;

export function isWebReadOnly(): boolean {
  return IS_WEB_READONLY;
}

export function getRuntimeMode(): 'web-readonly' | 'desktop' {
  return isWebReadOnly() ? 'web-readonly' : 'desktop';
}

function generateSessionId(): string {
  if (typeof globalThis.crypto !== 'undefined' && typeof globalThis.crypto.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  if (typeof globalThis.crypto !== 'undefined' && typeof globalThis.crypto.getRandomValues === 'function') {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < bytes.length; i += 1) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
  }
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function getWebSessionId(): string {
  try {
    if (typeof globalThis.sessionStorage !== 'undefined') {
      const existing = globalThis.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (existing && existing.trim().length > 0) {
        return existing;
      }
      const created = generateSessionId();
      globalThis.sessionStorage.setItem(SESSION_STORAGE_KEY, created);
      return created;
    }
  } catch {
    // Restricted storage contexts fall back to an in-memory per-page session ID.
  }
  if (!fallbackSessionId) {
    fallbackSessionId = generateSessionId();
  }
  return fallbackSessionId;
}
