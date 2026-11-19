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
    overridePort: string | number | null | undefined;
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

<section class="overflow-hidden rounded border border-vpro-border bg-white shadow-sm" aria-label="Cloud Connection and Session Role">
  <div class="border-b-[3px] border-b-vpro-gold bg-vpro-navy px-4 py-3 text-white">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs font-semibold uppercase tracking-wider text-vpro-gold">Cloud BECMaster Sync</span>
        {#if connectionReport?.connected}
          <span class="rounded bg-vpro-success px-2 py-0.5 text-xs font-semibold text-white" data-cloud-status-badge="connected">
            Connected ({connectionReport.latencyMs} ms)
          </span>
        {:else}
          <span class="rounded bg-slate-700 px-2 py-0.5 text-xs font-semibold text-vpro-ink-muted" data-cloud-status-badge="offline">
            Offline / Unprobed
          </span>
        {/if}
        <span class="rounded bg-vpro-gold px-2 py-0.5 text-xs font-bold text-vpro-navy" data-cloud-role-badge={activeRoleMode}>
          {activeRoleMode === 'custodian' ? 'Custodian Admin' : 'Contributor'}
        </span>
        <span class="rounded border border-vpro-border-strong/50 bg-vpro-navy-dark px-2 py-0.5 font-mono text-[11px] text-vpro-ink-muted" data-cloud-env-indicator>
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
          class="rounded border border-vpro-border-strong bg-white px-2.5 py-1.5 text-xs font-semibold text-vpro-navy"
          bind:value={selectedRoleMode}
          disabled={busy || operationHeld}
        >
          <option value="contributor">Role: Contributor</option>
          <option value="custodian">Role: Custodian Admin</option>
        </select>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-vpro-gold bg-vpro-gold px-3 py-1.5 text-xs font-bold text-vpro-navy hover:bg-amber-400 disabled:opacity-50"
          onclick={onSwitchRoleAndConnect}
        >
          Test Connection / Refresh Cloud Status
        </button>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-white/70 bg-vpro-navy-dark px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-ink disabled:opacity-50"
          onclick={onSyncProvincialStandards}
        >
          Sync Provincial Standards
        </button>
      </div>
    </div>
  </div>

  <!-- Cloud Counters & Telemetry Strip -->
  <div class="grid grid-cols-2 gap-2 border-b border-vpro-border bg-vpro-surface-subtle px-4 py-2.5 text-xs sm:grid-cols-5">
    <div>
      <div class="text-[11px] text-vpro-ink-secondary">BECMaster Plots</div>
      <div class="font-mono text-sm font-bold text-vpro-navy">
        {connectionReport ? connectionReport.becmasterPlotCount.toLocaleString() : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-vpro-ink-secondary">BECMaster Veg Rows</div>
      <div class="font-mono text-sm font-bold text-vpro-navy">
        {connectionReport ? connectionReport.becmasterVegCount.toLocaleString() : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-vpro-ink-secondary">Pending Staging Queue</div>
      <div class="font-mono text-sm font-bold text-vpro-navy">
        {connectionReport ? connectionReport.pendingSubmissionCount : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-vpro-ink-secondary">Dated Snapshots</div>
      <div class="font-mono text-sm font-bold text-vpro-navy">
        {connectionReport ? `${connectionReport.snapshotCount}${connectionReport.latestSnapshotTag ? ` (${connectionReport.latestSnapshotTag})` : ''}` : '—'}
      </div>
    </div>
    <div>
      <div class="text-[11px] text-vpro-ink-secondary">Provincial Standards</div>
      <div class="font-mono text-xs font-semibold text-vpro-navy">
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
    <summary class="cursor-pointer font-semibold text-vpro-navy select-none">
      Session Credential Override (Used for This Session Only — Never Saved to Disk)
    </summary>
    <div class="mt-3 space-y-3 border-t border-vpro-border pt-3">
      <p class="text-xs text-vpro-ink-secondary">
        Credentials entered here apply strictly to the current desktop session and are never written to local configuration files or echoed after submission.
      </p>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-4">
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-host">Server Host</label>
          <input
            id="cloud-override-host"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overrideHost}
            disabled={busy || operationHeld}
            placeholder="Hostname or IPv4/IPv6"
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-port">Port</label>
          <input
            id="cloud-override-port"
            type="number"
            min="1"
            max="65535"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overridePort}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-db">Database</label>
          <input
            id="cloud-override-db"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overrideDatabase}
            disabled={busy || operationHeld}
            placeholder="becmaster"
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-ssl">SSL Mode</label>
          <select
            id="cloud-override-ssl"
            class="w-full rounded border border-vpro-border p-1.5 text-xs"
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
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-user">Contributor User</label>
          <input
            id="cloud-override-user"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overrideUser}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-password">Contributor Password</label>
          <input
            id="cloud-override-password"
            type="password"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overridePassword}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-admin-user">Custodian Admin User</label>
          <input
            id="cloud-override-admin-user"
            type="text"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overrideAdminUser}
            disabled={busy || operationHeld}
          />
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-semibold text-vpro-ink-secondary" for="cloud-override-admin-password">Custodian Admin Password</label>
          <input
            id="cloud-override-admin-password"
            type="password"
            autocomplete="off"
            class="w-full rounded border border-vpro-border p-1.5 font-mono text-xs"
            bind:value={overrideAdminPassword}
            disabled={busy || operationHeld}
          />
        </div>
      </div>

      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded bg-vpro-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
          onclick={() => onApplySessionConfig(false)}
        >
          Apply Session Override
        </button>
        <button
          type="button"
          disabled={busy || operationHeld}
          class="rounded border border-vpro-border bg-white px-3 py-1.5 text-xs font-semibold text-vpro-ink hover:bg-vpro-canvas disabled:opacity-50"
          onclick={() => onApplySessionConfig(true)}
        >
          Clear Session Override
        </button>
      </div>
    </div>
  </details>
</section>
