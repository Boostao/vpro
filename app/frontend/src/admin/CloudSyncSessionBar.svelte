<script lang="ts">
  import CloudSyncAuthPanel from './CloudSyncAuthPanel.svelte';
  import type {
    CloudConfigStatus,
    CloudConnectionReport,
    CloudRoleMode,
    PullStandardsResult,
  } from './cloudSyncWorkbench';

  let {
    busy,
    operationHeld,
    activeProject,
    activeRoleMode,
    configStatus,
    connectionReport,
    pullStandardsResult,
    error,
    selectedRoleMode = $bindable<CloudRoleMode>('contributor'),
    overrideHost = $bindable(''),
    overridePort = $bindable<string | number | null | undefined>('5432'),
    overrideDatabase = $bindable(''),
    overrideSslMode = $bindable('require'),
    overrideUser = $bindable(''),
    overridePassword = $bindable(''),
    overrideAdminUser = $bindable(''),
    overrideAdminPassword = $bindable(''),
    onswitchroleandconnect,
    onsyncstandards,
    onapplysessionconfig,
  }: {
    busy: boolean;
    operationHeld: boolean;
    activeProject: string;
    activeRoleMode: CloudRoleMode;
    configStatus: CloudConfigStatus | null;
    connectionReport: CloudConnectionReport | null;
    pullStandardsResult: PullStandardsResult | null;
    error: string | null;
    selectedRoleMode?: CloudRoleMode;
    overrideHost?: string;
    overridePort?: string | number | null | undefined;
    overrideDatabase?: string;
    overrideSslMode?: string;
    overrideUser?: string;
    overridePassword?: string;
    overrideAdminUser?: string;
    overrideAdminPassword?: string;
    onswitchroleandconnect: () => void;
    onsyncstandards: () => void;
    onapplysessionconfig: (clearOverrides?: boolean) => void;
  } = $props();
</script>

<div
  data-workbench-sticky-bar
  class="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-2 rounded-t border-b border-vpro-border bg-white/95 px-3 py-2 backdrop-blur-xs"
>
  <div class="flex flex-wrap items-center gap-2 text-xs text-vpro-ink">
    <span class="font-semibold text-vpro-navy">BECMaster Cloud Sync</span>
    <span class="rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] text-vpro-navy">
      {activeRoleMode === 'custodian' ? 'Custodian Admin' : 'Contributor'}
    </span>
    <span class="text-vpro-ink-secondary">
      {connectionReport?.connected ? `Connected (${connectionReport.database})` : 'Offline / Unprobed'}
    </span>
    {#if activeProject}
      <span class="rounded bg-vpro-canvas px-2 py-0.5 font-mono text-[11px] text-vpro-ink-secondary">
        Project: {activeProject}
      </span>
    {/if}
  </div>
  <div class="flex flex-wrap items-center gap-2">
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded bg-vpro-navy px-2.5 py-1 text-xs font-semibold text-white hover:bg-vpro-navy-dark disabled:opacity-50"
      onclick={onswitchroleandconnect}
    >
      Test Connection
    </button>
    <button
      type="button"
      disabled={busy || operationHeld}
      class="rounded border border-vpro-navy bg-white px-2.5 py-1 text-xs font-semibold text-vpro-navy hover:bg-vpro-surface-subtle disabled:opacity-50"
      onclick={onsyncstandards}
    >
      Sync Standards
    </button>
  </div>
</div>

<CloudSyncAuthPanel
  {busy}
  {operationHeld}
  {activeRoleMode}
  {configStatus}
  {connectionReport}
  {pullStandardsResult}
  bind:selectedRoleMode
  bind:overrideHost
  bind:overridePort
  bind:overrideDatabase
  bind:overrideSslMode
  bind:overrideUser
  bind:overridePassword
  bind:overrideAdminUser
  bind:overrideAdminPassword
  onSwitchRoleAndConnect={onswitchroleandconnect}
  onSyncProvincialStandards={onsyncstandards}
  onApplySessionConfig={onapplysessionconfig}
/>

{#if error}
  <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">{error}</p>
{/if}
