<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { CheckCircle2, ShieldAlert, ShieldCheck, UserCog, X } from '@lucide/svelte';
  import {
    defaultUserSetupPort,
    validateUserSetupName,
    type UserAccreditation,
    type UserSetupPort,
  } from './userSetupModal';

  let {
    open = false,
    contextId = '',
    activeProject = 'None',
    port = defaultUserSetupPort,
    onSaved,
    onclose,
  }: {
    open?: boolean;
    contextId?: string;
    activeProject?: string;
    port?: UserSetupPort;
    onSaved?: (status: UserAccreditation) => void | Promise<void>;
    onclose: () => void;
  } = $props();

  let status = $state.raw<UserAccreditation | null>(null);
  let draftUser = $state('');
  let loading = $state(false);
  let saving = $state(false);
  let error = $state('');
  let savedNotice = $state('');
  let loadGen = 0;

  $effect(() => {
    const activeCtx = contextId;
    if (!open) return;
    untrack(() => {
      void refreshStatus(activeCtx);
    });
  });

  async function refreshStatus(activeCtx: string) {
    const gen = ++loadGen;
    loading = true;
    error = '';
    savedNotice = '';
    try {
      const current = await port.getUserSetup(activeCtx);
      if (gen !== loadGen) return;
      status = current;
      draftUser = current.userName ?? '';
    } catch (cause) {
      if (gen === loadGen) {
        error = `Could not load user setup: ${String(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  async function submitUserSetup(event: SubmitEvent) {
    event.preventDefault();
    if (saving || loading) return;
    const checked = validateUserSetupName(draftUser);
    if (!checked.valid) {
      error = checked.error;
      return;
    }
    const gen = ++loadGen;
    saving = true;
    error = '';
    savedNotice = '';
    try {
      const updated = await port.setUserName(contextId, checked.value);
      if (gen !== loadGen) return;
      status = updated;
      draftUser = updated.userName ?? checked.value;
      savedNotice = `Active user set to "${updated.userName}" (user settings and audit log updated).`;
      await onSaved?.(updated);
    } catch (cause) {
      if (gen === loadGen) {
        error = `Failed to save user setup: ${String(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        saving = false;
      }
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape' && !saving) {
      event.preventDefault();
      onclose();
    }
  }

  onDestroy(() => {
    loadGen++;
  });
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-3 sm:p-4" data-user-setup-modal>
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="user-setup-title"
      class="flex max-h-[88vh] w-full max-w-lg flex-col overflow-hidden rounded border border-[#D8D8D8] bg-white text-[#313132] shadow-2xl"
    >
      <header class="flex items-center justify-between gap-3 border-b-[3px] border-b-[#FCBA19] bg-[#003366] px-5 py-3.5 text-white">
        <div class="flex items-center gap-2.5">
          <UserCog size={18} class="shrink-0 text-[#FCBA19]" />
          <div>
            <div class="font-mono text-[11px] uppercase tracking-wider text-[#FCBA19]">
              Audit Identity &amp; BEC Accreditation
            </div>
            <h2 id="user-setup-title" class="text-base font-semibold text-white">
              VPro User Setup
            </h2>
          </div>
        </div>
        <button
          type="button"
          aria-label="Close User Setup"
          data-user-setup-close
          disabled={saving}
          class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20 disabled:opacity-45"
          onclick={onclose}
        >
          <X size={16} />
        </button>
      </header>

      <div class="space-y-4 overflow-y-auto p-5 text-xs">
        <p class="leading-relaxed text-[#474543]">
          Sets the active user name for plot edits, audit history, and session user log entries on
          <strong class="font-mono text-[#003366]">{activeProject}</strong>.
        </p>

        {#if error}
          <p role="alert" data-user-setup-error class="rounded border border-[#D8292F] bg-[#FBEAEA] p-2.5 text-[#D8292F]">
            {error}
          </p>
        {/if}

        {#if savedNotice}
          <div role="status" data-user-setup-saved class="flex items-start gap-2 rounded border border-[#2E8540] bg-[#EBF5ED] p-2.5 text-[#1E5128]">
            <CheckCircle2 size={15} class="mt-0.5 shrink-0" />
            <span>{savedNotice}</span>
          </div>
        {/if}

        <form onsubmit={(e) => void submitUserSetup(e)} class="space-y-3">
          <div>
            <label for="user-setup-name-input" class="mb-1 block font-semibold text-[#003366]">
              Active VPro User Name
            </label>
            <input
              id="user-setup-name-input"
              data-user-setup-input
              type="text"
              autocomplete="username"
              maxlength="128"
              disabled={loading || saving}
              bind:value={draftUser}
              placeholder="e.g. jsmith or mof-bec-reviewer"
              class="w-full rounded border border-[#9F9F9F] bg-white px-3 py-2 font-mono text-xs text-[#313132] focus:border-[#003366] focus:outline-2 focus:outline-[#FCBA19]"
            />
          </div>

          <div class="flex flex-wrap items-center justify-end gap-2">
            <button
              type="button"
              disabled={saving}
              class="rounded border border-[#D8D8D8] bg-white px-3 py-1.5 text-xs font-semibold text-[#313132] hover:bg-[#F2F2F2] disabled:opacity-45"
              onclick={onclose}
            >
              Close
            </button>
            <button
              type="submit"
              data-user-setup-save
              disabled={loading || saving}
              class="rounded bg-[#003366] px-3.5 py-1.5 text-xs font-semibold text-white hover:bg-[#002244] disabled:opacity-45"
            >
              {saving ? 'Saving…' : 'Save User Name'}
            </button>
          </div>
        </form>

        {#if loading}
          <p role="status" class="text-[#474543]">Checking BEC accreditation and restrictions…</p>
        {:else if status}
          <section aria-label="User Accreditation Status" data-user-accreditation-panel class="space-y-2 rounded border border-[#D8D8D8] bg-[#F2F2F2] p-3">
            <div class="flex items-center justify-between gap-2">
              <span class="font-semibold text-[#003366]">Provincial BEC Accreditation &amp; Restrictions</span>
              {#if status.canEditBecSiteUnit}
                <span class="inline-flex items-center gap-1 rounded border border-[#2E8540] bg-[#EBF5ED] px-2 py-0.5 font-mono text-[11px] font-semibold text-[#1E5128]">
                  <ShieldCheck size={12} /> Site Unit Edit Permitted
                </span>
              {:else}
                <span class="inline-flex items-center gap-1 rounded border border-[#FCBA19] bg-[#FEF6E0] px-2 py-0.5 font-mono text-[11px] font-semibold text-[#313132]">
                  <ShieldAlert size={12} /> Protected Master BEC Read-Only
                </span>
              {/if}
            </div>

            <dl class="grid grid-cols-1 gap-1.5 text-[11px] sm:grid-cols-2">
              <div class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5">
                <dt class="text-[#474543]">Accredited List (<code class="font-mono">USysAccreditation</code>)</dt>
                <dd class="font-mono font-semibold text-[#003366]">{status.accredited ? 'Yes' : 'No'}</dd>
              </div>
              <div class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5">
                <dt class="text-[#474543]">Master BEC Mode</dt>
                <dd class="font-mono font-semibold text-[#003366]">{status.masterBecAllowed ? 'Enabled' : 'Disabled'}</dd>
              </div>
              <div class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5">
                <dt class="text-[#474543]">User Restrictions (<code class="font-mono">USysUserRestrictions</code>)</dt>
                <dd class="font-mono font-semibold text-[#003366]">{status.inUserRestrictions ? 'Restricted' : 'None'}</dd>
              </div>
              <div class="rounded border border-[#D8D8D8] bg-white px-2.5 py-1.5">
                <dt class="text-[#474543]">Current Identity</dt>
                <dd class="truncate font-mono font-semibold text-[#003366]">{status.userName || 'Unset'}</dd>
              </div>
            </dl>
          </section>
        {/if}
      </div>
    </div>
  </div>
{/if}
