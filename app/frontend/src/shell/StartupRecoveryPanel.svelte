<script lang="ts" module>
  import type { StartupState } from '../../bindings/github.com/boostao/vpro/app';

  const FRIENDLY_CONFIG_FIELD_LABELS: Record<string, string> = {
    'Current.CoordMethod': 'Coordinate display format',
    'Current.AssignedSuSource': 'Working Unit source',
    'Current.ProjectIdSource': 'Project ID source',
    'Current.CurrProject': 'Active Project',
    'Current.CurrPlotlist': 'Active Site Unit list',
    'Current.CurrHierarchy': 'Active Hierarchy',
    'Current.ProjectPath': 'Project file path',
    'Current.SUPath': 'Site Unit file path',
    'Current.HierarchyPath': 'Hierarchy file path',
    'Current.User': 'User name',
    'Audit.AuditStrength': 'Audit tracking level',
    'Desktop.SchemaVersion': 'Settings version',
  };

  const MISSING_FILE_REASON_RE =
    /(not found|no such file|cannot find|unavailable|missing|does not exist)/i;

  export function hasConfiguredContextSelection(name: string | null | undefined): boolean {
    const trimmed = String(name ?? '').trim();
    return trimmed !== '' && trimmed !== 'None';
  }

  export function formatStartupError(raw: unknown): string {
    let msg = String(raw ?? '').trim();
    if (!msg) return '';

    const prefixes = ['RuntimeError:', 'Error:', 'validate recovered configuration:'];
    let stripped = true;
    while (stripped) {
      stripped = false;
      for (const prefix of prefixes) {
        if (msg.startsWith(prefix)) {
          msg = msg.slice(prefix.length).trim();
          stripped = true;
        }
      }
    }

    const legacyConflictMatch =
      /^legacy JSON conflicts with explicit YAML ([^;]+); both files were retained$/i.exec(msg);
    if (legacyConflictMatch) {
      const rawKey = legacyConflictMatch[1].trim();
      const friendly = FRIENDLY_CONFIG_FIELD_LABELS[rawKey] ?? rawKey;
      return `An older VPro selection file conflicts with your saved ${friendly} setting. Both files were kept unchanged.`;
    }

    const legacyChangedMatch =
      /^legacy (.+) changed after migration; YAML and JSON were retained for explicit resolution$/i.exec(
        msg
      );
    if (legacyChangedMatch) {
      return `An older VPro settings file (${legacyChangedMatch[1].trim()}) changed after your preferences were upgraded. Both files were kept unchanged so you can confirm which project to open.`;
    }

    if (msg === 'Current.CoordMethod must be an integer from 1 to 3') {
      return 'Saved Coordinate display format setting could not be read (expected Decimal Degrees, Degrees-Minutes, or Degrees-Minutes-Seconds).';
    }
    if (msg === 'Current.AssignedSuSource must be an integer from 1 to 3') {
      return 'Saved Working Unit source setting could not be read.';
    }
    if (msg === 'Audit.AuditStrength must be an integer from 0 to 3') {
      return 'Saved Audit tracking level setting could not be read.';
    }
    if (msg === 'Desktop.SchemaVersion must be an integer from 1 to 1') {
      return 'Saved settings version is not supported by this release of VPro.';
    }
    if (msg === 'Current.User must not be empty') {
      return 'Saved User name must not be empty.';
    }

    for (const [rawKey, friendly] of Object.entries(FRIENDLY_CONFIG_FIELD_LABELS)) {
      if (msg.includes(rawKey)) {
        msg = msg.replaceAll(rawKey, friendly);
      }
    }

    msg = msg
      .replaceAll(
        'configured context could not be opened; YAML was retained: ',
        'Your saved project or support databases could not be opened (your settings file was kept unchanged): '
      )
      .replaceAll('; YAML selection was retained', ' (your saved settings were kept unchanged)')
      .replaceAll('; YAML was retained', ' (your saved settings were kept unchanged)');

    return msg;
  }

  export function isDatabasePathMissing(
    failure: Partial<StartupState> | null | undefined,
    target: 'project' | 'su' | 'hierarchy'
  ): boolean {
    if (!failure) return false;
    const msg = String(failure.message ?? '');

    if (target === 'su') {
      if (!hasConfiguredContextSelection(failure.configuredSu)) {
        return false;
      }
      const suPath = String(failure.suPath ?? '').trim();
      if (
        /Configured Site Unit database was not found|Site Unit database unavailable|SU database unavailable/i.test(
          msg
        )
      ) {
        return true;
      }
      if (suPath !== '' && msg.includes(suPath) && MISSING_FILE_REASON_RE.test(msg)) {
        return true;
      }
      return false;
    }

    if (target === 'hierarchy') {
      if (!hasConfiguredContextSelection(failure.configuredHierarchy)) {
        return false;
      }
      const hierPath = String(failure.hierarchyPath ?? '').trim();
      if (
        /Configured Hierarchy database was not found|Hierarchy database unavailable|configured hierarchy .* unavailable/i.test(
          msg
        )
      ) {
        return true;
      }
      if (hierPath !== '' && msg.includes(hierPath) && MISSING_FILE_REASON_RE.test(msg)) {
        return true;
      }
      return false;
    }

    const projPath = String(failure.projectPath ?? '').trim();
    if (projPath === '') {
      return true;
    }
    if (
      /Configured project database was not found|configured project .* is unavailable|project database unavailable|external project\/SU path/i.test(
        msg
      )
    ) {
      return true;
    }
    if (msg.includes(projPath) && MISSING_FILE_REASON_RE.test(msg)) {
      return true;
    }
    return false;
  }

  export interface InitialRecoveryDraft {
    projectPath: string;
    projectName: string;
    suPath: string;
    clearSu: boolean;
    hierarchyPath: string;
    clearHierarchy: boolean;
    hasMissingDatabase: boolean;
    formattedMessage: string;
  }

  export function deriveInitialRecoveryDraft(
    failure: Partial<StartupState> | null | undefined
  ): InitialRecoveryDraft {
    const clearSu = isDatabasePathMissing(failure, 'su');
    const clearHierarchy = isDatabasePathMissing(failure, 'hierarchy');
    const projectMissing = isDatabasePathMissing(failure, 'project');
    return {
      projectPath: String(failure?.projectPath ?? ''),
      projectName: String(failure?.configuredProject ?? ''),
      suPath: String(failure?.suPath ?? ''),
      clearSu,
      hierarchyPath: String(failure?.hierarchyPath ?? ''),
      clearHierarchy,
      hasMissingDatabase: projectMissing || clearSu || clearHierarchy,
      formattedMessage: formatStartupError(failure?.message ?? ''),
    };
  }
