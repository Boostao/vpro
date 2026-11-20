<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import {
    LifecycleService,
    type StartupRecoveryRequest,
    type StartupState,
  } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, trackIfCancellable } from '../shared/readRequests';
  import { deriveInitialRecoveryDraft, formatStartupError, hasConfiguredContextSelection } from './startupRecovery';

  const reads = new ReadRequests();
  onDestroy(() => reads.cancelAll());

  let {
    startupFailure,
    busy,
    onrecovered,
  }: {
    startupFailure: StartupState;
    busy: boolean;
    onrecovered: (backupNotice: string) => Promise<void> | void;
  } = $props();

  function failureSignature(state: StartupState): string {
    return JSON.stringify([
      state.configPath ?? '',
      state.message ?? '',
      state.configuredProject ?? '',
      state.projectPath ?? '',
      state.configuredSu ?? '',
      state.suPath ?? '',
      state.configuredHierarchy ?? '',
      state.hierarchyPath ?? '',
    ]);
  }

  const initialSeed = untrack(() => deriveInitialRecoveryDraft(startupFailure));
  let appliedSignature = untrack(() => failureSignature(startupFailure));

  let recoveryWorking = $state(false);
  let recoveryError = $state('');
  let recoveryProjectPath = $state(initialSeed.projectPath);
  let recoveryProjectName = $state(initialSeed.projectName);
  let recoverySUPath = $state(initialSeed.suPath);
  let recoveryClearSU = $state(initialSeed.clearSu);
  let recoveryHierarchyPath = $state(initialSeed.hierarchyPath);
  let recoveryClearHierarchy = $state(initialSeed.clearHierarchy);

  let derivedMeta = $derived(deriveInitialRecoveryDraft(startupFailure));

  $effect(() => {
    const nextSignature = failureSignature(startupFailure);
    if (nextSignature === appliedSignature) return;
    appliedSignature = nextSignature;
    const nextDraft = deriveInitialRecoveryDraft(startupFailure);
    recoveryProjectPath = nextDraft.projectPath;
    recoveryProjectName = nextDraft.projectName;
    recoverySUPath = nextDraft.suPath;
    recoveryClearSU = nextDraft.clearSu;
    recoveryHierarchyPath = nextDraft.hierarchyPath;
    recoveryClearHierarchy = nextDraft.clearHierarchy;
  });

  function buildRecoveryNotice(baseNotice: string, recovered: Partial<StartupState>): string {
    const parts = [baseNotice];
    const extraMsg = String(recovered.message ?? '').trim();
    if (extraMsg) {
      parts.push(extraMsg);
    }
    const backup = String(recovered.backupPath ?? '').trim();
    if (backup && !extraMsg.includes(backup)) {
      parts.push(`Previous configuration was backed up to ${backup}.`);
    }
    return parts.join(' ');
  }

  async function fallbackStartupToSample() {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const recovered = await LifecycleService.ResetStartupToSample();
      const notice = buildRecoveryNotice('Recovered with built-in Sample project.', recovered);
      await onrecovered(notice);
    } catch (cause) {
      recoveryError = `Could not fall back to Sample project: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function browseStartupDatabase(target: 'project' | 'su' | 'hierarchy') {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const picked =
        typeof trackIfCancellable === 'function'
          ? await trackIfCancellable(reads, LifecycleService.ChooseStartupDatabaseFile())
          : await LifecycleService.ChooseStartupDatabaseFile();
      if (!picked) return;
      if (target === 'project') {
        recoveryProjectPath = picked;
      } else if (target === 'su') {
        recoverySUPath = picked;
        recoveryClearSU = false;
      } else {
        recoveryHierarchyPath = picked;
        recoveryClearHierarchy = false;
      }
    } catch (cause) {
      recoveryError = `File picker unavailable: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function recoverStartupPaths() {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const payload: StartupRecoveryRequest = $state.snapshot({
        projectPath: recoveryProjectPath.trim(),
        projectName: recoveryProjectName.trim(),
        suPath: recoverySUPath.trim(),
        clearSu: recoveryClearSU,
        hierarchyPath: recoveryHierarchyPath.trim(),
        clearHierarchy: recoveryClearHierarchy,
      });
      const recovered = await LifecycleService.RecoverStartupWithPaths(payload);
      const baseNotice = derivedMeta.supportDatabaseIssue
        ? 'Support database restored and project opened cleanly.'
        : derivedMeta.hasMissingDatabase
          ? 'Relocated project opened cleanly.'
          : 'Saved settings repaired and project opened cleanly.';
      const notice = buildRecoveryNotice(baseNotice, recovered);
      await onrecovered(notice);
    } catch (cause) {
      const prefix = derivedMeta.supportDatabaseIssue
        ? 'Could not restore support database'
        : derivedMeta.hasMissingDatabase
          ? 'Could not open relocated database'
          : 'Could not open project';
      recoveryError = `${prefix}: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }

  async function repairSupportAndOpenProject() {
    if (recoveryWorking || busy) return;
    if (!recoveryProjectPath.trim() || derivedMeta.hasMissingDatabase) {
      await fallbackStartupToSample();
      return;
    }
    await recoverStartupPaths();
  }
</script>

{#snippet projectSelectionFormFields(submitLabel: string)}
  <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
    <label for="recovery-project-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
      Project database (.db) path
      <input
        id="recovery-project-path"
        class="px-2.5 py-1.5 border rounded text-xs font-mono"
        bind:value={recoveryProjectPath}
        placeholder="/path/to/Project.db"
        disabled={recoveryWorking || busy}
      />
    </label>
    <button
      type="button"
      data-startup-browse-project
      disabled={recoveryWorking || busy}
      class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-vpro-surface-subtle disabled:opacity-50"
      onclick={() => void browseStartupDatabase('project')}
    >
      Browse .db...
    </button>
  </div>
  <label for="recovery-project-name" class="flex flex-col gap-1 text-xs font-medium max-w-xs">
    Project name inside file (optional when single-project .db)
    <input
      id="recovery-project-name"
      class="px-2.5 py-1.5 border rounded text-xs"
      bind:value={recoveryProjectName}
      placeholder={startupFailure.configuredProject || 'Auto-detect'}
      disabled={recoveryWorking || busy}
    />
  </label>

  <div class="flex flex-wrap gap-4 text-xs">
    <label class="inline-flex items-center gap-1.5">
      <input type="checkbox" bind:checked={recoveryClearSU} disabled={recoveryWorking || busy} />
      <span>Reset missing Site Unit (SU) selection to None</span>
    </label>
    <label class="inline-flex items-center gap-1.5">
      <input type="checkbox" bind:checked={recoveryClearHierarchy} disabled={recoveryWorking || busy} />
      <span>Reset missing Hierarchy selection to None</span>
    </label>
  </div>

  {#if !recoveryClearSU && hasConfiguredContextSelection(startupFailure.configuredSu)}
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
      <label for="recovery-su-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
        Site Unit database (.db) path ({startupFailure.configuredSu})
        <input
          id="recovery-su-path"
          class="px-2.5 py-1.5 border rounded text-xs font-mono"
          bind:value={recoverySUPath}
          disabled={recoveryWorking || busy}
        />
      </label>
      <button
        type="button"
        disabled={recoveryWorking || busy}
        class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-vpro-surface-subtle disabled:opacity-50"
        onclick={() => void browseStartupDatabase('su')}
      >
        Browse SU .db...
      </button>
    </div>
  {/if}

  {#if !recoveryClearHierarchy && hasConfiguredContextSelection(startupFailure.configuredHierarchy)}
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end">
      <label for="recovery-hierarchy-path" class="sm:col-span-2 flex flex-col gap-1 text-xs font-medium">
        Hierarchy database (.db) path ({startupFailure.configuredHierarchy})
        <input
          id="recovery-hierarchy-path"
          class="px-2.5 py-1.5 border rounded text-xs font-mono"
          bind:value={recoveryHierarchyPath}
          disabled={recoveryWorking || busy}
        />
      </label>
      <button
        type="button"
        disabled={recoveryWorking || busy}
        class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-vpro-surface-subtle disabled:opacity-50"
        onclick={() => void browseStartupDatabase('hierarchy')}
      >
        Browse Hierarchy .db...
      </button>
    </div>
  {/if}

  <div>
    <button
      type="submit"
      data-startup-relocate-open
      disabled={recoveryWorking || busy || !recoveryProjectPath.trim()}
      class="px-3.5 py-1.5 rounded border border-vpro-navy text-vpro-navy text-xs font-semibold hover:bg-vpro-surface-subtle disabled:opacity-50"
    >
      {recoveryWorking ? 'Opening...' : submitLabel}
    </button>
  </div>
{/snippet}

<section class="startup-recovery space-y-4 p-5 border rounded bg-white max-w-3xl" role="alert" data-startup-recovery>
  <div>
    <div class="eyebrow">Startup Recovery</div>
    <h1 class="text-xl font-semibold">
      {derivedMeta.supportDatabaseIssue
        ? 'Shared support database could not be opened'
        : 'Saved context could not be opened'}
    </h1>
  </div>
  <p class="text-sm">{derivedMeta.formattedMessage}</p>

  {#if derivedMeta.supportDatabaseIssue}
    {@const issue = derivedMeta.supportDatabaseIssue}
    {@const targetLabel = issue.allFileNames.length > 1 ? 'support databases' : issue.fileName}
    <div
      class="p-3.5 border border-vpro-gold rounded bg-vpro-warning-bg space-y-1.5 text-xs text-vpro-ink"
      data-startup-support-db-callout
    >
      <div class="font-semibold">
        Affected support database: <code>{issue.fileName}</code> ({issue.roleDescription})
      </div>
      {#if issue.filePath}
        <div>
          File location: <code class="break-all">{issue.filePath}</code>
        </div>
      {/if}
      {#if issue.hasPersonalUserEntries}
        <p class="text-vpro-ink-secondary">
          <code>VUser.db</code> stores custom user species codes and personal site unit lists. Before restoring a clean
          built-in copy, VPro saves your existing file untouched as
          <code>VUser.corrupt-&lt;timestamp&gt;.db</code> in the same folder so no custom entries are silently lost.
        </p>
      {:else}
        <p class="text-vpro-ink-secondary">
          Before restoring a clean built-in copy, VPro saves the unreadable file untouched as
          <code>{issue.role}.corrupt-&lt;timestamp&gt;.db</code> in the same folder.
        </p>
      {/if}
    </div>
  {/if}

  <p class="text-xs text-vpro-ink-secondary">
    Your saved preferences in <code>{startupFailure.configPath}</code> and existing project files have not been modified yet.
    Choose an option below — VPro will automatically save a backup copy before making any changes.
  </p>
  {#if recoveryError}
    <p role="alert" class="error text-xs" data-startup-recovery-error>{recoveryError}</p>
  {/if}

  {#if derivedMeta.supportDatabaseIssue}
    {@const issue = derivedMeta.supportDatabaseIssue}
    {@const targetLabel = issue.allFileNames.length > 1 ? 'support databases' : issue.fileName}
    <div class="p-3.5 border rounded bg-vpro-surface-subtle space-y-2" data-startup-repair-support-panel>
      <h2 class="text-sm font-semibold">Option 1: Back up &amp; restore {targetLabel}</h2>
      <p class="text-xs text-vpro-ink-secondary">
        Saves a timestamped backup copy of the unreadable support database, installs a clean built-in copy, and opens
        {#if recoveryProjectPath.trim() && !derivedMeta.hasMissingDatabase}
          your saved <strong>{startupFailure.configuredProject || 'Sample'}</strong> project with your preferences intact.
        {:else}
          VPro with the built-in <strong>Sample</strong> project.
        {/if}
        None of your existing <code>.db</code> project files are deleted or altered.
      </p>
      <button
        type="button"
        data-startup-repair-support
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded bg-vpro-navy text-white text-xs font-semibold hover:bg-vpro-navy-dark disabled:opacity-50"
        onclick={() => void repairSupportAndOpenProject()}
      >
        {recoveryWorking ? 'Restoring support database...' : `Back up & restore ${targetLabel} & open project`}
      </button>
    </div>

    <div class="p-3.5 border rounded space-y-2">
      <h2 class="text-sm font-semibold">
        Option 2: Restore {targetLabel} &amp; switch to Sample project
      </h2>
      <p class="text-xs text-vpro-ink-secondary">
        Backs up both the unreadable support database and your current settings, installs a clean built-in copy, and
        opens VPro with the built-in <strong>Sample</strong> project.
      </p>
      <button
        type="button"
        data-startup-fallback-sample
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded border border-vpro-navy text-vpro-navy text-xs font-semibold hover:bg-vpro-surface-subtle disabled:opacity-50"
        onclick={() => void fallbackStartupToSample()}
      >
        {recoveryWorking ? 'Recovering...' : `Restore ${targetLabel} & Switch to Sample project`}
      </button>
    </div>

    <details class="p-3.5 border rounded" open={derivedMeta.hasMissingDatabase}>
      <summary class="text-xs font-semibold cursor-pointer select-none">
        {derivedMeta.hasMissingDatabase
          ? `Option 3: Relocate missing project database (.db) & restore ${targetLabel}`
          : 'Open a different project database (.db) file instead'}
      </summary>
      <form
        class="mt-3 space-y-3"
        onsubmit={(event) => {
          event.preventDefault();
          void recoverStartupPaths();
        }}
      >
        {@render projectSelectionFormFields(`Restore ${targetLabel} & open selected project`)}
      </form>
    </details>
  {:else}
    <div class="p-3.5 border rounded bg-vpro-surface-subtle space-y-2">
      <h2 class="text-sm font-semibold">Option 1: Open built-in Sample project</h2>
      <p class="text-xs text-vpro-ink-secondary">
        Backs up your current settings and opens VPro immediately with the built-in <strong>Sample</strong> project.
        None of your existing <code>.db</code> project files are deleted or altered.
      </p>
      <button
        type="button"
        data-startup-fallback-sample
        disabled={recoveryWorking || busy}
        class="px-3.5 py-1.5 rounded bg-vpro-navy text-white text-xs font-semibold hover:bg-vpro-navy-dark disabled:opacity-50"
        onclick={() => void fallbackStartupToSample()}
      >
        {recoveryWorking ? 'Recovering...' : 'Switch to Sample project (back up settings)'}
      </button>
    </div>

    <form
      class="p-3.5 border rounded space-y-3"
      onsubmit={(event) => {
        event.preventDefault();
        void recoverStartupPaths();
      }}
    >
      <h2 class="text-sm font-semibold">
        {derivedMeta.hasMissingDatabase
          ? 'Option 2: Relocate missing database path'
          : 'Option 2: Repair settings & open project'}
      </h2>
      {#if !derivedMeta.hasMissingDatabase}
        <p class="text-xs text-vpro-ink-secondary">
          Updates your saved preferences while keeping your valid settings and opening the selected project.
        </p>
      {/if}
      {@render projectSelectionFormFields('Update paths & open project')}
    </form>
  {/if}
</section>
