import { WEB_RPC_BY_ID, WEB_RPC_BY_NAME, type WebRpcEntry } from './generatedRpcMap';
import { getWebSessionId, WEB_SESSION_HEADER } from './runtimeMode';

export class RuntimeError extends Error {
  constructor(message?: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'RuntimeError';
  }
}

export class CancelError extends Error {
  constructor(message?: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'CancelError';
  }
}

function errorMessage(value: unknown): string {
  if (value instanceof Error) {
    return value.message || value.name || 'Unexpected error';
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }
  if (
    value !== null &&
    typeof value === 'object' &&
    'message' in value &&
    typeof (value as { message?: unknown }).message === 'string'
  ) {
    const msg = (value as { message: string }).message.trim();
    if (msg.length > 0) return msg;
  }
  return 'Unexpected error';
}

export class CancelledRejectionError extends Error {
  readonly promise: unknown;

  constructor(promise: unknown, reason: unknown, info?: string) {
    super(`${info ?? 'Unhandled rejection in cancelled promise.'} Reason: ${errorMessage(reason)}`, {
      cause: reason,
    });
    this.promise = promise;
    this.name = 'CancelledRejectionError';
  }
}

export interface CancellablePromiseWithResolvers<T> {
  promise: CancellablePromise<T>;
  resolve: (value: T | PromiseLike<T>) => void;
  reject: (reason?: unknown) => void;
  oncancelled: ((cause?: unknown) => void | PromiseLike<void>) | null;
}

export class CancellablePromise<T> extends Promise<T> {
  static get [Symbol.species](): PromiseConstructor {
    return Promise;
  }

  private readonly _cancelImpl: (cause?: unknown) => Promise<void>;

  constructor(
    executor: (resolve: (value: T | PromiseLike<T>) => void, reject: (reason?: unknown) => void) => void,
    oncancelled?: (cause?: unknown) => void | PromiseLike<void>
  ) {
    let rawResolve!: (value: T | PromiseLike<T>) => void;
    let rawReject!: (reason?: unknown) => void;
    super((res, rej) => {
      rawResolve = res;
      rawReject = rej;
    });

    let settled = false;
    let cancelled = false;
    let cancelHandler = oncancelled ?? null;

    const safeResolve = (value: T | PromiseLike<T>): void => {
      if (settled || cancelled) return;
      settled = true;
      rawResolve(value);
    };

    const safeReject = (reason?: unknown): void => {
      if (settled || cancelled) return;
      settled = true;
      rawReject(reason);
    };

    this._cancelImpl = (cause?: unknown): Promise<void> => {
      if (settled || cancelled) {
        return Promise.resolve();
      }
      cancelled = true;
      settled = true;
      rawReject(new CancelError('The operation was cancelled', cause !== undefined ? { cause } : undefined));
      if (cancelHandler) {
        try {
          return Promise.resolve(cancelHandler(cause)).then(() => undefined);
        } catch {
          return Promise.resolve();
        }
      }
      return Promise.resolve();
    };

    try {
      executor(safeResolve, safeReject);
    } catch (err) {
      safeReject(err);
    }
  }

  cancel(cause?: unknown): Promise<void> {
    return this._cancelImpl(cause);
  }

  static override resolve(): CancellablePromise<void>;
  static override resolve<U>(value: U | PromiseLike<U>): CancellablePromise<Awaited<U>>;
  static override resolve<U = void>(value?: U | PromiseLike<U>): CancellablePromise<Awaited<U>> {
    return new CancellablePromise<Awaited<U>>((resolve) => {
      resolve(value as Awaited<U> | PromiseLike<Awaited<U>>);
    });
  }

  static override reject<U = never>(reason?: unknown): CancellablePromise<U> {
    return new CancellablePromise<U>((_resolve, reject) => {
      reject(reason);
    });
  }

  static withResolvers<U>(): CancellablePromiseWithResolvers<U> {
    let resolve!: (value: U | PromiseLike<U>) => void;
    let reject!: (reason?: unknown) => void;
    const holder: CancellablePromiseWithResolvers<U> = {
      promise: undefined as unknown as CancellablePromise<U>,
      resolve: undefined as unknown as (value: U | PromiseLike<U>) => void,
      reject: undefined as unknown as (reason?: unknown) => void,
      oncancelled: null,
    };
    const promise = new CancellablePromise<U>(
      (res, rej) => {
        resolve = res;
        reject = rej;
      },
      (cause) => holder.oncancelled?.(cause)
    );
    holder.promise = promise;
    holder.resolve = resolve;
    holder.reject = reject;
    return holder;
  }
}