</script>

<script lang="ts">
  import { untrack } from 'svelte';
  import {
    LifecycleService,
    type StartupRecoveryRequest,
  } from '../../bindings/github.com/boostao/vpro/app';

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

  async function fallbackStartupToSample() {
    if (recoveryWorking || busy) return;
    recoveryWorking = true;
    recoveryError = '';
    try {
      const recovered = await LifecycleService.ResetStartupToSample();
      const notice = recovered.backupPath
        ? `Recovered with built-in Sample project. Previous configuration was backed up to ${recovered.backupPath}.`
        : 'Recovered with built-in Sample project.';
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
      const picked = await LifecycleService.ChooseStartupDatabaseFile();
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
      const baseNotice = derivedMeta.hasMissingDatabase
        ? 'Relocated project opened cleanly.'
        : 'Saved settings repaired and project opened cleanly.';
      const notice = recovered.backupPath
        ? `${baseNotice} Previous configuration was backed up to ${recovered.backupPath}.`
        : baseNotice;
      await onrecovered(notice);
    } catch (cause) {
      const prefix = derivedMeta.hasMissingDatabase
        ? 'Could not open relocated database'
        : 'Could not open project';
      recoveryError = `${prefix}: ${formatStartupError(cause)}`;
    } finally {
      recoveryWorking = false;
    }
  }
</script>

<section class="startup-recovery space-y-4 p-5 border rounded bg-white max-w-3xl" role="alert" data-startup-recovery>
  <div>
    <div class="eyebrow">Startup Recovery</div>
    <h1 class="text-xl font-semibold">Saved context could not be opened</h1>
  </div>
  <p class="text-sm">{derivedMeta.formattedMessage}</p>
  <p class="text-xs text-slate-600">
    Your saved preferences in <code>{startupFailure.configPath}</code> and existing project files have not been modified yet.
    Choose an option below — VPro will automatically save a backup copy of your current settings before making any changes.
  </p>
  {#if recoveryError}
    <p role="alert" class="error text-xs" data-startup-recovery-error>{recoveryError}</p>
  {/if}

  <div class="p-3.5 border rounded bg-slate-50 space-y-2">
    <h2 class="text-sm font-semibold">Option 1: Open built-in Sample project</h2>
    <p class="text-xs text-slate-700">
      Backs up your current settings and opens VPro immediately with the built-in <strong>Sample</strong> project.
      None of your existing <code>.db</code> project files are deleted or altered.
    </p>
    <button
      type="button"
      data-startup-fallback-sample
      disabled={recoveryWorking || busy}
      class="px-3.5 py-1.5 rounded bg-[#003366] text-white text-xs font-semibold hover:bg-[#002244] disabled:opacity-50"
      onclick={() => void fallbackStartupToSample()}
    >
      {recoveryWorking ? 'Recovering...' : 'Switch to Sample project (back up settings)'}
    </button>
  </div>

  <form
    class="p-3.5 border rounded space-y-3"
    onsubmit={(event) => { event.preventDefault(); void recoverStartupPaths(); }}
  >
    <h2 class="text-sm font-semibold">
      {derivedMeta.hasMissingDatabase
        ? 'Option 2: Relocate missing database path'
        : 'Option 2: Repair settings & open project'}
    </h2>
    {#if !derivedMeta.hasMissingDatabase}
      <p class="text-xs text-slate-700">
        Updates your saved preferences while keeping your valid settings and opening the selected project.
      </p>
    {/if}
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
        class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
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
          class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
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
          class="px-3 py-1.5 border rounded text-xs font-medium hover:bg-slate-50 disabled:opacity-50"
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
        class="px-3.5 py-1.5 rounded border border-[#003366] text-[#003366] text-xs font-semibold hover:bg-slate-50 disabled:opacity-50"
      >
        {recoveryWorking ? 'Opening...' : 'Update paths & open project'}
      </button>
    </div>
  </form>
</section>
