<script lang="ts">
  import { onMount, onDestroy, untrack, type Snippet } from 'svelte';
  import { SpatialService, CoordinateMode, type FS882Header } from '../../bindings/github.com/boostao/vpro/app';
  import { ReadRequests, formatError, trackIfCancellable } from '../shared/readRequests';
  import type { PaperControl } from './paperLayout';
  import {
    CoordinateEditor,
    coordinateSession,
    rememberCoordinateSession,
    coordinateBusy,
    coordinateControls,
    coordinateOptions,
    type CoordinateDisplayMode,
    type CoordinateAxis,
  } from './coordinateEditor';
  import { createSpatialCoordinatePort, projectNAD83UTMZoneToLatLon } from './coordinateConversion';

  let {
    draft = $bindable(),
    mode = $bindable(),
    controls,
    position,
    capabilities,
    disabled,
    onchange,
    onerror,
    onvalidation,
    onbusy,
    children,
  }: {
    draft: FS882Header;
    mode: CoordinateDisplayMode;
    controls: PaperControl[];
    position: (control: PaperControl) => string;
    capabilities: Record<string, boolean | undefined>;
    disabled: boolean;
    onchange: () => void;
    onerror: (message: string) => void;
    onvalidation: (axis: CoordinateAxis, message: string | null) => void;
    onbusy?: (busy: boolean) => void;
    children: Snippet<[Snippet<[PaperControl?]>]>;
  } = $props();
  const axes = ['latitude', 'longitude'] as const;
  const radioGroup = $props.id();
  let identity = untrack(() => draft);
  const busyIdentity = identity;
  const busyOwner = {};
  const reportBusy = untrack(() => onbusy);
  const coordReads = new ReadRequests();
  const auto1Reads = new ReadRequests();
  const editor = new CoordinateEditor(
    createSpatialCoordinatePort(SpatialService, CoordinateMode, coordReads),
    {
      state: (next) => {
        view = next;
        mode = next.mode;
        rememberCoordinateSession(identity, next);
      },
      busy: (value) => reportBusy?.(coordinateBusy(busyIdentity, busyOwner, value)),
      dirty: () => onchange(),
      value: (axis, value) => {
        draft[axis] = value;
      },
      validation: (axis, message) => onvalidation(axis, message),
      error: (message) => onerror(message),
    },
    coordinateSession(identity)
  );
  let view = $state(editor.snapshot());
  let auto1Busy = $state(false);
  let auto1Summary = $state('');
  let auto1OutOfBounds = $state(false);
  let auto1Generation = 0;
  const invalid = $derived(Object.values(view.axes).some((axis) => axis.error !== null));
  function readonly(axis: CoordinateAxis) {
    return disabled || capabilities[axis] !== true || !view.ready || !view.axes[axis].ready;
  }
  async function runAuto1CoordinateAttribution() {
    if (disabled || view.busy || invalid) return;
    auto1Reads.cancelAll();
    const targetDraft = identity;
    const gen = (auto1Generation += 1);
    auto1Busy = true;
    auto1Summary = '';
    auto1OutOfBounds = false;
    reportBusy?.(coordinateBusy(busyIdentity, busyOwner, true));
    try {
      let lat = targetDraft.latitude;
      let lon = targetDraft.longitude;
      let changed = false;

      if (
        lat === null &&
        lon === null &&
        targetDraft.utmZone &&
        targetDraft.easting !== null &&
        targetDraft.northing !== null
      ) {
        const projected = await projectNAD83UTMZoneToLatLon(
          SpatialService,
          targetDraft.utmZone,
          targetDraft.easting,
          targetDraft.northing,
          true,
          auto1Reads
        );
        if (gen !== auto1Generation || identity !== targetDraft) return;
        lat = projected.latitude;
        lon = projected.longitude;
        if (capabilities.latitude === true) {
          targetDraft.latitude = lat;
          changed = true;
        }
        if (capabilities.longitude === true) {
          targetDraft.longitude = lon;
          changed = true;
        }
        editor.syncDraft(targetDraft.latitude, targetDraft.longitude, targetDraft);
      }

      if (lat === null || lon === null) {
        throw new Error('Enter Latitude/Longitude or NAD83 UTM Zone/Easting/Northing before running map lookup.');
      }

      const suggestion = await trackIfCancellable(auto1Reads, SpatialService.SuggestSpatialAttributes(lat, lon));
      if (gen !== auto1Generation || identity !== targetDraft || !suggestion) return;

      if (suggestion.longitudeSignFlipped && capabilities.longitude === true) {
        targetDraft.longitude = suggestion.normalizedLon;
        editor.syncDraft(targetDraft.latitude, targetDraft.longitude, targetDraft);
        changed = true;
      }
      if (suggestion.utmZone > 0) {
        const zText = String(suggestion.utmZone);
        const eVal = Math.round(suggestion.utmEasting * 10) / 10;
        const nVal = Math.round(suggestion.utmNorthing * 10) / 10;
        if (capabilities.utmZone === true && !targetDraft.utmZone) {
          targetDraft.utmZone = zText;
          changed = true;
        }
        if (capabilities.easting === true && targetDraft.easting === null) {
          targetDraft.easting = eVal;
          changed = true;
        }
        if (capabilities.northing === true && targetDraft.northing === null) {
          targetDraft.northing = nVal;
          changed = true;
        }
      }
      if (suggestion.ntsMapSheet && capabilities.mapSheet === true && !targetDraft.mapSheet) {
        targetDraft.mapSheet = suggestion.ntsMapSheet;
        changed = true;
      }
      if (suggestion.ecosection && capabilities.ecosection === true && !targetDraft.ecosection) {
        targetDraft.ecosection = suggestion.ecosection;
        changed = true;
      }
      if (suggestion.fsRegionDistrict && capabilities.fsRegionDistrict === true && !targetDraft.fsRegionDistrict) {
        targetDraft.fsRegionDistrict = suggestion.fsRegionDistrict;
        changed = true;
      }
      if (changed) onchange();

      const parts = [
        suggestion.gisBgc ? `GIS_BGC: ${suggestion.gisBgc}` : '',
        suggestion.utmZone > 0
          ? `NAD83 UTM ${suggestion.utmZone}: ${suggestion.utmEasting.toFixed(1)}E ${suggestion.utmNorthing.toFixed(1)}N`
          : '',
        suggestion.ecosection ? `Eco: ${suggestion.ecosection}` : '',
        suggestion.fsRegionDistrict ? `Dist: ${suggestion.fsRegionDistrict}` : '',
        suggestion.ntsMapSheet ? `Sheet: ${suggestion.ntsMapSheet}` : '',
      ].filter(Boolean);
      const diag = (suggestion.diagnostics ?? []).filter(Boolean);
      if (!suggestion.gisBgc && !suggestion.ecosection && !suggestion.fsRegionDistrict) {
        auto1OutOfBounds = true;
        const outMsg =
          diag.find((item) => /outside/i.test(item)) ??
          `Coordinates (${lat}, ${lon}) fall outside B.C. map coverage; no BGC, ecosection, or district matched.`;
        parts.unshift(`Out of B.C. bounds: ${outMsg}`);
      } else if (diag.length > 0) {
        parts.push(...diag);
      }
      auto1Summary = parts.join(' | ');
    } catch (cause) {
      if (gen === auto1Generation) {
        onerror(formatError(cause));
      }
    } finally {
      if (gen === auto1Generation) {
        auto1Busy = false;
        reportBusy?.(coordinateBusy(busyIdentity, busyOwner, view.busy));
      }
    }
  }
  $effect(() => {
    const previous = identity;
    identity = draft;
    if (previous !== draft) {
      auto1Generation += 1;
      auto1Reads.cancelAll();
      auto1Summary = '';
      auto1OutOfBounds = false;
      if (auto1Busy) {
        auto1Busy = false;
        reportBusy?.(coordinateBusy(busyIdentity, busyOwner, view.busy));
      }
    }
    editor.syncDraft(draft.latitude, draft.longitude, draft);
  });
  onMount(() => {
    void editor.initialize();
  });
  onDestroy(() => {
    auto1Generation += 1;
    auto1Reads.cancelAll();
    coordReads.cancelAll();
    editor.dispose();
  });