function isSafeDownloadUrl(rawUrl: string): boolean {
  const trimmed = rawUrl.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    return true;
  }
  if (trimmed.startsWith('blob:')) {
    return true;
  }
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return false;
    }
    if (typeof globalThis.window !== 'undefined' && globalThis.window.location?.origin) {
      return parsed.origin === globalThis.window.location.origin;
    }
    return false;
  } catch {
    return false;
  }
}

export function triggerBrowserDownload(downloadUrl: string, filename?: string): boolean {
  if (typeof downloadUrl !== 'string' || !isSafeDownloadUrl(downloadUrl)) {
    return false;
  }
  const doc = globalThis.document;
  if (!doc || typeof doc.createElement !== 'function') {
    return false;
  }
  const anchor = doc.createElement('a');
  anchor.href = downloadUrl;
  anchor.rel = 'noopener';
  if (typeof filename === 'string' && filename.trim().length > 0) {
    anchor.download = filename.trim();
  }
  if (anchor.style) {
    anchor.style.display = 'none';
  }
  const parent = doc.body ?? doc.documentElement;
  if (parent && typeof parent.appendChild === 'function') {
    parent.appendChild(anchor);
  }
  try {
    anchor.click();
  } finally {
    if (typeof anchor.remove === 'function') {
      anchor.remove();
    } else if (parent && typeof parent.removeChild === 'function') {
      parent.removeChild(anchor);
    }
  }
  return true;
}

function normalizeMethodName(methodName: string): string {
  const trimmed = String(methodName ?? '').trim();
  if (!trimmed) return '';
  if (Object.hasOwn(WEB_RPC_BY_NAME, trimmed)) {
    return trimmed;
  }
  // Support Wails fully-qualified names such as "main.PictureService.GetPictureOptions"
  // or "github.com/boostao/vpro/app.PictureService.GetPictureOptions".
  const parts = trimmed.split('.');
  if (parts.length >= 2) {
    const shortName = `${parts[parts.length - 2]}.${parts[parts.length - 1]}`;
    if (Object.hasOwn(WEB_RPC_BY_NAME, shortName)) {
      return shortName;
    }
  }
  return trimmed;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function unwrapSingleResultEnvelope(value: unknown): unknown {
  if (isPlainObject(value)) {
    const keys = Object.keys(value);
    if (keys.length === 1 && keys[0] === 'result') {
      return value.result;
    }
  }
  return value;
}

function isAbortError(cause: unknown): boolean {
  if (!cause || typeof cause !== 'object') return false;
  const name = 'name' in cause ? (cause as { name?: unknown }).name : undefined;
  return name === 'AbortError';
}

function extractErrorMessage(bodyText: string, status: number, statusText: string): string {
  const trimmed = bodyText.trim();
  if (trimmed) {
    try {
      const parsed = JSON.parse(trimmed) as unknown;
      if (isPlainObject(parsed)) {
        if (typeof parsed.error === 'string' && parsed.error.trim()) {
          return parsed.error.trim();
        }
        if (typeof parsed.message === 'string' && parsed.message.trim()) {
          return parsed.message.trim();
        }
      } else if (typeof parsed === 'string' && parsed.trim()) {
        return parsed.trim();
      }
    } catch {
      return trimmed;
    }
  }
  return statusText ? `HTTP ${status} ${statusText}` : `HTTP ${status}`;
}

function invokeAllowedRpc<T = unknown>(entry: WebRpcEntry, args: unknown[]): CancellablePromise<T> {
  const controller = new AbortController();
  const url = `/api/rpc/${encodeURIComponent(entry.service)}/${encodeURIComponent(entry.method)}`;

  return new CancellablePromise<T>(
    (resolve, reject) => {
      globalThis
        .fetch(url, {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            [WEB_SESSION_HEADER]: getWebSessionId(),
          },
          body: JSON.stringify({ args }),
        })
        .then(async (response) => {
          const text = await response.text();
          if (!response.ok) {
            reject(new RuntimeError(extractErrorMessage(text, response.status, response.statusText)));
            return;
          }
          if (response.status === 204 || text.trim().length === 0) {
            resolve(undefined as T);
            return;
          }
          let parsed: unknown;
          try {
            parsed = JSON.parse(text);
          } catch (parseErr) {
            reject(
              new RuntimeError(`Invalid JSON response from ${entry.service}.${entry.method}: ${errorMessage(parseErr)}`)
            );
            return;
          }
          const payload = unwrapSingleResultEnvelope(parsed);
          if (
            entry.kind === 'download' &&
            isPlainObject(payload) &&
            typeof payload.downloadUrl === 'string' &&
            payload.downloadUrl.trim().length > 0
          ) {
            const filename = typeof payload.filename === 'string' ? payload.filename : undefined;
            triggerBrowserDownload(payload.downloadUrl, filename);
            resolve(('outcome' in payload ? payload.outcome : payload) as T);
            return;
          }
          resolve(payload as T);
        })
        .catch((err) => {
          if (controller.signal.aborted || isAbortError(err)) {
            reject(new RuntimeError('context canceled', { cause: err }));
            return;
          }
          if (err instanceof RuntimeError) {
            reject(err);
            return;
          }
          reject(new RuntimeError(errorMessage(err), { cause: err }));
        });
    },
    () => {
      controller.abort();
    }
  );
}

