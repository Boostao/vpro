<script lang="ts">
  import type {
    CloudConfigStatus,
    CloudConnectionReport,
    CloudRoleMode,
    PullStandardsResult,
  } from './cloudSyncWorkbench';

  interface Props {
    busy: boolean;
    operationHeld: boolean;
    activeRoleMode: CloudRoleMode;
    configStatus: CloudConfigStatus | null;
    connectionReport: CloudConnectionReport | null;
    pullStandardsResult: PullStandardsResult | null;
    selectedRoleMode: CloudRoleMode;
    overrideHost: string;
    overridePort: string;
    overrideDatabase: string;
    overrideSslMode: string;
    overrideUser: string;
    overridePassword: string;
    overrideAdminUser: string;
    overrideAdminPassword: string;
    onSwitchRoleAndConnect: () => void;
    onSyncProvincialStandards: () => void;
    onApplySessionConfig: (clearOverrides: boolean) => void;
  }

  let {
    busy,
    operationHeld,
    activeRoleMode,
    configStatus,
    connectionReport,
    pullStandardsResult,
    selectedRoleMode = $bindable(),
    overrideHost = $bindable(),
    overridePort = $bindable(),
    overrideDatabase = $bindable(),
    overrideSslMode = $bindable(),
    overrideUser = $bindable(),
    overridePassword = $bindable(),
    overrideAdminUser = $bindable(),
    overrideAdminPassword = $bindable(),
    onSwitchRoleAndConnect,
    onSyncProvincialStandards,
    onApplySessionConfig,
  }: Props = $props();
</script>

