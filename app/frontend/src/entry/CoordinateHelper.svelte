<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { ReadRequests, formatError } from '../shared/readRequests';

  let {
    idPrefix,
    disabled = false,
    variant = 'sivi',
    defaultMode = 'dms',
    onApplyUTM,
    onApplyAxis,
  }: {
    idPrefix: string;
    disabled?: boolean;
    variant?: 'sivi' | 'two-page';
    defaultMode?: 'dm' | 'dms' | 'utm';
    onApplyUTM: (result: {
      zone: number;
      latitude: number;
      longitude: number;
      easting: number;
      northing: number;
    }) => void;
    onApplyAxis: (axis: 'latitude' | 'longitude', dd: number) => void;
  } = $props();

  let coordHelperMode = $state<'dm' | 'dms' | 'utm'>(untrack(() => defaultMode));
  let coordHelperAxis = $state<'latitude' | 'longitude'>('latitude');
  let coordDeg = $state('');
  let coordMin = $state('');
  let coordSec = $state('');
  let coordDir = $state<'N' | 'S' | 'E' | 'W'>('N');
  let utmZone = $state('');
  let utmEasting = $state('');
  let utmNorthing = $state('');
  let coordBusy = $state(false);
  let coordError = $state<string | null>(null);
  const coordReads = new ReadRequests();

  onDestroy(() => {
    coordReads.cancelAll();
  });

  async function applyCoordConversion() {
    if (disabled || coordBusy) return;
    coordBusy = true;
    coordError = null;
    try {
      const [{ SpatialService, CoordinateMode }, { projectNAD83UTMZoneToLatLon, convertDMOrDMSToDecimalDegrees }] =
        await Promise.all([import('../../bindings/github.com/boostao/vpro/app'), import('./coordinateConversion')]);
      if (coordHelperMode === 'utm') {
        const z = Number.parseInt(utmZone.trim(), 10);
        const e = Number.parseFloat(utmEasting.trim());
        const n = Number.parseFloat(utmNorthing.trim());
        if (!Number.isFinite(z) || !Number.isFinite(e) || !Number.isFinite(n)) {
          throw new Error('Enter valid NAD83 UTM Zone, Easting, and Northing.');
        }
        const projected = await projectNAD83UTMZoneToLatLon(SpatialService, z, e, n, false, coordReads);
        onApplyUTM(projected);
      } else {
        const dd = await convertDMOrDMSToDecimalDegrees(
          SpatialService,
          CoordinateMode,
          coordHelperAxis,
          coordHelperMode,
          coordDeg,
          coordMin,
          coordSec,
          coordDir,
          coordReads
        );
        onApplyAxis(coordHelperAxis, dd);
      }
    } catch (cause) {
      coordError = formatError(cause);
    } finally {
      coordBusy = false;
    }
  }
</script>

<div
  class="mt-2 rounded border border-vpro-border bg-vpro-canvas p-2.5 space-y-2 text-xs"
  data-sivi-coord-helper={variant === 'sivi' ? '' : undefined}
  data-two-page-coord-helper={variant === 'two-page' ? '' : undefined}
>
  <div class="flex flex-wrap items-center gap-2">
    <label class="font-medium" for={`${idPrefix}-coord-mode`}>Mode</label>
    <select
      id={`${idPrefix}-coord-mode`}
      class="rounded border border-vpro-border bg-white px-2 py-1"
      bind:value={coordHelperMode}
    >
      <option value="dm">DM (Deg / Min)</option>
      <option value="dms">DMS (Deg / Min / Sec)</option>
      <option value="utm">NAD83 UTM</option>
    </select>
    {#if coordHelperMode !== 'utm'}
      <select
        aria-label="Coordinate Axis"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={coordHelperAxis}
        onchange={() => {
          coordDir = coordHelperAxis === 'latitude' ? 'N' : 'W';
        }}
      >
        <option value="latitude">Latitude</option>
        <option value="longitude">Longitude</option>
      </select>
    {/if}
  </div>

  {#if coordHelperMode === 'utm'}
    <div class="grid grid-cols-1 gap-1.5 sm:grid-cols-3">
      <input
        type="text"
        aria-label="NAD83 UTM Zone"
        placeholder="Zone (e.g. 10)"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={utmZone}
      />
      <input
        type="text"
        aria-label="NAD83 UTM Easting"
        placeholder="Easting"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={utmEasting}
      />
      <input
        type="text"
        aria-label="NAD83 UTM Northing"
        placeholder="Northing"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={utmNorthing}
      />
    </div>
  {:else}
    <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
      <input
        type="text"
        aria-label="Coordinate Degrees"
        placeholder="Deg"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={coordDeg}
      />
      <input
        type="text"
        aria-label="Coordinate Minutes"
        placeholder="Min"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={coordMin}
      />
      {#if coordHelperMode === 'dms'}
        <input
          type="text"
          aria-label="Coordinate Seconds"
          placeholder="Sec"
          class="rounded border border-vpro-border bg-white px-2 py-1"
          bind:value={coordSec}
        />
      {/if}
      <select
        aria-label="Hemisphere"
        class="rounded border border-vpro-border bg-white px-2 py-1"
        bind:value={coordDir}
      >
        {#if coordHelperAxis === 'latitude'}
          <option value="N">N</option>
          <option value="S">S</option>
        {:else}
          <option value="W">W</option>
          <option value="E">E</option>
        {/if}
      </select>
    </div>
  {/if}

  {#if coordError}
    <p role="alert" class="text-vpro-error">{coordError}</p>
  {/if}
  <button
    type="button"
    class="rounded bg-vpro-navy px-2.5 py-1 text-white disabled:opacity-50"
    disabled={disabled || coordBusy}
    onclick={() => void applyCoordConversion()}
  >
    {coordBusy ? 'Converting...' : 'Apply converted coordinates'}
  </button>
</div>
