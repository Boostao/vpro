<script lang="ts">
  import { metadataCellText } from '../admin/projectMetadataEditor';
  import { siviParentSharedFieldsFor, siviParentSharedCell, siviParentSharedDirty, type SIVIParentSharedColumn,
    type SIVIParentSharedInput, type SIVIParentSharedView } from './siviParentSharedSession';
  let { view, disabled = true, canSave = false, onstage, onoperation, oncancel, onreferences, extendedShrubs = false, onExtendedShrubsChange,
    snowCoverRegime, activeLayerDepth, snowCoverRegimeDisabled = false, activeLayerDepthDisabled = false,
    snowCoverRegimeError = null, activeLayerDepthError = null, onSnowCoverRegimeChange, onActiveLayerDepthChange }: {
    view: SIVIParentSharedView; disabled?: boolean; canSave?: boolean;
    onstage: (column: SIVIParentSharedColumn, input: SIVIParentSharedInput) => void;
    onoperation: (operation: 'load' | 'save' | 'undo' | 'retain' | 'prune') => void;
    oncancel: () => void;
    onreferences?: () => void;
    extendedShrubs?: boolean;
    onExtendedShrubsChange?: (enabled: boolean) => void;
    snowCoverRegime?: string;
    activeLayerDepth?: string;
    snowCoverRegimeDisabled?: boolean;
    activeLayerDepthDisabled?: boolean;
    snowCoverRegimeError?: string | null;
    activeLayerDepthError?: string | null;
    onSnowCoverRegimeChange?: (value: string) => void;
    onActiveLayerDepthChange?: (value: string) => void;
  } = $props();
  function projectedEnvCellText(column: string): string {
    if (!view.original?.Rows[0]?.Env) return '';
    const index = view.original.EnvColumns.findIndex(col => col.name.toLowerCase() === column.toLowerCase());
    if (index < 0) return '';
    const cell = view.original.Rows[0].Env.cells[index];
    return !cell || cell.storage === 'null' ? '' : metadataCellText(cell);
  }
  const displayedSnowCoverRegime = $derived(snowCoverRegime ?? projectedEnvCellText('SnowCoverregime'));
  const displayedActiveLayerDepth = $derived(activeLayerDepth ?? projectedEnvCellText('ActiveLayerDepth'));

  let coordHelperOpen = $state(false);
  let coordHelperMode = $state<'dm' | 'dms' | 'utm'>('dms');
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

  async function applyCoordConversion() {
    if (disabled || view.busy || view.blocked || coordBusy) return;
    coordBusy = true;
    coordError = null;
    try {
      const { SpatialService, CoordinateMode } = await import('../../bindings/github.com/boostao/vpro/app');
      if (coordHelperMode === 'utm') {
        const z = Number.parseInt(utmZone.trim(), 10);
        const e = Number.parseFloat(utmEasting.trim());
        const n = Number.parseFloat(utmNorthing.trim());
        if (!Number.isFinite(z) || !Number.isFinite(e) || !Number.isFinite(n)) {
          throw new Error('Enter valid NAD83 UTM Zone, Easting, and Northing.');
        }
        const projected = await SpatialService.ProjectNAD83UTMToLatLon(z, e, n);
        onstage('Latitude', { kind: 'text', raw: String(Math.round(projected.latitude * 1e6) / 1e6) });
        onstage('Longitude', { kind: 'text', raw: String(Math.round(projected.longitude * 1e6) / 1e6) });
      } else {
        const deg = coordDeg.trim() === '' ? null : Number(coordDeg);
        const min = coordMin.trim() === '' ? null : Number(coordMin);
        const sec = coordHelperMode === 'dms' ? (coordSec.trim() === '' ? null : Number(coordSec)) : null;
        const negative = coordDir === 'S' || coordDir === 'W';
        const mode = coordHelperMode === 'dms' ? CoordinateMode.CoordinateModeDMS : CoordinateMode.CoordinateModeDM;
        const dd = await SpatialService.ConvertCoordinate(coordHelperAxis, mode, { degrees: deg, minutes: min, seconds: sec, negative });
        if (dd === null || !Number.isFinite(dd)) throw new Error('Coordinate conversion returned empty result.');
        onstage(coordHelperAxis === 'latitude' ? 'Latitude' : 'Longitude', { kind: 'text', raw: String(dd) });
      }
    } catch (cause) {
      coordError = String(cause);
    } finally {
      coordBusy = false;
    }
  }
  const groups = [
    { label: 'Plot & survey', scope: 'plot' },
    { label: 'Site description', scope: 'site' },
    { label: 'Topography & stand', scope: 'topography' },
    { label: 'TERRAIN', scope: 'terrain' },
    { label: 'SOIL', scope: 'soils' },
    { label: 'Vegetation', scope: 'veg' },
    { label: 'Notes', scope: 'notes' },
  ];
  const dirty = $derived(siviParentSharedDirty(view.drafts));
  const fields = $derived(siviParentSharedFieldsFor(Boolean(view.referencesEnabled)));
