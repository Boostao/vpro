<script lang="ts">
  import { onDestroy, onMount } from 'svelte';

  let {
    onEscape,
    escapeDisabled = false,
    trapFocus = true,
    initialFocusSelector = '',
  }: {
    onEscape?: () => void;
    escapeDisabled?: boolean;
    trapFocus?: boolean;
    initialFocusSelector?: string;
  } = $props();

  let markerEl: HTMLSpanElement | undefined = $state();
  let previousFocus: HTMLElement | null = null;
  let dialogEl: HTMLElement | null = null;

  const FOCUSABLE_SELECTOR = [
    'a[href]',
    'button:not(:disabled)',
    'input:not(:disabled):not([type="hidden"])',
    'select:not(:disabled)',
    'textarea:not(:disabled)',
    'summary',
    '[tabindex]:not([tabindex="-1"])',
  ].join(', ');

  function isVisible(el: HTMLElement): boolean {
    if (el.hidden || el.getAttribute('aria-hidden') === 'true') return false;
    let cur: HTMLElement | null = el;
    while (cur) {
      if (cur.hidden || cur.getAttribute('aria-hidden') === 'true') return false;
      if (typeof getComputedStyle === 'function') {
        const style = getComputedStyle(cur);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
      }
      cur = cur.parentElement;
    }
    return true;
  }

  function getFocusable(root: HTMLElement): HTMLElement[] {
    return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
      (el) => !el.hasAttribute('disabled') && el.tabIndex >= 0 && isVisible(el)
    );
  }

  function trapTab(event: KeyboardEvent, root: HTMLElement) {
    const focusable = getFocusable(root);
    if (focusable.length === 0) {
      event.preventDefault();
      if (root.tabIndex < 0) root.tabIndex = -1;
      root.focus();
      return;
    }
    const doc = root.ownerDocument ?? document;
    const active = doc.activeElement as HTMLElement | null;
    const idx = active ? focusable.indexOf(active) : -1;
    if (event.shiftKey) {
      if (idx <= 0 || !root.contains(active)) {
        event.preventDefault();
        focusable[focusable.length - 1].focus();
      }
    } else if (idx === -1 || idx >= focusable.length - 1 || !root.contains(active)) {
      event.preventDefault();
      focusable[0].focus();
    }
  }

  function ensureGlobalAriaModalTrap(doc: Document) {
    const win = doc.defaultView as (Window & { __vproAriaModalTrapInstalled?: boolean }) | null;
    if (!win || win.__vproAriaModalTrapInstalled) return;
    win.__vproAriaModalTrapInstalled = true;
    doc.addEventListener(
      'keydown',
      (event: KeyboardEvent) => {
        if (event.key !== 'Tab' || event.defaultPrevented) return;
        const modals = Array.from(
          doc.querySelectorAll<HTMLElement>('dialog[open], [role="dialog"][aria-modal="true"]')
        ).filter(isVisible);
        const top = modals.length > 0 ? modals[modals.length - 1] : null;
        if (!top || top.tagName === 'DIALOG') return;
        trapTab(event, top);
      },
      true
    );
  }

  function focusInsideDialog(root: HTMLElement) {
    const doc = root.ownerDocument ?? document;
    if (!root.isConnected) return;
    if (root.contains(doc.activeElement) && doc.activeElement !== root) return;
    if (initialFocusSelector) {
      const target = root.querySelector<HTMLElement>(initialFocusSelector);
      if (target && !target.hasAttribute('disabled') && isVisible(target)) {
        target.focus();
        return;
      }
    }
    const marked = root.querySelector<HTMLElement>('[data-dialog-autofocus]');
    if (marked && !marked.hasAttribute('disabled') && isVisible(marked)) {
      marked.focus();
      return;
    }
    const focusable = getFocusable(root);
    if (focusable.length > 0) {
      focusable[0].focus();
    } else {
      if (root.tabIndex < 0) root.tabIndex = -1;
      root.focus();
    }
  }

  function handleWindowKeydown(event: KeyboardEvent) {
    if (!dialogEl || !dialogEl.isConnected) return;
    const doc = dialogEl.ownerDocument ?? document;
    const visibleDialogs = Array.from(doc.querySelectorAll<HTMLElement>('[role="dialog"]')).filter(isVisible);
    if (visibleDialogs.length > 0 && visibleDialogs[visibleDialogs.length - 1] !== dialogEl) return;

    if (event.key === 'Tab' && trapFocus) {
      trapTab(event, dialogEl);
      return;
    }
    if (event.key === 'Escape' && onEscape && !escapeDisabled) {
      event.preventDefault();
      event.stopPropagation();
      onEscape();
    }
  }

  onMount(() => {
    const host = markerEl?.closest<HTMLElement>('[role="dialog"]') ?? markerEl?.parentElement ?? null;
    dialogEl = host;
    const doc = host?.ownerDocument ?? (typeof document !== 'undefined' ? document : undefined);
    if (doc) {
      ensureGlobalAriaModalTrap(doc);
      if (doc.activeElement instanceof HTMLElement && (!host || !host.contains(doc.activeElement))) {
        previousFocus = doc.activeElement;
      }
    }
    if (host) {
      if (!host.hasAttribute('tabindex')) host.setAttribute('tabindex', '-1');
      focusInsideDialog(host);
      queueMicrotask(() => {
        if (dialogEl) focusInsideDialog(dialogEl);
      });
    }
    const win = doc?.defaultView ?? (typeof window !== 'undefined' ? window : undefined);
    win?.addEventListener('keydown', handleWindowKeydown, true);
    return () => {
      win?.removeEventListener('keydown', handleWindowKeydown, true);
    };
  });

  onDestroy(() => {
    const target = previousFocus;
    previousFocus = null;
    dialogEl = null;
    if (target) {
      queueMicrotask(() => {
        if (target.isConnected) {
          target.focus();
        }
      });
    }
  });
</script>

<span bind:this={markerEl} hidden aria-hidden="true" data-modal-dialog-trap></span>
