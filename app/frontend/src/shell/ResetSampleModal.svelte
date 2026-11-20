<script lang="ts">
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';

  let {
    open,
    busy,
    editorBusy,
    companionPanelBusy,
    transitionWorking,
    contextAvailable,
    onconfirm,
    onclose,
  }: {
    open: boolean;
    busy: boolean;
    editorBusy: boolean;
    companionPanelBusy: boolean;
    transitionWorking: boolean;
    contextAvailable: boolean;
    onconfirm: () => void;
    onclose: () => void;
  } = $props();
</script>

{#if open}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-vpro-ink/50 p-4" data-reset-sample-modal>
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="reset-sample-modal-title"
      class="w-full max-w-md overflow-hidden rounded border border-vpro-border bg-white text-vpro-ink shadow-2xl"
    >
      <ModalDialogTrap onEscape={onclose} escapeDisabled={busy || transitionWorking} />
      <header class="border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white">
        <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">Safe Non-Destructive Recovery</div>
        <h2 id="reset-sample-modal-title" class="text-sm font-semibold text-white">Reset Workspace to Sample</h2>
      </header>
      <div class="space-y-3 p-4 text-xs leading-relaxed">
        <p>
          Restore a fresh copy of the built-in <code class="font-mono text-vpro-navy">Sample</code> project and switch
          the active session cleanly to
          <strong>Project = Sample</strong>, <strong>SU = Sample</strong>, and <strong>Hierarchy = Sample</strong>?
        </p>
        <p class="rounded border border-vpro-border bg-vpro-canvas p-2.5 text-vpro-ink-secondary">
          Existing user project <code class="font-mono">.db</code> files in your projects directory are
          <strong>never deleted or modified</strong>.
        </p>
        <div class="flex justify-end gap-2 pt-2">
          <button
            type="button"
            disabled={busy || transitionWorking}
            class="rounded border border-vpro-border bg-white px-3 py-1.5 text-xs font-medium text-vpro-ink hover:bg-vpro-surface-subtle"
            onclick={onclose}
          >
            Cancel
          </button>
          <button
            type="button"
            data-confirm-reset-sample
            disabled={busy || editorBusy || companionPanelBusy || transitionWorking || !contextAvailable}
            class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
            onclick={onconfirm}
          >
            {busy ? 'Resetting...' : 'Reset Workspace to Sample'}
          </button>
        </div>
      </div>
    </div>
  </div>
{/if}
