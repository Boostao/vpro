<script lang="ts">
  import { untrack } from 'svelte';
  import { KeyRound, Lock, LogIn, LogOut, ShieldCheck, Unlock, X } from '@lucide/svelte';
  import { ContextService } from '../../bindings/github.com/boostao/vpro/app';
  import type { ActivityRecordResult, SessionSummary, SignInResult } from '../../bindings/github.com/boostao/vpro/app/internal/auth/models';
  import type { EditLockState } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';
  import ModalDialogTrap from '../shared/ModalDialogTrap.svelte';
  import { formatError } from '../shared/readRequests';
  import { notifications } from './notificationService.svelte';

  export interface AuthSignInPort {
    GetAuthSession: () => Promise<SessionSummary>;
    GetEditLockStatus: (contextID: string) => Promise<EditLockState>;
    BeginOIDCSignIn: (providerHint: string) => Promise<SignInResult>;
    CompleteDevEvaluationSignIn: (userID: string, displayName: string, role: string) => Promise<SessionSummary>;
    SignOut: () => Promise<SessionSummary>;
    RecordAppActivity: (eventKind: string, datasetName: string, plotCount: number) => Promise<ActivityRecordResult>;
  }

  const defaultAuthPort: AuthSignInPort = {
    GetAuthSession: () => ContextService.GetAuthSession(),
    GetEditLockStatus: (contextID: string) => ContextService.GetEditLockStatus(contextID),
    BeginOIDCSignIn: (providerHint: string) => ContextService.BeginOIDCSignIn(providerHint),
    CompleteDevEvaluationSignIn: (userID: string, displayName: string, role: string) =>
      ContextService.CompleteDevEvaluationSignIn(userID, displayName, role),
    SignOut: () => ContextService.SignOut(),
    RecordAppActivity: (eventKind: string, datasetName: string, plotCount: number) =>
      ContextService.RecordAppActivity(eventKind, datasetName, plotCount),
  };

  const DEV_ROLES: Array<{ value: string; label: string; description: string }> = [
    { value: 'viewer', label: 'Viewer (Read-only)', description: 'Browse plots, maps, and reports; editing stays locked.' },
    { value: 'contributor', label: 'Contributor', description: 'Edit working project files and submit staged updates.' },
    {
      value: 'regional_ecologist',
      label: 'Regional Ecologist',
      description: 'Edit working projects and review regional classifications.',
    },
    { value: 'custodian', label: 'Custodian', description: 'Full editing access, including BECMaster maintenance.' },
  ];

  let {
    open = false,
    contextId = '',
    activeProject = '',
    plotCount = 0,
    port = defaultAuthPort,
    onstatuschange,
    onclose,
  }: {
    open?: boolean;
    contextId?: string;
    activeProject?: string;
    plotCount?: number;
    port?: AuthSignInPort;
    onstatuschange?: (payload: { session: SessionSummary | null; lockStatus: EditLockState | null }) => void;
    onclose: () => void;
  } = $props();

  let session = $state<SessionSummary | null>(null);
  let lockStatus = $state<EditLockState | null>(null);
  let loading = $state(false);
  let working = $state(false);
  let error = $state('');
  let notice = $state('');
  let pendingAuthUrl = $state('');
  let providerHint = $state('');
  let devDisplayName = $state('Field Ecologist');
  let devRole = $state('contributor');
  let loadGen = 0;

  const isSignedIn = $derived(Boolean(session?.signedIn || lockStatus?.signedIn));
  const isLocked = $derived(lockStatus ? lockStatus.locked : !isSignedIn);
  const devFallbackAvailable = $derived(Boolean(session?.devFallbackAvailable || lockStatus?.devFallbackAvailable));
  const signedInName = $derived(
    (session?.displayName || lockStatus?.displayName || session?.userId || lockStatus?.userId || 'Signed-in user').trim()
  );
  const signedInRole = $derived((session?.role || lockStatus?.role || 'viewer').trim());

  function dispatchAuthChanged() {
    if (typeof window !== 'undefined' && typeof CustomEvent !== 'undefined') {
      window.dispatchEvent(new CustomEvent('vpro:auth-changed'));
    }
  }

  function formatRoleLabel(role: string): string {
    switch (role.trim().toLowerCase()) {
      case 'custodian':
        return 'Custodian';
      case 'regional_ecologist':
        return 'Regional Ecologist';
      case 'contributor':
        return 'Contributor';
      case 'viewer':
        return 'Viewer';
      default:
        return role || 'Unassigned';
    }
  }

  async function refreshStatus() {
    const gen = ++loadGen;
    loading = true;
    error = '';
    try {
      const [nextSession, nextLock] = await Promise.all([
        port.GetAuthSession(),
        contextId ? port.GetEditLockStatus(contextId) : Promise.resolve(null),
      ]);
      if (gen !== loadGen) return;
      session = nextSession;
      lockStatus = nextLock;
      onstatuschange?.({ session: nextSession, lockStatus: nextLock });
    } catch (cause) {
      if (gen === loadGen) {
        error = `Could not load sign-in status: ${formatError(cause)}`;
      }
    } finally {
      if (gen === loadGen) {
        loading = false;
      }
    }
  }

  $effect(() => {
    if (!open) return;
    void contextId;
    untrack(() => {
      pendingAuthUrl = '';
      notice = '';
      void refreshStatus();
    });
  });

  async function handleOIDCSignIn() {
    if (working) return;
    working = true;
    error = '';
    notice = '';
    pendingAuthUrl = '';
    try {
      const result = await port.BeginOIDCSignIn(providerHint);
      if (result.session) session = result.session;
      if (result.authUrl && !result.browserOpened) {
        pendingAuthUrl = result.authUrl;
      }
      if (result.warning) {
        notice = result.warning;
      }
      if (result.completed && result.session?.signedIn) {
        const nextLock = contextId ? await port.GetEditLockStatus(contextId) : null;
        lockStatus = nextLock;
        onstatuschange?.({ session: result.session, lockStatus: nextLock });
        void port.RecordAppActivity('signin', activeProject, plotCount).catch(() => {});
        dispatchAuthChanged();
        notice = `Signed in as ${result.session.displayName || result.session.userId} (${formatRoleLabel(result.session.role)}).`;
        notifications.success('Signed in to VPro', notice, { source: 'Access', toast: true });
      }
    } catch (cause) {
      error = `BC Gov sign-in did not complete: ${formatError(cause)}`;
    } finally {
      working = false;
    }
  }

  async function handleDevSignIn(event: SubmitEvent) {
    event.preventDefault();
    if (working) return;
    const cleanName = devDisplayName.trim() || 'Field Ecologist';
    const slug = cleanName
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
    const userId = `dev-${slug || 'ecologist'}`;
    working = true;
    error = '';
    notice = '';
    try {
      const nextSession = await port.CompleteDevEvaluationSignIn(userId, cleanName, devRole);
      session = nextSession;
      const nextLock = contextId ? await port.GetEditLockStatus(contextId) : null;
      lockStatus = nextLock;
      onstatuschange?.({ session: nextSession, lockStatus: nextLock });
      void port.RecordAppActivity('signin', activeProject, plotCount).catch(() => {});
      dispatchAuthChanged();
      notice = `Signed in as ${nextSession.displayName || nextSession.userId} (${formatRoleLabel(nextSession.role)}).`;
      notifications.success('Evaluation sign-in active', notice, { source: 'Access', toast: true });
    } catch (cause) {
      error = `Could not complete evaluation sign-in: ${formatError(cause)}`;
    } finally {
      working = false;
    }
  }

  async function handleSignOut() {
    if (working) return;
    working = true;
    error = '';
    notice = '';
    pendingAuthUrl = '';
    try {
      const nextSession = await port.SignOut();
      session = nextSession;
      const nextLock = contextId ? await port.GetEditLockStatus(contextId) : null;
      lockStatus = nextLock;
      onstatuschange?.({ session: nextSession, lockStatus: nextLock });
      dispatchAuthChanged();
      notice = 'Signed out. Data editing is locked on this computer until you sign in again.';
      notifications.info('Signed out of VPro', notice, { source: 'Access', toast: true });
    } catch (cause) {
      error = `Could not sign out: ${formatError(cause)}`;
    } finally {
      working = false;
    }
  }