</script>

<section class="space-y-4 rounded border border-stone-200 bg-white p-4" aria-label="SIVI shared-field editor" data-sivi-shared-panel>
  <div class="flex flex-wrap items-center justify-between gap-2">
    <h3 class="font-semibold">SIVI / FS1333 shared fields</h3>
    {#if onExtendedShrubsChange}
      <label class="inline-flex items-center gap-2 text-xs font-medium">
        <input type="checkbox" data-sivi-extended-shrubs checked={extendedShrubs} disabled={view.busy}
          onchange={event => onExtendedShrubsChange(event.currentTarget.checked)} />
        Show extended shrub layers
      </label>
    {/if}
  </div>
  {#if extendedShrubs}
    <p class="text-xs text-stone-600" data-sivi-extended-summary>Extended shrub cover columns (Cover5a–Cover5c only; height fields remain disabled) and Arctic site fields (SnowCoverregime, ActiveLayerDepth) are active.</p>
    <fieldset class="space-y-2 rounded border border-stone-200 p-3" data-sivi-arctic-fields>
      <legend class="px-1 text-sm font-medium">Arctic / extended site fields</legend>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div class="min-w-0 space-y-1">
          <label for="sivi-arctic-SnowCoverregime" class="block text-sm font-medium">Snow cover regime</label>
          <input id="sivi-arctic-SnowCoverregime" data-column="SnowCoverregime" type="text"
            class="w-full rounded border p-2" value={displayedSnowCoverRegime}
            disabled={snowCoverRegimeDisabled || view.busy || view.blocked || !onSnowCoverRegimeChange}
            aria-invalid={snowCoverRegimeError ? 'true' : undefined}
            oninput={event => onSnowCoverRegimeChange?.(event.currentTarget.value)} />
          {#if snowCoverRegimeError}<p role="alert" class="text-sm text-red-700">{snowCoverRegimeError}</p>{/if}
        </div>
        <div class="min-w-0 space-y-1">
          <label for="sivi-arctic-ActiveLayerDepth" class="block text-sm font-medium">Active layer depth (cm)</label>
          <input id="sivi-arctic-ActiveLayerDepth" data-column="ActiveLayerDepth" type="text" inputmode="decimal"
            class="w-full rounded border p-2" value={displayedActiveLayerDepth}
            disabled={activeLayerDepthDisabled || view.busy || view.blocked || !onActiveLayerDepthChange}
            aria-invalid={activeLayerDepthError ? 'true' : undefined}
            oninput={event => onActiveLayerDepthChange?.(event.currentTarget.value)} />
          {#if activeLayerDepthError}<p role="alert" class="text-sm text-red-700">{activeLayerDepthError}</p>{/if}
        </div>
      </div>
    </fieldset>
  {/if}
  {#if view.error}<p role="alert" class="text-sm text-red-700">{view.error}</p>{/if}
  {#if view.referenceError}<p role="alert" data-sivi-reference-error>{view.referenceError}</p>{/if}
  {#if view.blocked}<p role="alert">Commit outcome or refresh is unresolved. Undo / reload before continuing; never replay Save.</p>{/if}
  {#if view.busy}<p role="status">Shared-field operation: {view.operation}...</p>{/if}
  <div class="flex flex-wrap gap-2">
    <button type="button" disabled={disabled || view.busy || view.blocked || dirty} onclick={() => onoperation('load')}>Load shared fields</button>
    <button type="button" disabled={disabled || !canSave || view.busy || view.blocked} onclick={() => onoperation('save')}>Save shared fields</button>
    <button type="button" disabled={view.busy} onclick={() => onoperation('undo')}>Undo / reload</button>
    {#if view.historyId}
      <button type="button" disabled={disabled || !canSave || view.busy || view.blocked || dirty} onclick={() => onoperation('retain')}>Restore (retain audits)</button>
      <button type="button" disabled={disabled || !canSave || view.busy || view.blocked || dirty} onclick={() => onoperation('prune')}>Restore (prune audits)</button>
    {/if}
    {#if view.busy && view.operation === 'read'}<button type="button" onclick={oncancel}>Cancel shared read</button>{/if}
    {#if fields.length > 32 && onreferences}
      <button type="button" disabled={disabled || view.busy || view.blocked || !view.original}
        onclick={onreferences}>Reload reference choices</button>
    {/if}
  </div>
  {#if view.original}
    {#each groups.filter(group => fields.some(field => field.policy.scope === group.scope)) as group}
      <section aria-label={group.label} class="space-y-2">
        <h4 class="font-medium">{group.label}</h4>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {#each fields.filter(field => field.policy.scope === group.scope) as field (field.column)}
            {@const original = siviParentSharedCell(view.original, field.column)}
            {@const draft = view.drafts[field.column]}
            {@const value = draft?.value ?? original}
            {@const raw = draft?.input.kind === 'text' ? draft.input.raw : value.storage === 'null' ? '' : metadataCellText(value)}
            {@const id = `sivi-shared-${field.column}`}
            {@const reference = view.references?.fields.find(row => row.column === field.column)}
            <div class="min-w-0 space-y-1" data-sivi-shared-field={field.column} data-source-control={field.controlId}>
              <label for={id} class="block text-sm font-medium">{field.label}</label>
              {#if field.policy.kind === 'memo'}
                <textarea {id} class="w-full rounded border p-2" value={raw}
                  disabled={disabled || view.busy || view.blocked} aria-invalid={Boolean(draft?.error)}
                  aria-describedby={draft?.error ? `${id}-error` : undefined}
                  oninput={event => onstage(field.column, { kind: 'text', raw: event.currentTarget.value })}></textarea>
              {:else}
                <input {id} type="text" class="w-full rounded border p-2" value={raw}
                  list={field.policy.kind === 'reference' ? `${id}-options` : undefined}
                  disabled={disabled || view.busy || view.blocked} aria-invalid={Boolean(draft?.error)}
                  aria-describedby={draft?.error ? `${id}-error` : undefined}
                  oninput={event => onstage(field.column, { kind: 'text', raw: event.currentTarget.value })} />
              {/if}
              {#if field.policy.kind === 'reference'}
                <datalist id={`${id}-options`}>
                  {#each reference?.available ? reference.choices.filter(row => row.selectable && row.code !== null) : [] as choice}
                    <option value={choice.code ?? ''} data-reference-row={choice.rowId}>{choice.description ?? '(NULL description)'}</option>
                  {/each}
                </datalist>
                {#if reference && !reference.available}
                  <p role="status" data-sivi-reference-unavailable>{reference.diagnostic}</p>
                {/if}
                {#if view.advisories?.[field.column]}
                  <p role="status" data-sivi-reference-advisory={field.column}>{view.advisories[field.column]}</p>
                {/if}
              {/if}
              <div class="flex flex-wrap gap-2 text-xs">
                <button type="button" disabled={disabled || view.busy || view.blocked}
                  onclick={() => onstage(field.column, { kind: 'clear' })}>Clear to NULL</button>
                <button type="button" disabled={disabled || view.busy || view.blocked}
                  onclick={() => onstage(field.column, { kind: 'original' })}>Retain original</button>
                {#if field.column === 'Latitude'}
                  <button type="button" data-sivi-coord-toggle
                    onclick={() => { coordHelperOpen = !coordHelperOpen; coordError = null; }}>
                    {coordHelperOpen ? 'Close DD/DM/DMS/UTM' : 'Coordinate Modes (DM/DMS/UTM)'}
                  </button>
                {/if}
                <span data-storage={value.storage}>{value.storage === 'text' && value.text === '' ? 'empty text' : value.storage}</span>
              </div>
              {#if field.column === 'Latitude' && coordHelperOpen}
                <div class="mt-2 rounded border border-[#D8D8D8] bg-[#F2F2F2] p-2.5 space-y-2 text-xs" data-sivi-coord-helper>
                  <div class="flex flex-wrap items-center gap-2">
                    <label class="font-medium" for="sivi-coord-mode">Mode</label>
                    <select id="sivi-coord-mode" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={coordHelperMode}>
                      <option value="dm">DM (Deg / Min)</option>
                      <option value="dms">DMS (Deg / Min / Sec)</option>
                      <option value="utm">NAD83 UTM</option>
                    </select>
                    {#if coordHelperMode !== 'utm'}
                      <select aria-label="Axis" class="rounded border border-[#D8D8D8] bg-white px-2 py-1"
                        bind:value={coordHelperAxis}
                        onchange={() => { coordDir = coordHelperAxis === 'latitude' ? 'N' : 'W'; }}>
                        <option value="latitude">Latitude</option>
                        <option value="longitude">Longitude</option>
                      </select>
                    {/if}
                  </div>
                  {#if coordHelperMode === 'utm'}
                    <div class="grid grid-cols-1 gap-1.5 sm:grid-cols-3">
                      <input type="text" placeholder="Zone (e.g. 10)" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={utmZone} />
                      <input type="text" placeholder="Easting" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={utmEasting} />
                      <input type="text" placeholder="Northing" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={utmNorthing} />
                    </div>
                  {:else}
                    <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
                      <input type="text" placeholder="Deg" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={coordDeg} />
                      <input type="text" placeholder="Min" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={coordMin} />
                      {#if coordHelperMode === 'dms'}
                        <input type="text" placeholder="Sec" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={coordSec} />
                      {/if}
                      <select aria-label="Hemisphere" class="rounded border border-[#D8D8D8] bg-white px-2 py-1" bind:value={coordDir}>
                        {#if coordHelperAxis === 'latitude'}
                          <option value="N">N</option><option value="S">S</option>
                        {:else}
                          <option value="W">W</option><option value="E">E</option>
                        {/if}
                      </select>
                    </div>
                  {/if}
                  {#if coordError}<p role="alert" class="text-[#D8292F]">{coordError}</p>{/if}
                  <button type="button" class="rounded bg-[#003366] px-2.5 py-1 text-white disabled:opacity-50"
                    disabled={disabled || view.busy || view.blocked || coordBusy} onclick={() => void applyCoordConversion()}>
                    {coordBusy ? 'Converting...' : 'Apply converted coordinates'}
                  </button>
                </div>
              {/if}
              {#if draft?.error}<p id={`${id}-error`} role="alert" class="text-sm text-red-700">{draft.error}</p>{/if}
            </div>
          {/each}
        </div>
      </section>
    {/each}
  {/if}
  <p class="text-xs text-stone-600">{fields.length} source-bound fields reuse storage validation and owned audited transactions.
    Explicit Save, Undo and restoration are desktop safety adaptations, not SIVI parent-event parity.
    ProjectID, source actions and XL callbacks are not part of this editor.</p>
  <p class="text-xs text-stone-600">Latitude and longitude use signed decimal degrees with changed-value limits of
    +/-90 and +/-180: a desktop safety adaptation. Source Fixed/six-decimal formatting is presentation evidence;
    editable and stored precision is not rounded. Yr. is an Admin integer, not a date or metadata update.
    Stand Age does not change Est./Meas. options.</p>
  <p class="text-xs text-stone-600">Date uses exact YYYY-MM-DD HH:MM:SS with an optional 1-9 digit fraction,
    years 0100-9999, and explicit NULL. This desktop wall-clock entry adaptation shows the full stored timestamp
    rather than source Medium Date formatting hiding time/precision. No timezone conversion, localized coercion,
    date-only completion, trimming or precision normalization is applied.</p>
  {#if fields.length > 32}
    <p class="text-xs text-stone-600">Reference suggestions preserve duplicate definitions. Only Exposure 1/2,
      Soil Drainage and Successional Status require exact listed Items; other reference fields retain physically
      valid free entry without acknowledgement. Changing BGC refreshes SubZone suggestions without clearing
      SubZone or changing Site Unit. Configured imported VLists ownership is not frozen DAO provenance.</p>
  {/if}
</section>