<section class="overflow-hidden rounded border border-slate-300 bg-white shadow-sm" aria-label="Cloud Connection and Session Role">
  <div class="border-b-[3px] border-b-[#FCBA19] bg-[#003366] px-4 py-3 text-white">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs font-semibold uppercase tracking-wider text-[#FCBA19]">Cloud BECMaster Sync</span>
        {#if connectionReport?.connected}
          <span class="rounded bg-[#2E8540] px-2 py-0.5 text-xs font-semibold text-white" data-cloud-status-badge="connected">
            Connected ({connectionReport.latencyMs} ms)
          </span>
        {:else}
          <span class="rounded bg-slate-700 px-2 py-0.5 text-xs font-semibold text-slate-100" data-cloud-status-badge="offline">
            Offline / Unprobed
          </span>
        {/if}
        <span class="rounded bg-[#FCBA19] px-2 py-0.5 text-xs font-bold text-[#003366]" data-cloud-role-badge={activeRoleMode}>
          {activeRoleMode === 'custodian' ? 'Custodian Admin' : 'Contributor'}
        </span>
        <span class="rounded border border-slate-400/50 bg-[#002244] px-2 py-0.5 font-mono text-[11px] text-slate-200" data-cloud-env-indicator>
          {#if configStatus?.sessionOverride}
            Session Override ({configStatus.configSource})
          {:else if configStatus?.envFileDetected}
            becmaster.env detected ({configStatus.configSource})
          {:else if configStatus}
            Source: {configStatus.configSource || 'unconfigured'}
          {:else}
            Local config unprobed
          {/if}
        </span>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <label class="sr-only" for="cloud-role-mode-select">Active Cloud Role</label>
        <select
          id="cloud-role-mode-select"
          class="rounded border border-slate-400 bg-white px-2.5 py-1.5 text-xs font-semibold text-[#003366]"
          bind:value={selectedRoleMode}
          disabled={busy || operationHeld}
        >
          <option value="contributor">Role: Contributor</option>
          <option value="custodian">Role: Custodian Admin</option>
        </select>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-[#FCBA19] bg-[#FCBA19] px-3 py-1.5 text-xs font-bold text-[#003366] hover:bg-amber-400 disabled:opacity-50"
          onclick={onSwitchRoleAndConnect}
        >
          Test Connection / Refresh Cloud Status
        </button>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-white/70 bg-[#002244] px-3 py-1.5 text-xs font-semibold text-white hover:bg-slate-800 disabled:opacity-50"
          onclick={onSyncProvincialStandards}
        >
          Sync Provincial Standards
        </button>
      </div>
    </div>
  </div>

  <!-- Cloud Counters & Telemetry Strip -->
  <div class="grid grid-cols-2 gap-2 border-b border-slate-200 bg-slate-50 px-4 py-2.5 text-xs sm:grid-cols-5">
    <div>
      <div class="text-[11px] text-slate-600">BECMaster Plots</div>
      <div class="font-mono text-sm font-bold text-[#003366]">
        {connectionReport ? connectionReport.becmasterPlotCount.toLocaleString() : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-slate-600">BECMaster Veg Rows</div>
      <div class="font-mono text-sm font-bold text-[#003366]">
        {connectionReport ? connectionReport.becmasterVegCount.toLocaleString() : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-slate-600">Pending Staging Queue</div>
      <div class="font-mono text-sm font-bold text-[#003366]">
        {connectionReport ? connectionReport.pendingSubmissionCount : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-slate-600">Dated Snapshots</div>
      <div class="font-mono text-sm font-bold text-[#003366]">
        {connectionReport ? `${connectionReport.snapshotCount}${connectionReport.latestSnapshotTag ? ` (${connectionReport.latestSnapshotTag})` : ''}` : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-slate-600">Provincial Standards</div>
      <div class="font-mono text-xs font-semibold text-[#003366]">
        {#if connectionReport?.activeStandardsRelease}
          {connectionReport.activeStandardsRelease} (BEC v{connectionReport.activeBecVersion ?? '?'} / Taxa v{connectionReport.activeTaxonomyVersion ?? '?'})
        {:else if pullStandardsResult}
          {pullStandardsResult.releaseId} (BEC v{pullStandardsResult.becVersion} / Taxa v{pullStandardsResult.taxonomyVersion})
        {:else}
          —
        {/if}
      </div>
    </div>
  </div>

  <!-- Collapsible Session Credential Override Panel -->
  <details class="px-4 py-2.5 text-xs" data-session-override-panel>
    <summary class="cursor-pointer font-semibold text-[#003366] select-none">
      Session Credential Override (In-Memory Only — Never Persisted to Disk)
    </summary>
    <div class="mt-3 space-y-3 border-t border-slate-200 pt-3">
      <p class="text-xs text-slate-600">
        Credentials entered here apply strictly to the current desktop memory session and are never written to <span class="font-mono">config.yml</span> or echoed after submission.
      </p>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-4">
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-host">PostgreSQL Host</label>
          <input
            id="cloud-override-host"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overrideHost}
            disabled={busy || operationHeld}
            placeholder="Hostname or IPv4/IPv6"
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-port">Port</label>
          <input
            id="cloud-override-port"
            type="number"
            min="1"
            max="65535"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overridePort}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-db">Database</label>
          <input
            id="cloud-override-db"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overrideDatabase}
            disabled={busy || operationHeld}
            placeholder="becmaster"
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-ssl">SSL Mode</label>
          <select
            id="cloud-override-ssl"
            class="w-full rounded border border-slate-300 p-1.5 text-xs"
            bind:value={overrideSslMode}
            disabled={busy || operationHeld}
          >
            <option value="require">require</option>
            <option value="verify-full">verify-full</option>
            <option value="verify-ca">verify-ca</option>
            <option value="prefer">prefer</option>
            <option value="disable">disable</option>
          </select>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-4">
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-user">Contributor User</label>
          <input
            id="cloud-override-user"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overrideUser}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-password">Contributor Password</label>
          <input
            id="cloud-override-password"
            type="password"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overridePassword}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-admin-user">Custodian Admin User</label>
          <input
            id="cloud-override-admin-user"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overrideAdminUser}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-slate-700" for="cloud-override-admin-password">Custodian Admin Password</label>
          <input
            id="cloud-override-admin-password"
            type="password"
            autocomplete="off"
            class="w-full rounded border border-slate-300 p-1.5 font-mono text-xs"
            bind:value={overrideAdminPassword}
            disabled={busy || operationHeld}
          />
        </div>
      </div>

      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded bg-[#003366] px-3 py-1.5 text-xs font-semibold text-white hover:bg-[#002244] disabled:opacity-50"
          onclick={() => onApplySessionConfig(false)}
        >
          Apply Session Override
        </button>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-800 hover:bg-slate-100 disabled:opacity-50"
          onclick={() => onApplySessionConfig(true)}
        >
          Clear Session Override
        </button>
      </div>
    </div>
  </details>
</section>