</script>

<div class="coordinate-toolbar" aria-label="Coordinate safety controls">
  {#if view.mode !== 'dd'}
    <span>Safety addition: explicit numeric signs; no hemisphere assumptions.</span>
    {#each axes as axis}
      <label
        >{axis === 'latitude' ? 'Latitude' : 'Longitude'} sign
        <select
          aria-label={`${axis} numeric sign`}
          value={view.axes[axis].buffers.negative ? '-' : '+'}
          disabled={readonly(axis)}
          onchange={(event) => {
            if (!readonly(axis)) editor.edit(axis, 'negative', event.currentTarget.value === '-');
          }}
        >
          <option value="+">+</option><option value="-">−</option>
        </select>
      </label>
    {/each}
  {/if}
  <button
    type="button"
    data-auto1-spatial-stamp
    disabled={disabled ||
      view.busy ||
      auto1Busy ||
      invalid ||
      (capabilities.latitude !== true && capabilities.easting !== true)}
    onclick={() => void runAuto1CoordinateAttribution()}
  >
    Project NAD83 UTM &lt;-&gt; DD &amp; Suggest BGC/Admin
  </button>
  {#if view.busy || auto1Busy}<span role="status">Preparing coordinate values…</span>{/if}
  {#if auto1Summary}<span
      role="status"
      class="auto1-summary"
      class:auto1-warning={auto1OutOfBounds}
      data-auto1-out-of-bc={auto1OutOfBounds ? 'true' : undefined}>{auto1Summary}</span
    >{/if}
  {#if (!view.ready || !view.axes.latitude.ready || !view.axes.longitude.ready) && !view.busy}<button
      type="button"
      {disabled}
      onclick={() => void editor.initialize()}>Retry coordinate display</button
    >{/if}
  {#each axes as axis}
    {#if view.axes[axis].error}<span id={`coordinate-error-${axis}`} role="alert">{view.axes[axis].error}</span>{/if}
  {/each}
</div>

{#snippet coordinateInputs(only?: PaperControl)}
  <div
    class="coordinate-inputs"
    role={only ? undefined : 'radiogroup'}
    aria-label={only ? undefined : 'Coordinate display mode'}
  >
    {#each only ? [only] : controls as control (control.controlId)}
      {@const name = control.controlName ?? ''}
      {@const mapping = coordinateControls[name]}
      {@const option = coordinateOptions[name]}
      {#if mapping && mapping.mode === view.mode}
        <input
          class="coordinate-control"
          style={position(control)}
          data-source-control={name}
          id={`header-coordinate-${name}`}
          data-column={control.column}
          type="text"
          inputmode={(mapping.part === 'degrees' && view.mode !== 'dd') ||
          (mapping.part === 'minutes' && view.mode === 'dms')
            ? 'numeric'
            : 'decimal'}
          aria-label={`${mapping.axis} ${view.mode.toUpperCase()} ${mapping.part}`}
          aria-invalid={view.axes[mapping.axis].error !== null}
          aria-describedby={view.axes[mapping.axis].error ? `coordinate-error-${mapping.axis}` : undefined}
          readonly={readonly(mapping.axis) || control.locked || !control.enabled}
          disabled={readonly(mapping.axis) || control.locked || !control.enabled}
          placeholder={capabilities[mapping.axis] !== true ? 'Pending' : ''}
          title={capabilities[mapping.axis] !== true
            ? `${mapping.axis} is unsupported by the active schema`
            : 'Raw signed coordinates are preserved; NULL requires clearing all parts'}
          value={view.axes[mapping.axis].buffers[mapping.part]}
          oninput={(event) => {
            if (!readonly(mapping.axis) && !control.locked && control.enabled)
              editor.edit(mapping.axis, mapping.part, event.currentTarget.value);
          }}
        />
      {:else if option}
        <input
          class="coordinate-control coordinate-radio"
          id={`header-coordinate-${name}`}
          style={position(control)}
          data-source-control={name}
          type="radio"
          name={`${radioGroup}-coordinate-display-mode`}
          value={option}
          checked={view.mode === option}
          aria-label={option === 'dd'
            ? 'Decimal degrees'
            : option === 'dm'
              ? 'Degrees and decimal minutes'
              : 'Degrees minutes and seconds'}
          disabled={disabled || !view.ready || view.busy || invalid || control.locked || !control.enabled}
          onchange={() => {
            if (!disabled && view.ready && !view.busy && !invalid && !control.locked && control.enabled)
              void editor.changeMode(option);
          }}
        />
      {/if}
    {/each}
  </div>
{/snippet}
{@render children(coordinateInputs)}

<style>
  .coordinate-toolbar {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
    font-size: 0.75rem;
    color: var(--vpro-ink-secondary);
  }
  .coordinate-toolbar label {
    display: flex;
    align-items: center;
    gap: 0.25rem;
  }
  .coordinate-toolbar select,
  .coordinate-toolbar button {
    border: 1px solid var(--vpro-border-strong);
    border-radius: 4px;
    background: var(--vpro-surface, white);
    color: var(--vpro-navy);
    font-weight: 500;
    padding: 0.2rem 0.5rem;
    min-height: 30px;
  }
  .coordinate-toolbar button:hover:not(:disabled) {
    background: var(--vpro-navy-tint);
    border-color: var(--vpro-navy);
  }
  .coordinate-toolbar [role='alert'] {
    color: var(--vpro-error-ink);
  }
  .auto1-warning {
    padding: 0.15rem 0.5rem;
    border-radius: 4px;
    border: 1px solid var(--vpro-warning);
    background: var(--vpro-warning-bg);
    color: var(--vpro-warning-ink);
    font-weight: 600;
  }
  .coordinate-inputs {
    display: contents;
  }
  .coordinate-control {
    box-sizing: border-box;
    width: 100%;
    min-width: 0;
    min-height: 40px;
    border: 1px solid var(--vpro-forest-border);
    border-radius: 4px;
    padding: 0.5rem 0.65rem;
    background: var(--vpro-surface, white);
    color: var(--vpro-ink);
    font: inherit;
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
    line-height: 1.4;
  }
  .coordinate-control:focus {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
  .coordinate-control:read-only {
    color: var(--vpro-ink-muted);
    background: var(--vpro-surface-subtle);
  }
  .coordinate-radio {
    margin: 0;
    padding: 0;
  }
</style>
