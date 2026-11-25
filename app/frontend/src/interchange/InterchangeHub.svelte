<script lang="ts">
  import { onDestroy } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';
  import { defaultWebExportFilename } from '../shell/webReadOnlyShell';
  import { ReadRequests } from '../shared/readRequests';
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import { formatWebDownloadFeedback } from '../web/webMeta';
  import * as hubOps from './interchangeHub';
  import {
    defaultInterchangeHubPort,
    validateTargetProjectName,
    type FileDialogFilter,
    type InterchangeHubPort,
    type LumpTableSummary,
  } from './interchangeHub';
  import InterchangeDataExportsTab from './InterchangeDataExportsTab.svelte';
  import InterchangeGeoPackageTab from './InterchangeGeoPackageTab.svelte';
  import InterchangeHubHeader, { type InterchangeSection } from './InterchangeHubHeader.svelte';
  import InterchangeTurboVegTab from './InterchangeTurboVegTab.svelte';
  import InterchangeUserSpeciesTab from './InterchangeUserSpeciesTab.svelte';
  import InterchangeVenusTab from './InterchangeVenusTab.svelte';

  let {
    contextId,
    operationHeld = false,
    port = defaultInterchangeHubPort,
    yieldScheduler = hubOps.defaultYieldScheduler,
    onBusyChange = () => {},
    onProjectActivated = () => {},
  }: {
    contextId: string;
    operationHeld?: boolean;
    port?: InterchangeHubPort;
    yieldScheduler?: () => Promise<void>;
    onBusyChange?: (busy: boolean) => void;
    onProjectActivated?: (state: Record<string, unknown>) => void;
  } = $props();

  let section = $state<InterchangeSection>(IS_WEB_READONLY ? 'analytics' : 'venus');
  let busy = $state(false);
  let error = $state('');
  let generation = 0;
  let activeRpc: { cancel: () => unknown } | null = null;
  const rpcRequests = new ReadRequests();
  const lumpDiscoveryReads = new ReadRequests();
  let lumpDiscoveryGen = 0;
  let discoveredLumpTables = $state.raw<LumpTableSummary[]>([]);
  let externalLumpDbPaths = $state<string[]>([]);

  let venusSourcePath = $state('');
  let venusInspection = $state.raw<hubOps.VenusSourceInspection | null>(null);
  let venusSelectedProject = $state('');
  let venusTargetProject = $state('');
  let venusDestinationPath = $state('');
  let venusActivate = $state(false);
  let venusResult = $state.raw<hubOps.VenusImportResult | null>(null);

  let tvExportFormat = $state<'xml' | 'sqlite'>('sqlite');
  let tvExportPath = $state('');
  let tvExportLump = $state('');
  let tvExportLumpDbPath = $state('');
  let tvExportOutcome = $state.raw<hubOps.TurboVegExportOutcome | null>(null);
  let tvImportPath = $state('');
  let tvImportFormat = $state<'xml' | 'sqlite' | ''>('');
  let tvImportTarget = $state('');
  let tvImportDestPath = $state('');
  let tvImportActivate = $state(false);
  let tvResolveSynonyms = $state(false);
  let tvImportOutcome = $state.raw<hubOps.TurboVegImportOutcome | null>(null);

  let csvLumpTable = $state('');
  let csvLumpDbPath = $state('');
  let longCsvDest = $state('');
  let wideCsvDest = $state('');
  let wideLayerMode = $state<'rollup_all' | 'strata_4' | 'species_layer'>('rollup_all');
  let wideZeroFill = $state(true);
  let wideIncludeSiteUnit = $state(true);
  let csvOutcome = $state.raw<hubOps.CSVExportOutcome | null>(null);
  let rdsDestPath = $state('');
  let rdsOutcome = $state.raw<hubOps.RDSExportOutcome | null>(null);

  let gpkgDestPath = $state('');
  let gpkgCrs = $state<'EPSG:3005' | 'EPSG:4326'>('EPSG:3005');
  let gpkgIncludeAttributes = $state(true);
  let gpkgIncludeUnlocated = $state(false);
  let gpkgLumpTable = $state('');
  let gpkgLumpDbPath = $state('');
  let gpkgOutcome = $state.raw<hubOps.GeoPackageExportOutcome | null>(null);

  function lumpDatabaseBaseName(dbPath: string): string {
    return hubOps.lumpDbBaseName(dbPath);
  }
  function lumpOptionValue(item: LumpTableSummary, list: readonly LumpTableSummary[] = discoveredLumpTables): string {
    return hubOps.computeLumpOptionValue(item, list);
  }
  function formatLumpOptionLabel(item: LumpTableSummary): string {
    return hubOps.buildLumpOptionLabel(item);
  }
  function selectedLumpOptionKey(tableName: string, dbPath: string): string {
    return hubOps.findSelectedLumpOptionKey(discoveredLumpTables, tableName, dbPath);
  }
  function applySelectedLumpOption(target: 'tv' | 'csv' | 'gpkg', optionValue: string) {
    const { tableName, dbPath } = hubOps.resolveLumpOptionChoice(discoveredLumpTables, optionValue);
    if (target === 'tv') [tvExportLump, tvExportLumpDbPath] = [tableName, dbPath];
    else if (target === 'csv') [csvLumpTable, csvLumpDbPath] = [tableName, dbPath];
    else [gpkgLumpTable, gpkgLumpDbPath] = [tableName, dbPath];
  }

  async function refreshDiscoveredLumpTables(ownerContextId = contextId, extraPaths: string[] = externalLumpDbPaths) {
    const reads = typeof lumpDiscoveryReads !== 'undefined' ? lumpDiscoveryReads : undefined;
    const effectiveExtra = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY ? [] : extraPaths;
    await hubOps.refreshDiscoveredLumpTablesOp(
      ownerContextId,
      effectiveExtra,
      port,
      reads,
      () => ++lumpDiscoveryGen,
      (id) => id === lumpDiscoveryGen && ownerContextId === contextId,
      (items) => {
        discoveredLumpTables = items;
        for (const t of hubOps.invalidLumpTargets(
          items,
          tvExportLump,
          tvExportLumpDbPath,
          csvLumpTable,
          csvLumpDbPath,
          gpkgLumpTable,
          gpkgLumpDbPath
        ))
          applySelectedLumpOption(t, '');
      }
    );
  }

  async function browseExternalLumpDatabase(target: 'tv' | 'csv' | 'gpkg') {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const filters = [{ DisplayName: 'VPro Project Database (*.db)', Pattern: '*.db' }];
    await pickFilePath('open', 'Choose VPro Database with *_Lump Tables', '', filters, async (chosenPath) => {
      const next = externalLumpDbPaths.includes(chosenPath)
        ? externalLumpDbPaths
        : [...externalLumpDbPaths, chosenPath];
      externalLumpDbPaths = next;
      await refreshDiscoveredLumpTables(contextId, next);
      const found = discoveredLumpTables.find((item) => item.databasePath === chosenPath);
      if (found) applySelectedLumpOption(target, lumpOptionValue(found, discoveredLumpTables));
      else
        pushHubError(
          'No species lumping tables found',
          `No *_Lump tables were found in ${lumpDatabaseBaseName(chosenPath)}.`
        );
    });
  }

  $effect(() => {
    void refreshDiscoveredLumpTables(contextId, $state.snapshot(externalLumpDbPaths));
    return () => lumpDiscoveryReads.cancelAll();
  });

  function setBusy(next: boolean, rpc: unknown = null) {
    activeRpc =
      next && rpc !== null && typeof rpc === 'object' && typeof (rpc as { cancel?: unknown }).cancel === 'function'
        ? (rpc as { cancel: () => unknown })
        : null;
    if (busy !== next) {
      busy = next;
      onBusyChange(next);
    }
  }

  function cancelOperation() {
    generation++;
    const current = typeof activeRpc !== 'undefined' ? activeRpc : null;
    setBusy(false);
    if (typeof rpcRequests !== 'undefined') rpcRequests.cancelAll();
    if (current) current.cancel();
  }

  function pushHubError(title: string, rawMessage: unknown) {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    error =
      webReadOnly && typeof formatWebDownloadFeedback === 'function'
        ? formatWebDownloadFeedback(rawMessage, title)
        : hubOps.formatInterchangeError(rawMessage);
    notifications.error(title, error, { category: 'background', source: 'Interchange Hub' });
  }

  async function pickFilePath(
    mode: 'open' | 'save',
    title: string,
    defaultFilename: string,
    filters: FileDialogFilter[],
    assign: (chosen: string) => void | Promise<void>
  ) {
    const owner = contextId;
    await hubOps.pickInterchangeFilePath(
      mode,
      title,
      defaultFilename,
      filters,
      busy || operationHeld,
      () => owner === contextId,
      port,
      () => {
        error = '';
      },
      pushHubError,
      assign
    );
  }

  async function validateXmlSnippet(xmlText: string): Promise<number | null> {
    const owner = contextId;
    return hubOps.validateInterchangeXmlSnippet(
      xmlText,
      busy || operationHeld,
      () => ++generation,
      (g) => g !== generation || owner !== contextId,
      (g) => {
        if (g === generation && busy) setBusy(false);
      },
      setBusy,
      () => {
        error = '';
      },
      yieldScheduler,
      pushHubError
    );
  }

  async function runHubRpc<T>(errorTitle: string, call: (owner: string) => Promise<T>, onSuccess: (res: T) => void) {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(call(owner), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError(errorTitle, out.err);
    else if (!out.cancelled && out.res !== undefined) onSuccess(out.res);
  }

  async function inspectVenus() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    if (!venusSourcePath.trim())
      return pushHubError('VENUS source path required', 'Enter a VENUS 5.0 .mdb or .xml source file path.');
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    venusInspection = null;
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.inspectVenusSource(owner, venusSourcePath.trim()), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('VENUS inspection failed', out.err);
    else if (out.res) {
      venusInspection = out.res;
      const p0 = out.res.projects[0];
      if (p0)
        ({
          projectName: venusSelectedProject,
          suggestedTarget: venusTargetProject,
          suggestedDestPath: venusDestinationPath,
        } = p0);
    }
  }

  async function runVenusImport() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const check = validateTargetProjectName(venusTargetProject);
    if (!check.valid) return pushHubError('Invalid VENUS target project', check.error);
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const req = $state.snapshot(
      hubOps.buildVenusImportPayload(
        venusSourcePath,
        venusSelectedProject,
        check.normalized,
        venusDestinationPath,
        venusActivate
      )
    );
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.importVenusProject(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('VENUS import failed', out.err);
    else if (out.res) venusResult = hubOps.onVenusImported(notifications, out.res, onProjectActivated);
  }

  async function runTurboVegExport() {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const targetPath =
      webReadOnly && !tvExportPath.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename('turboveg_export', tvExportFormat === 'xml' ? '.xml' : '.sqlite')
          : tvExportFormat === 'xml'
            ? 'turboveg_export.xml'
            : 'turboveg_export.sqlite'
        : tvExportPath.trim();
    if (!targetPath)
      return pushHubError('TurboVeg destination required', 'Enter a destination path for TurboVeg export.');
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = webReadOnly ? '' : typeof tvExportLumpDbPath === 'string' ? tvExportLumpDbPath : '';
    const req = $state.snapshot({
      format: tvExportFormat,
      destinationPath: targetPath,
      ...hubOps.lumpExportFields(tvExportLump, lumpDb),
    });
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.exportTurboVeg(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('TurboVeg export failed', out.err);
    else if (out.res) tvExportOutcome = hubOps.onTurboVegExported(notifications, out.res);
  }

  async function runTurboVegImport() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const check = validateTargetProjectName(tvImportTarget);
    if (!check.valid) return pushHubError('Invalid TurboVeg target project', check.error);
    if (!tvImportPath.trim())
      return pushHubError('TurboVeg source path required', 'Enter a TurboVeg .xml or .sqlite source path.');
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const req = $state.snapshot(
      hubOps.buildTurboVegImportPayload(
        tvImportPath,
        tvImportFormat,
        check.normalized,
        tvImportDestPath,
        tvImportActivate,
        { resolveVProCodeSynonyms: tvResolveSynonyms }
      )
    );
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.importTurboVeg(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('TurboVeg import failed', out.err);
    else if (out.res) tvImportOutcome = hubOps.onTurboVegImported(notifications, out.res, onProjectActivated);
  }

  async function runLongCsvExport() {
    if (busy || operationHeld || !contextId) return;
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = webReadOnly ? '' : typeof csvLumpDbPath === 'string' ? csvLumpDbPath : '';
    const targetPath =
      webReadOnly && !longCsvDest.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename('veg_long', '.csv')
          : 'veg_long.csv'
        : longCsvDest.trim();
    const req = $state.snapshot({
      destinationPath: targetPath,
      ...hubOps.lumpExportFields(csvLumpTable, lumpDb),
    });
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.exportLongTidyCSV(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('Long CSV export failed', out.err);
    else if (out.res) csvOutcome = out.res;
  }

  async function runWideCsvExport() {
    if (busy || operationHeld || !contextId) return;
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = webReadOnly ? '' : typeof csvLumpDbPath === 'string' ? csvLumpDbPath : '';
    const targetPath =
      webReadOnly && !wideCsvDest.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename('veg_wide_matrix', '.csv')
          : 'veg_wide_matrix.csv'
        : wideCsvDest;
    const req = $state.snapshot(
      hubOps.buildWideCsvPayload(targetPath, wideLayerMode, wideZeroFill, wideIncludeSiteUnit, csvLumpTable, lumpDb)
    );
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.exportWideMatrixCSV(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('Wide CSV export failed', out.err);
    else if (out.res) csvOutcome = out.res;
  }

  async function runRdsExport() {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const targetPath =
      webReadOnly && !rdsDestPath.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename('project_snapshot', '.rds')
          : 'project_snapshot.rds'
        : rdsDestPath.trim();
    if (!targetPath) return pushHubError('R .rds destination required', 'Enter a destination .rds file path.');
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = webReadOnly ? '' : typeof csvLumpDbPath === 'string' ? csvLumpDbPath : '';
    const req = $state.snapshot({
      destinationPath: targetPath,
      ...hubOps.lumpExportFields(csvLumpTable, lumpDb),
    });
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.exportProjectRDS(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('R .rds export failed', out.err);
    else if (out.res) rdsOutcome = hubOps.onRdsExported(notifications, out.res);
  }

  // Enforces Western North America spatial bounds [45..85 N, -170..-100 W] with positive West longitude normalization.
  async function runGeoPackageExport() {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const targetPath =
      webReadOnly && !gpkgDestPath.trim()
        ? typeof defaultWebExportFilename === 'function'
          ? defaultWebExportFilename('bec_plots', '.gpkg')
          : 'bec_plots.gpkg'
        : gpkgDestPath.trim();
    if (!targetPath)
      return pushHubError('GeoPackage destination required', 'Enter a destination .gpkg file path.');
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = webReadOnly ? '' : typeof gpkgLumpDbPath === 'string' ? gpkgLumpDbPath : '';
    const req = $state.snapshot(
      hubOps.buildGeoPackagePayload(
        targetPath,
        gpkgCrs,
        gpkgIncludeAttributes,
        gpkgIncludeUnlocated,
        gpkgLumpTable,
        lumpDb
      )
    );
    const r = typeof rpcRequests !== 'undefined' ? rpcRequests : undefined;
    const [tracked, active] = hubOps.trackHubCall(port.exportGeoPackage(owner, req), r);
    error = '';
    setBusy(true, active);
    const out = await hubOps.awaitHubCall(tracked);
    if (reqGen === generation && busy) setBusy(false);
    if (reqGen !== generation || owner !== contextId) return;
    if (out.err) pushHubError('GeoPackage export failed', out.err);
    else if (out.res) gpkgOutcome = hubOps.onGeoPackageExported(notifications, out.res);
  }

  const hubShared = $derived({ contextId, busy, operationHeld, onPickFilePath: pickFilePath });
  const lumpProps = $derived({ discoveredLumpTables, lumpOptionValue, formatLumpOptionLabel });
  onDestroy(() => {
    lumpDiscoveryReads.cancelAll();
    cancelOperation();
  });
</script>

<section
  class="bcgov-interchange"
  data-tour="interchange-hub-root"
  data-interchange-hub
  aria-label="VPro Standards and Analytical Interchange Hub"
>
  <InterchangeHubHeader bind:section {busy} onCancel={cancelOperation} />

  {#if IS_WEB_READONLY && error}
    <p class="hub-error-banner" role="alert">{error}</p>
  {/if}

  {#if section === 'venus' && !IS_WEB_READONLY}
    <InterchangeVenusTab
      {...hubShared}
      bind:venusSourcePath
      {venusInspection}
      bind:venusSelectedProject
      bind:venusTargetProject
      bind:venusDestinationPath
      bind:venusActivate
      {venusResult}
      onInspectVenus={inspectVenus}
      onRunVenusImport={runVenusImport}
    />
  {:else if section === 'turboveg'}
    <InterchangeTurboVegTab
      {...hubShared}
      {...lumpProps}
      bind:tvExportFormat
      bind:tvExportPath
      selectedLumpKey={selectedLumpOptionKey(tvExportLump, tvExportLumpDbPath)}
      {tvExportOutcome}
      layerCrosswalk={hubOps.TURBOVEG_LAYER_CROSSWALK}
      bind:tvImportPath
      bind:tvImportFormat
      bind:tvImportTarget
      bind:tvImportDestPath
      bind:tvImportActivate
      bind:tvResolveSynonyms
      {tvImportOutcome}
      onApplyLumpOption={(val) => applySelectedLumpOption('tv', val)}
      onBrowseExternalLumpDb={() => void browseExternalLumpDatabase('tv')}
      onRunTurboVegExport={runTurboVegExport}
      onValidateXmlSnippet={validateXmlSnippet}
      onRunTurboVegImport={runTurboVegImport}
    />
  {:else if section === 'userspecies'}
    <InterchangeUserSpeciesTab {...hubShared} {port} onRunHubRpc={runHubRpc} />
  {:else if section === 'analytics'}
    <InterchangeDataExportsTab
      {...hubShared}
      {...lumpProps}
      csvLumpKey={selectedLumpOptionKey(csvLumpTable, csvLumpDbPath)}
      bind:longCsvDest
      bind:wideCsvDest
      bind:wideLayerMode
      bind:wideZeroFill
      bind:wideIncludeSiteUnit
      {csvOutcome}
      bind:rdsDestPath
      {rdsOutcome}
      onApplyLumpOption={(val) => applySelectedLumpOption('csv', val)}
      onBrowseExternalLumpDb={() => void browseExternalLumpDatabase('csv')}
      onRunLongCsvExport={runLongCsvExport}
      onRunWideCsvExport={runWideCsvExport}
      onRunRdsExport={runRdsExport}
    />
  {:else}
    <InterchangeGeoPackageTab
      {...hubShared}
      {...lumpProps}
      gpkgLumpKey={selectedLumpOptionKey(gpkgLumpTable, gpkgLumpDbPath)}
      bind:gpkgDestPath
      bind:gpkgCrs
      bind:gpkgIncludeAttributes
      bind:gpkgIncludeUnlocated
      {gpkgOutcome}
      onApplyLumpOption={(val) => applySelectedLumpOption('gpkg', val)}
      onBrowseExternalLumpDb={() => void browseExternalLumpDatabase('gpkg')}
      onRunGeoPackageExport={runGeoPackageExport}
    />
  {/if}
</section>

<style>
  .bcgov-interchange {
    display: grid;
    gap: 1rem;
    min-width: 0;
    --hub-accent-navy: var(--vpro-navy);
    --hub-accent-gold: var(--vpro-gold);
  }
  .hub-error-banner {
    margin: 0;
    padding: 0.65rem 0.9rem;
    background: var(--vpro-error-bg);
    border-left: 4px solid var(--vpro-error);
    color: var(--vpro-error);
    border-radius: 4px;
    font-size: 0.84rem;
  }
</style>
