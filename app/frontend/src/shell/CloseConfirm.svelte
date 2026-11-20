<script lang="ts">
  import type { CloseDecision } from './closeLifecycle';

  let {
    requestId,
    working,
    canSave,
    saveReason,
    error,
    onrespond,
    purpose = 'close',
    editorLabel = 'FS882',
  }: {
    requestId: string;
    working: boolean;
    canSave: boolean;
    saveReason: string;
    error: string;
    onrespond: (decision: CloseDecision) => Promise<void>;
    purpose?: 'close' | 'context';
    editorLabel?: 'FS882' | 'FS882 (2-Page)' | 'SIVI / FS1333';
  } = $props();
  let dialog: HTMLDialogElement;

  $effect(() => {
    if (requestId && !dialog.open) dialog.showModal();
    else if (!requestId && dialog.open) dialog.close();
  });
</script>

<dialog
  bind:this={dialog}
  role="alertdialog"
  aria-labelledby="close-title"
  aria-describedby="close-description"
  oncancel={(event) => {
    event.preventDefault();
    if (!working) void onrespond('cancel');
  }}
>
  <header class="dialog-header">
    <div class="dialog-eyebrow">Unsaved Draft Protection</div>
    <h2 id="close-title">
      {purpose === 'close' ? 'Save changes before closing VPRO?' : 'Save changes before changing context?'}
    </h2>
  </header>
  <div class="dialog-body">
    <p id="close-description">
      {purpose === 'close'
        ? `${editorLabel} has an unsaved draft or incomplete entry. Cancel keeps the application open. Discard closes without saving this draft; completed child edits remain saved.`
        : `${editorLabel} has an unsaved draft or incomplete entry. Save writes to the current project before switching. Cancel keeps the current context and draft. Discard removes this draft only after the switch succeeds; completed child edits remain saved.`}
    </p>
    {#if error}<p role="alert">{error}</p>{/if}
    {#if !canSave}<p role="status">{saveReason}</p>{/if}
    <div class="actions">
      <button type="button" class="btn-secondary" disabled={working} onclick={() => onrespond('cancel')}>Cancel</button>
      <button type="button" class="btn-primary" disabled={working || !canSave} onclick={() => onrespond('save')}
        >{purpose === 'close' ? 'Save and close' : 'Save and continue'}</button
      >
      <button type="button" class="btn-danger" disabled={working} onclick={() => onrespond('discard')}
        >{purpose === 'close' ? 'Discard draft and close' : 'Discard draft and continue'}</button
      >
    </div>
  </div>
</dialog>

<style>
  dialog {
    max-width: min(38rem, calc(100vw - 2rem));
    padding: 0;
    border: 1px solid var(--vpro-border);
    border-radius: var(--vpro-radius-lg, 8px);
    box-shadow: var(--vpro-shadow-lg, 0 14px 34px rgba(0, 34, 68, 0.2));
    background: var(--vpro-surface);
    color: var(--vpro-ink);
    overflow: hidden;
  }
  dialog::backdrop {
    background: rgba(0, 34, 68, 0.45);
  }
  .dialog-header {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    padding: 0.9rem 1.25rem;
    border-bottom: 3px solid var(--vpro-gold);
  }
  .dialog-eyebrow {
    font-family: var(--vpro-font-mono, monospace);
    font-size: 0.7rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--vpro-gold);
    margin-bottom: 0.2rem;
  }
  h2 {
    font-size: 1.05rem;
    font-weight: 700;
    margin: 0;
    color: var(--vpro-surface);
  }
  .dialog-body {
    padding: 1.15rem 1.25rem 1.25rem;
  }
  p {
    margin: 0 0 0.75rem;
    font-size: 0.9rem;
    line-height: 1.5;
    color: var(--vpro-ink);
  }
  [role='alert'] {
    padding: 0.55rem 0.75rem;
    border-radius: var(--vpro-radius-sm, 4px);
    background: var(--vpro-error-bg);
    border: 1px solid var(--vpro-error-border);
    color: var(--vpro-error-ink);
    font-weight: 600;
  }
  [role='status'] {
    padding: 0.55rem 0.75rem;
    border-radius: var(--vpro-radius-sm, 4px);
    background: var(--vpro-warning-bg);
    border: 1px solid var(--vpro-warning-border);
    color: var(--vpro-warning-ink);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 0.6rem;
    margin-top: 1rem;
    padding-top: 0.85rem;
    border-top: 1px solid var(--vpro-border);
  }
  button {
    min-height: 36px;
    padding: 0.45rem 0.85rem;
    border-radius: var(--vpro-radius-sm, 4px);
    font: inherit;
    font-size: 0.85rem;
    font-weight: 600;
  }
  .btn-secondary {
    border: 1px solid var(--vpro-border-strong);
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  .btn-secondary:hover:not(:disabled) {
    background: var(--vpro-surface-subtle);
  }
  .btn-primary {
    border: 1px solid var(--vpro-navy);
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
  .btn-primary:hover:not(:disabled) {
    background: var(--vpro-navy-hover);
  }
  .btn-danger {
    border: 1px solid var(--vpro-error-border);
    background: var(--vpro-error-bg);
    color: var(--vpro-error-ink);
  }
  .btn-danger:hover:not(:disabled) {
    background: #f6d5d7;
  }
  button:disabled {
    opacity: 0.5;
  }
  button:focus-visible {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 2px;
  }
</style>
