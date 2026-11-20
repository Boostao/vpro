export type ContextSessionDisposer = (contextId: string) => void;

type GlobalContextDisposerHost = typeof globalThis & {
  __vproContextDisposers?: Set<ContextSessionDisposer>;
};

function getContextDisposers(): Set<ContextSessionDisposer> {
  const host = globalThis as GlobalContextDisposerHost;
  if (!host.__vproContextDisposers) {
    host.__vproContextDisposers = new Set<ContextSessionDisposer>();
  }
  return host.__vproContextDisposers;
}

export function registerContextDisposer(evict: ContextSessionDisposer): () => void {
  const disposers = getContextDisposers();
  disposers.add(evict);
  return () => {
    disposers.delete(evict);
  };
}

function defaultKeyMatchesContext(key: unknown, contextId: string): boolean {
  if (typeof key !== 'string') return false;
  return (
    key === contextId ||
    key.startsWith(`${contextId}:`) ||
    key.startsWith(`${contextId}\u0000`) ||
    key.startsWith(`[${JSON.stringify(contextId)},`) ||
    key === `[${JSON.stringify(contextId)}]`
  );
}

export function evictMapEntriesByContext<K, V>(
  map: Map<K, V>,
  contextId: string,
  matchesContext: (key: K, value: V, contextId: string) => boolean = (k, _v, c) => defaultKeyMatchesContext(k, c),
  cleanup?: (value: V, key: K) => void
): number {
  if (!contextId) return 0;
  let evicted = 0;
  for (const [key, value] of [...map.entries()]) {
    if (matchesContext(key, value, contextId)) {
      map.delete(key);
      cleanup?.(value, key);
      evicted += 1;
    }
  }
  return evicted;
}

export function onContextDisposed(oldContextId: string): void {
  if (!oldContextId) return;
  for (const evict of [...getContextDisposers()]) {
    evict(oldContextId);
  }
}
