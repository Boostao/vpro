import { untrack } from 'svelte';

export interface SubscribableSession {
  subscribe(listener: () => void): () => void;
}

export function observeSession<S extends SubscribableSession, V>(
  getSession: () => S | null | undefined,
  read: (session: S) => V
): { readonly current: V | undefined } {
  let version = $state(0);

  $effect(() => {
    const session = getSession();
    if (!session) return;
    return session.subscribe(() => {
      untrack(() => {
        version += 1;
      });
    });
  });

  const current = $derived.by(() => {
    void version;
    const session = getSession();
    return session ? read(session) : undefined;
  });

  return {
    get current() {
      return current;
    },
  };
}

export function observeSessionView<V>(getSession: () => (SubscribableSession & { view(): V }) | null | undefined): {
  readonly current: V | undefined;
} {
  return observeSession(getSession, (session) => session.view());
}
