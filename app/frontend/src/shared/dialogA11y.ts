export interface ModalDialogOptions {
  onClose?: () => void;
  escapeDisabled?: boolean;
  trapFocus?: boolean;
  initialFocusSelector?: string;
}

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not(:disabled)',
  'input:not(:disabled):not([type="hidden"])',
  'select:not(:disabled)',
  'textarea:not(:disabled)',
  'summary',
  '[tabindex]:not([tabindex="-1"])',
].join(', ');

function isElementVisible(el: HTMLElement): boolean {
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

export function findFocusableElements(container: HTMLElement): HTMLElement[] {
  const candidates = Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
  return candidates.filter((el) => !el.hasAttribute('disabled') && el.tabIndex >= 0 && isElementVisible(el));
}

export function trapDialogTabKey(event: KeyboardEvent, dialogEl: HTMLElement): boolean {
  if (event.key !== 'Tab') return false;
  const focusable = findFocusableElements(dialogEl);
  if (focusable.length === 0) {
    event.preventDefault();
    if (dialogEl.tabIndex < 0) dialogEl.tabIndex = -1;
    dialogEl.focus();
    return true;
  }
  const doc = dialogEl.ownerDocument ?? document;
  const active = doc.activeElement as HTMLElement | null;
  const currentIndex = active ? focusable.indexOf(active) : -1;

  if (event.shiftKey) {
    if (currentIndex <= 0 || !dialogEl.contains(active)) {
      event.preventDefault();
      focusable[focusable.length - 1].focus();
      return true;
    }
  } else if (currentIndex === -1 || currentIndex >= focusable.length - 1 || !dialogEl.contains(active)) {
    event.preventDefault();
    focusable[0].focus();
    return true;
  }
  return false;
}

function getTopmostModalDialog(doc: Document): HTMLElement | null {
  const dialogs = Array.from(
    doc.querySelectorAll<HTMLElement>(
      'dialog[open], [role="dialog"][aria-modal="true"], [role="dialog"][data-modal-trap="true"]'
    )
  ).filter(isElementVisible);
  return dialogs.length > 0 ? dialogs[dialogs.length - 1] : null;
}

let globalTrapInstalled = false;

export function installGlobalAriaModalTabTrap(
  doc: Document | undefined = typeof document !== 'undefined' ? document : undefined
): void {
  if (!doc || globalTrapInstalled) return;
  globalTrapInstalled = true;
  doc.addEventListener(
    'keydown',
    (event: KeyboardEvent) => {
      if (event.key !== 'Tab' || event.defaultPrevented) return;
      const topDialog = getTopmostModalDialog(doc);
      if (!topDialog || topDialog.tagName === 'DIALOG') return;
      trapDialogTabKey(event, topDialog);
    },
    true
  );
}

function isHtmlElementLike(value: unknown): value is HTMLElement {
  if (typeof HTMLElement !== 'undefined') return value instanceof HTMLElement;
  return Boolean(value && typeof (value as HTMLElement).focus === 'function');
}

export function modalDialog(node: HTMLElement, initialOptions: ModalDialogOptions = {}) {
  let opts = { ...initialOptions };
  const doc = node.ownerDocument ?? (typeof document !== 'undefined' ? document : undefined);
  installGlobalAriaModalTabTrap(doc);

  const previousFocus =
    doc && isHtmlElementLike(doc.activeElement) && !node.contains(doc.activeElement) ? doc.activeElement : null;

  if (node.tabIndex < 0 && !node.hasAttribute('tabindex')) {
    node.setAttribute('tabindex', '-1');
  }

  const moveInitialFocus = () => {
    if (node.isConnected === false || !doc) return;
    if (node.contains(doc.activeElement) && doc.activeElement !== node) return;
    if (opts.initialFocusSelector) {
      const preferred = node.querySelector<HTMLElement>(opts.initialFocusSelector);
      if (preferred && !preferred.hasAttribute('disabled') && isElementVisible(preferred)) {
        preferred.focus();
        return;
      }
    }
    const autoTarget = node.querySelector<HTMLElement>('[data-dialog-autofocus]');
    if (autoTarget && !autoTarget.hasAttribute('disabled') && isElementVisible(autoTarget)) {
      autoTarget.focus();
      return;
    }
    const focusable = findFocusableElements(node);
    if (focusable.length > 0) {
      focusable[0].focus();
    } else {
      node.focus();
    }
  };

  const scheduleMicrotask =
    typeof queueMicrotask === 'function'
      ? queueMicrotask
      : (cb: () => void) => {
          void Promise.resolve().then(cb);
        };

  moveInitialFocus();
  scheduleMicrotask(moveInitialFocus);

  const handleKeydown = (event: KeyboardEvent) => {
    if (node.isConnected === false || !doc) return;
    const dialogs = Array.from(doc.querySelectorAll<HTMLElement>('[role="dialog"]')).filter(isElementVisible);
    if (dialogs.length > 0 && dialogs[dialogs.length - 1] !== node) return;

    if (event.key === 'Tab' && opts.trapFocus !== false) {
      trapDialogTabKey(event, node);
      return;
    }
    if (event.key === 'Escape' && opts.onClose && !opts.escapeDisabled) {
      event.preventDefault();
      event.stopPropagation();
      opts.onClose();
    }
  };

  const keyTarget: Pick<EventTarget, 'addEventListener' | 'removeEventListener'> | undefined =
    doc?.defaultView ?? doc ?? (typeof window !== 'undefined' ? window : undefined);
  keyTarget?.addEventListener('keydown', handleKeydown as EventListener, true);

  return {
    update(nextOptions: ModalDialogOptions = {}) {
      opts = { ...nextOptions };
    },
    destroy() {
      keyTarget?.removeEventListener('keydown', handleKeydown as EventListener, true);
      if (previousFocus && previousFocus.isConnected !== false) {
        const restoreTarget = previousFocus;
        restoreTarget.focus();
        scheduleMicrotask(() => {
          if (restoreTarget.isConnected !== false) {
            restoreTarget.focus();
          }
        });
      }
    },
  };
}