</script>

{#if open}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-vpro-ink/50 p-4" data-auth-signin-modal>
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="auth-signin-modal-title"
      class="flex max-h-[88vh] w-full max-w-lg flex-col overflow-hidden rounded border border-vpro-border bg-white text-vpro-ink shadow-2xl"
    >
      <ModalDialogTrap onEscape={onclose} escapeDisabled={working} initialFocusSelector="[data-auth-modal-close]" />

      <header
        class="flex items-center justify-between gap-3 border-b-[3px] border-b-vpro-gold bg-vpro-navy px-5 py-3.5 text-white"
      >
        <div class="flex items-center gap-2.5">
          <KeyRound size={18} class="text-vpro-gold" aria-hidden="true" />
          <div>
            <div class="font-mono text-[11px] uppercase tracking-wider text-vpro-gold">
              One-Time Machine Access
            </div>
            <h2 id="auth-signin-modal-title" class="text-base font-semibold text-white">Sign In &amp; Access</h2>
          </div>
        </div>
        <button
          type="button"
          aria-label="Close Sign In & Access"
          data-auth-modal-close
          class="rounded border border-white/30 bg-white/10 p-1.5 text-white hover:bg-white/20"
          disabled={working}
          onclick={onclose}
        >
          <X size={16} aria-hidden="true" />
        </button>
      </header>

      <div class="space-y-4 overflow-y-auto p-5 text-xs">
        {#if error}
          <p role="alert" class="rounded border border-vpro-error bg-red-50 p-2.5 text-vpro-error" data-auth-error>
            {error}
          </p>
        {/if}

        {#if notice}
          <p role="status" class="rounded border border-vpro-navy/30 bg-vpro-canvas p-2.5 text-vpro-navy" data-auth-notice>
            {notice}
          </p>
        {/if}

        <section
          aria-label="Current editing access status"
          data-auth-status-card
          class="rounded border p-3.5 {isLocked
            ? 'border-vpro-gold bg-vpro-warning-bg'
            : 'border-vpro-success/40 bg-vpro-canvas'}"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-start gap-2.5">
              {#if isLocked}
                <Lock size={18} class="mt-0.5 shrink-0 text-vpro-navy" aria-hidden="true" />
              {:else}
                <Unlock size={18} class="mt-0.5 shrink-0 text-vpro-success" aria-hidden="true" />
              {/if}
              <div class="space-y-1">
                {#if loading && !session && !lockStatus}
                  <div class="font-semibold text-vpro-navy">Checking sign-in status…</div>
                {:else if isSignedIn}
                  <div class="font-bold text-vpro-navy" data-auth-status-headline>
                    Signed in as {signedInName} ({signedInRole})
                  </div>
                  <div class="text-[11px] text-vpro-ink-secondary">
                    {#if isLocked}
                      {lockStatus?.reason || 'Data editing is currently locked for this project.'}
                    {:else}
                      Data editing is unlocked on this computer{session?.offlineMode ? ' (cached offline session)' : ''}.
                    {/if}
                  </div>
                {:else}
                  <div class="font-bold text-vpro-navy" data-auth-status-headline>Data locked — Sign in to edit</div>
                  <div class="text-[11px] text-vpro-ink-secondary">
                    {lockStatus?.reason ||
                      'Sign in once on this computer with your BC Gov ID (IDIR or BCeID) to unlock plot editing. Offline field use stays unlocked automatically.'}
                  </div>
                {/if}
              </div>
            </div>

            {#if isSignedIn}
              <button
                type="button"
                data-auth-signout
                disabled={working}
                class="inline-flex shrink-0 items-center gap-1.5 rounded border border-vpro-navy bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle disabled:opacity-50"
                onclick={() => void handleSignOut()}
              >
                <LogOut size={13} aria-hidden="true" />
                <span>Sign Out</span>
              </button>
            {/if}
          </div>

          {#if isSignedIn && session}
            <dl class="mt-3 grid grid-cols-2 gap-2 border-t border-black/10 pt-2.5 text-[11px]">
              <div>
                <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Role</dt>
                <dd class="font-semibold text-vpro-ink">{formatRoleLabel(session.role)}</dd>
              </div>
              <div>
                <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Provider</dt>
                <dd class="font-semibold text-vpro-ink">
                  {session.isDevEvaluation ? 'Dev Evaluation' : session.identityProvider || 'BC Gov ID'}
                </dd>
              </div>
              <div>
                <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">Working Projects</dt>
                <dd class="font-semibold {session.canEditWorkingProjects ? 'text-vpro-success' : 'text-vpro-ink-secondary'}">
                  {session.canEditWorkingProjects ? 'Editable' : 'Read-only'}
                </dd>
              </div>
              <div>
                <dt class="font-mono text-[10px] uppercase text-vpro-ink-secondary">BECMaster Editing</dt>
                <dd class="font-semibold {session.canEditBecMaster ? 'text-vpro-success' : 'text-vpro-ink-secondary'}">
                  {session.canEditBecMaster ? 'Custodian access' : 'Protected'}
                </dd>
              </div>
            </dl>
          {/if}
        </section>

        <section aria-label="BC Gov ID sign-in" class="space-y-2.5 rounded border border-vpro-border bg-white p-3.5">
          <div class="flex items-center gap-2 font-semibold text-vpro-navy">
            <ShieldCheck size={15} aria-hidden="true" />
            <span>BC Government Single Sign-On</span>
          </div>
          <p class="leading-relaxed text-vpro-ink-secondary">
            Sign in once on this computer using your BC Government IDIR or Business BCeID account. VPro keeps your access
            available offline when working in the field.
          </p>

          <div class="flex flex-wrap items-center gap-2">
            <label for="auth-provider-hint" class="sr-only">Account type</label>
            <select
              id="auth-provider-hint"
              bind:value={providerHint}
              disabled={working}
              class="rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs text-vpro-ink"
            >
              <option value="">Choose at BC Gov login</option>
              <option value="idir">IDIR (BC Gov staff)</option>
              <option value="bceidbusiness">Business BCeID</option>
            </select>

            <button
              type="button"
              data-auth-oidc-signin
              disabled={working}
              class="inline-flex flex-1 items-center justify-center gap-1.5 rounded bg-vpro-navy px-3.5 py-2 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
              onclick={() => void handleOIDCSignIn()}
            >
              <LogIn size={14} aria-hidden="true" />
              <span>{working ? 'Waiting for sign-in…' : 'Sign in with BC Gov ID (IDIR / BCeID)'}</span>
            </button>
          </div>

          {#if pendingAuthUrl}
            <div class="rounded border border-vpro-border bg-vpro-canvas p-2.5 text-[11px]">
              <div class="font-semibold text-vpro-navy">Browser did not open automatically</div>
              <p class="mt-0.5 text-vpro-ink-secondary">Open this sign-in address in your web browser:</p>
              <div class="mt-1 break-all font-mono text-[10px] text-vpro-ink">{pendingAuthUrl}</div>
            </div>
          {/if}
        </section>

        {#if devFallbackAvailable}
          <section
            aria-label="Dev Evaluation Sign-In"
            data-auth-dev-section
            class="space-y-2.5 rounded border border-dashed border-vpro-navy/40 bg-vpro-canvas p-3.5"
          >
            <div class="font-semibold text-vpro-navy">Dev Evaluation Sign-In</div>
            <p class="text-[11px] leading-relaxed text-vpro-ink-secondary">
              Available in development builds when BC Gov sign-in is not configured. Pick a name and role to evaluate
              edit locking and unlocking locally.
            </p>
            <form class="space-y-2.5" onsubmit={(e) => void handleDevSignIn(e)}>
              <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <label class="flex flex-col gap-1 text-[11px] font-medium text-vpro-ink">
                  <span>Display Name</span>
                  <input
                    type="text"
                    data-auth-dev-name
                    bind:value={devDisplayName}
                    disabled={working}
                    placeholder="Field Ecologist"
                    class="rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs text-vpro-ink"
                  />
                </label>
                <label class="flex flex-col gap-1 text-[11px] font-medium text-vpro-ink">
                  <span>Evaluation Role</span>
                  <select
                    data-auth-dev-role
                    bind:value={devRole}
                    disabled={working}
                    class="rounded border border-vpro-border bg-white px-2.5 py-1.5 text-xs text-vpro-ink"
                  >
                    {#each DEV_ROLES as item (item.value)}
                      <option value={item.value}>{item.label}</option>
                    {/each}
                  </select>
                </label>
              </div>
              <p class="text-[11px] text-vpro-ink-secondary">
                {DEV_ROLES.find((r) => r.value === devRole)?.description}
              </p>
              <button
                type="submit"
                data-auth-dev-signin
                disabled={working}
                class="inline-flex items-center gap-1.5 rounded border border-vpro-navy bg-white px-3 py-1.5 text-xs font-semibold text-vpro-navy hover:bg-vpro-navy-tint disabled:opacity-50"
              >
                <Unlock size={13} aria-hidden="true" />
                <span>{working ? 'Signing in…' : 'Sign In (Dev Evaluation)'}</span>
              </button>
            </form>
          </section>
        {/if}
      </div>
    </div>
  </div>
{/if}