export type CallOptions =
  { methodID: number; methodName?: never; args: unknown[] } | { methodID?: never; methodName: string; args: unknown[] };

function callById<T = unknown>(methodID: number, ...args: unknown[]): CancellablePromise<T> {
  const entry = Object.hasOwn(WEB_RPC_BY_ID, methodID) ? WEB_RPC_BY_ID[methodID] : undefined;
  if (!entry) {
    return CancellablePromise.reject<T>(
      new RuntimeError(`Operation is unavailable in VPro web read-only mode (RPC ID ${methodID}).`)
    );
  }
  return invokeAllowedRpc<T>(entry, args);
}

function callByName<T = unknown>(methodName: string, ...args: unknown[]): CancellablePromise<T> {
  const normalized = normalizeMethodName(methodName);
  const entry = Object.hasOwn(WEB_RPC_BY_NAME, normalized) ? WEB_RPC_BY_NAME[normalized] : undefined;
  if (!entry) {
    return CancellablePromise.reject<T>(
      new RuntimeError(`Operation "${methodName}" is unavailable in VPro web read-only mode.`)
    );
  }
  return invokeAllowedRpc<T>(entry, args);
}

function callWithOptions<T = unknown>(options: CallOptions): CancellablePromise<T> {
  if (typeof options.methodID === 'number') {
    return callById<T>(options.methodID, ...(options.args ?? []));
  }
  return callByName<T>(options.methodName ?? '', ...(options.args ?? []));
}

export const Call = {
  ByID: callById,
  ByName: callByName,
  Call: callWithOptions,
  RuntimeError,
};

export interface OpenFileDialogOptions {
  AllowsMultipleSelection?: boolean;
  [key: string]: unknown;
}

export interface SaveFileDialogOptions {
  Filename?: string;
  [key: string]: unknown;
}

export interface MessageDialogOptions {
  Title?: string;
  Message?: string;
  [key: string]: unknown;
}

export const Dialogs = {
  OpenFile(options?: OpenFileDialogOptions): Promise<string | string[]> {
    return Promise.resolve(options?.AllowsMultipleSelection ? [] : '');
  },
  SaveFile(_options?: SaveFileDialogOptions): Promise<string> {
    return Promise.resolve('');
  },
  Info(_options?: MessageDialogOptions): Promise<string> {
    return Promise.resolve('');
  },
  Warning(_options?: MessageDialogOptions): Promise<string> {
    return Promise.resolve('');
  },
  Error(_options?: MessageDialogOptions): Promise<string> {
    return Promise.resolve('');
  },
  Question(_options?: MessageDialogOptions): Promise<string> {
    return Promise.resolve('');
  },
};

export class WailsEvent<T = unknown> {
  name: string;
  data: T;
  sender?: string;

  constructor(name: string, data?: T) {
    this.name = name;
    this.data = data as T;
  }
}

export type WailsEventCallback<T = unknown> = (ev: WailsEvent<T>) => void;

const eventTarget = new EventTarget();
const registeredListeners = new Map<string, Set<EventListener>>();

function onMultiple<T = unknown>(eventName: string, callback: WailsEventCallback<T>, maxCallbacks: number): () => void {
  let remaining = maxCallbacks;
  let active = true;

  const listener: EventListener = (rawEvent) => {
    if (!active) return;
    const detail = rawEvent instanceof CustomEvent ? (rawEvent.detail as WailsEvent<T>) : new WailsEvent<T>(eventName);
    if (remaining > 0) {
      remaining -= 1;
      if (remaining === 0) {
        unsubscribe();
      }
    }
    callback(detail);
  };

  const unsubscribe = (): void => {
    if (!active) return;
    active = false;
    eventTarget.removeEventListener(eventName, listener);
    const set = registeredListeners.get(eventName);
    if (set) {
      set.delete(listener);
      if (set.size === 0) {
        registeredListeners.delete(eventName);
      }
    }
  };

  let set = registeredListeners.get(eventName);
  if (!set) {
    set = new Set<EventListener>();
    registeredListeners.set(eventName, set);
  }
  set.add(listener);
  eventTarget.addEventListener(eventName, listener);
  return unsubscribe;
}

export const Events = {
  WailsEvent,
  OnMultiple: onMultiple,
  On<T = unknown>(eventName: string, callback: WailsEventCallback<T>): () => void {
    return onMultiple(eventName, callback, -1);
  },
  Once<T = unknown>(eventName: string, callback: WailsEventCallback<T>): () => void {
    return onMultiple(eventName, callback, 1);
  },
  Off(...eventNames: string[]): void {
    for (const eventName of eventNames) {
      const set = registeredListeners.get(eventName);
      if (!set) continue;
      for (const listener of set) {
        eventTarget.removeEventListener(eventName, listener);
      }
      registeredListeners.delete(eventName);
    }
  },
  OffAll(): void {
    for (const [eventName, set] of registeredListeners.entries()) {
      for (const listener of set) {
        eventTarget.removeEventListener(eventName, listener);
      }
    }
    registeredListeners.clear();
  },
  Emit<T = unknown>(name: string, data?: T): Promise<boolean> {
    const payload = new WailsEvent<T>(name, data);
    eventTarget.dispatchEvent(new CustomEvent(name, { detail: payload }));
    return Promise.resolve(false);
  },
};

function createAny<T>(source: T): T {
  return source;
}

export const Create = {
  Any: createAny,
  ByteSlice(source: string | null | undefined): string {
    return source == null ? '' : source;
  },
  Array<T>(element: (item: unknown) => T): (source: unknown[] | null) => T[] {
    if (element === (createAny as unknown)) {
      return (source) => (source === null ? [] : (source as T[]));
    }
    return (source) => {
      if (source === null) return [];
      return source.map((item) => element(item));
    };
  },
  Map<K extends string | number, V>(
    _key: (k: unknown) => K,
    value: (v: unknown) => V
  ): (source: Record<string, unknown> | null) => Record<string, V> {
    if (value === (createAny as unknown)) {
      return (source) => (source === null ? {} : (source as Record<string, V>));
    }
    return (source) => {
      if (source === null) return {};
      const out: Record<string, V> = {};
      for (const k of Object.keys(source)) {
        out[k] = value(source[k]);
      }
      return out;
    };
  },
  Nullable<T>(element: (item: unknown) => T): (source: unknown) => T | null {
    if (element === (createAny as unknown)) {
      return createAny as (source: unknown) => T | null;
    }
    return (source) => (source === null ? null : element(source));
  },
  Struct(
    createField: Record<string, (v: unknown) => unknown>
  ): (source: Record<string, unknown>) => Record<string, unknown> {
    const entries = Object.entries(createField).filter(([, fn]) => fn !== (createAny as unknown));
    if (entries.length === 0) {
      return createAny;
    }
    return (source) => {
      for (const [name, fn] of entries) {
        if (name in source) {
          source[name] = fn(source[name]);
        }
      }
      return source;
    };
  },
  DateFromTime(source: string | number | Date): Date {
    return new Date(source);
  },
  Events: {} as Record<string, unknown>,
};
