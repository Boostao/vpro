<script lang="ts">
  import { onDestroy } from 'svelte';
  import { notifications } from '../shell/notificationService.svelte';
  import { ReadRequests, type CancellableRead } from '../shared/readRequests';
  import {
    TURBOVEG_LAYER_CROSSWALK,
    defaultInterchangeHubPort,
    defaultYieldScheduler,
    validateTargetProjectName,
    validateXMLSnippetChunked,
    type CSVExportOutcome,
    type FileDialogFilter,
    type GeoPackageExportOutcome,
    type InterchangeHubPort,
    type LumpTableSummary,
    type RDSExportOutcome,
    type TurboVegExportOutcome,
    type TurboVegImportOutcome,
    type UserSpeciesCollisionPolicy,
    type UserSpeciesExportResult,
    type UserSpeciesImportPreview,
    type UserSpeciesImportResult,
    type VenusImportResult,
    type VenusSourceInspection,
  } from './interchangeHub';

  type HubSection = 'venus' | 'turboveg' | 'userspecies' | 'analytics' | 'geopackage';

  let {
    contextId,
    operationHeld = false,
    port = defaultInterchangeHubPort,
    yieldScheduler = defaultYieldScheduler,
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

  let section = $state<HubSection>('venus');
  let busy = $state(false);
  let error = $state('');
  let generation = 0;
  let activeRpc: { cancel: () => unknown } | null = null;
  const rpcRequests = new ReadRequests();
  const lumpDiscoveryReads = new ReadRequests();
  let lumpDiscoveryGen = 0;
  let discoveredLumpTables = $state.raw<LumpTableSummary[]>([]);
  let externalLumpDbPaths = $state<string[]>([]);

  // 1. VENUS 5.0 state
  let venusSourcePath = $state('');
  let venusInspection = $state.raw<VenusSourceInspection | null>(null);
  let venusSelectedProject = $state('');
  let venusTargetProject = $state('');
  let venusDestinationPath = $state('');
  let venusActivate = $state(false);
  let venusResult = $state.raw<VenusImportResult | null>(null);

  // 2. TurboVeg 3 / XML state
  let tvExportFormat = $state<'xml' | 'sqlite'>('sqlite');
  let tvExportPath = $state('');
  let tvExportLump = $state('');
  let tvExportLumpDbPath = $state('');
  let tvExportOutcome = $state.raw<TurboVegExportOutcome | null>(null);

  let tvImportPath = $state('');
  let tvImportFormat = $state<'xml' | 'sqlite' | ''>('');
  let tvImportTarget = $state('');
  let tvImportDestPath = $state('');
  let tvImportActivate = $state(false);
  let tvResolveSynonyms = $state(false);
  let tvXmlSnippet = $state('');
  let tvXmlSnippetCount = $state<number | null>(null);
  let tvImportOutcome = $state.raw<TurboVegImportOutcome | null>(null);

  // 3. User Species List state
  let userSppExportFormat = $state<'json' | 'csv'>('json');
  let userSppExportPath = $state('');
  let userSppExportResult = $state.raw<UserSpeciesExportResult | null>(null);

  let userSppImportPath = $state('');
  let userSppImportContent = $state('');
  let userSppPolicy = $state<UserSpeciesCollisionPolicy>('skip');
  let userSppPreview = $state.raw<UserSpeciesImportPreview | null>(null);
  let userSppImportResult = $state.raw<UserSpeciesImportResult | null>(null);

  // 4. Long/Wide CSV & R .rds state
  let csvLumpTable = $state('');
  let csvLumpDbPath = $state('');
  let longCsvDest = $state('');
  let wideCsvDest = $state('');
  let wideLayerMode = $state<'rollup_all' | 'strata_4' | 'species_layer'>('rollup_all');
  let wideZeroFill = $state(true);
  let wideIncludeSiteUnit = $state(true);
  let csvOutcome = $state.raw<CSVExportOutcome | null>(null);

  let rdsDestPath = $state('');
  let rdsOutcome = $state.raw<RDSExportOutcome | null>(null);

  // 5. GeoPackage (.gpkg) state
  let gpkgDestPath = $state('');
  let gpkgCrs = $state<'EPSG:3005' | 'EPSG:4326'>('EPSG:3005');
  let gpkgIncludeAttributes = $state(true);
  let gpkgIncludeUnlocated = $state(false);
  let gpkgLumpTable = $state('');
  let gpkgLumpDbPath = $state('');
  let gpkgOutcome = $state.raw<GeoPackageExportOutcome | null>(null);

  function lumpDatabaseBaseName(dbPath: string): string {
    const normalized = String(dbPath ?? '').replaceAll('\\', '/');
    const idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.slice(idx + 1) : normalized;
  }

  function lumpOptionValue(item: LumpTableSummary, list: readonly LumpTableSummary[] = discoveredLumpTables): string {
    const duplicateCount = list.filter(other => other.tableName.toLowerCase() === item.tableName.toLowerCase()).length;
    if (duplicateCount <= 1 || item.isActiveProject) {
      return item.tableName;
    }
    return `${item.tableName}@${item.databasePath}`;
  }

  function formatLumpOptionLabel(item: LumpTableSummary): string {
    const rules = `${item.activeCount} active rule${item.activeCount === 1 ? '' : 's'}`;
    if (item.isActiveProject) {
      return `${item.tableName} (${rules})`;
    }
    return `${item.tableName} (${lumpDatabaseBaseName(item.databasePath)} · ${rules})`;
  }

  function selectedLumpOptionKey(tableName: string, dbPath: string): string {
    const trimmedTable = (tableName ?? '').trim();
    if (!trimmedTable) return '';
    const trimmedDb = (dbPath ?? '').trim();
    const match = discoveredLumpTables.find(item => {
      if (item.tableName.toLowerCase() !== trimmedTable.toLowerCase()) return false;
      if (!trimmedDb) return item.isActiveProject;
      return item.databasePath === trimmedDb;
    }) ?? discoveredLumpTables.find(item => item.tableName.toLowerCase() === trimmedTable.toLowerCase());
    return match ? lumpOptionValue(match, discoveredLumpTables) : trimmedTable;
  }

  function applySelectedLumpOption(target: 'tv' | 'csv' | 'gpkg', optionValue: string) {
    const raw = (optionValue ?? '').trim();
    const chosen = raw
      ? discoveredLumpTables.find(item => lumpOptionValue(item, discoveredLumpTables) === raw) ?? null
      : null;
    const nextTable = chosen ? chosen.tableName : '';
    const nextDbPath = chosen && !chosen.isActiveProject ? chosen.databasePath : '';
    if (target === 'tv') {
      tvExportLump = nextTable;
      tvExportLumpDbPath = nextDbPath;
    } else if (target === 'csv') {
      csvLumpTable = nextTable;
      csvLumpDbPath = nextDbPath;
    } else {
      gpkgLumpTable = nextTable;
      gpkgLumpDbPath = nextDbPath;
    }
  }

  async function refreshDiscoveredLumpTables(ownerContextId = contextId, extraPaths: string[] = externalLumpDbPaths) {
    if (!ownerContextId) {
      discoveredLumpTables = [];
      return;
    }
    const discoverFn =
      typeof port?.discoverLumpTables === 'function'
        ? port.discoverLumpTables.bind(port)
        : port === defaultInterchangeHubPort && typeof defaultInterchangeHubPort.discoverLumpTables === 'function'
          ? defaultInterchangeHubPort.discoverLumpTables
          : null;
    if (!discoverFn) return;
    const reqId = ++lumpDiscoveryGen;
    try {
      const rawRpc = discoverFn(ownerContextId, [...extraPaths]);
      const tracked =
        typeof lumpDiscoveryReads !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? lumpDiscoveryReads.track(rawRpc as unknown as CancellableRead<LumpTableSummary[]>)
          : rawRpc;
      const items = (await tracked) ?? [];
      if (reqId !== lumpDiscoveryGen || ownerContextId !== contextId) return;
      discoveredLumpTables = Array.isArray(items) ? items : [];
      for (const target of ['tv', 'csv', 'gpkg'] as const) {
        const curTable = target === 'tv' ? tvExportLump : target === 'csv' ? csvLumpTable : gpkgLumpTable;
        const curDb = target === 'tv' ? tvExportLumpDbPath : target === 'csv' ? csvLumpDbPath : gpkgLumpDbPath;
        if (!curTable) continue;
        const stillValid = discoveredLumpTables.some(
          item =>
            item.tableName.toLowerCase() === curTable.toLowerCase() &&
            (!curDb ? true : item.databasePath === curDb)
        );
        if (!stillValid) {
          applySelectedLumpOption(target, '');
        }
      }
    } catch {
      if (reqId === lumpDiscoveryGen && ownerContextId === contextId) {
        discoveredLumpTables = [];
      }
    }
  }

  async function browseExternalLumpDatabase(target: 'tv' | 'csv' | 'gpkg') {
    await pickFilePath(
      'open',
      'Choose VPro Database with *_Lump Tables',
      '',
      [{ DisplayName: 'VPro Project Database (*.db)', Pattern: '*.db' }],
      async chosenPath => {
        const nextPaths = externalLumpDbPaths.includes(chosenPath)
          ? externalLumpDbPaths
          : [...externalLumpDbPaths, chosenPath];
        externalLumpDbPaths = nextPaths;
        await refreshDiscoveredLumpTables(contextId, nextPaths);
        const fromChosen = discoveredLumpTables.find(item => item.databasePath === chosenPath);
        if (fromChosen) {
          applySelectedLumpOption(target, lumpOptionValue(fromChosen, discoveredLumpTables));
        } else {
          pushHubError(
            'No species lumping tables found',
            `No *_Lump tables were found in ${lumpDatabaseBaseName(chosenPath)}.`
          );
        }
      }
    );
  }

  $effect(() => {
    const owner = contextId;
    const extras = $state.snapshot(externalLumpDbPaths);
    if (!owner) {
      discoveredLumpTables = [];
      return;
    }
    void refreshDiscoveredLumpTables(owner, extras);
    return () => {
      lumpDiscoveryReads.cancelAll();
    };
  });

  function setBusy(next: boolean, rpc: unknown = null) {
    const cancellable =
      next &&
      rpc !== null &&
      typeof rpc === 'object' &&
      typeof (rpc as { cancel?: unknown }).cancel === 'function'
        ? (rpc as { cancel: () => unknown })
        : null;
    if (typeof activeRpc !== 'undefined') {
      activeRpc = cancellable;
    } else {
      (setBusy as unknown as { _activeRpc?: { cancel: () => unknown } | null })._activeRpc = cancellable;
    }
    if (busy !== next) {
      busy = next;
      onBusyChange(next);
    }
  }

  function cancelOperation() {
    generation++;
    const current =
      typeof activeRpc !== 'undefined'
        ? activeRpc
        : ((setBusy as unknown as { _activeRpc?: { cancel: () => unknown } | null })._activeRpc ?? null);
    setBusy(false);
    if (typeof rpcRequests !== 'undefined') {
      rpcRequests.cancelAll();
    }
    if (current) {
      current.cancel();
    }
  }

  function pushHubError(title: string, rawMessage: unknown) {
    let message = String(rawMessage ?? '').trim();
    const prefixes = ['RuntimeError:', 'Error:', 'CallError:'];
    let stripped = true;
    while (stripped) {
      stripped = false;
      for (const prefix of prefixes) {
        if (message.startsWith(prefix)) {
          message = message.slice(prefix.length).trim();
          stripped = true;
        }
      }
    }
    if (message.includes('picture selection') || message.includes('file dialogs not available in server mode')) {
      message = 'File selection requires an active desktop window; enter a file path directly when running in a browser.';
    } else if (message.includes('database disk image is malformed') || message.includes('file is not a database')) {
      message = 'The selected database file is damaged, incomplete, or not a valid SQLite file.';
    } else if (
      message.includes('Access source read error') ||
      message.includes('cannot read Access catalog') ||
      message.includes('cannot reopen Access database')
    ) {
      message = 'The selected Access file could not be read. It may be incomplete, damaged, or in an unsupported format.';
    } else if (/XML syntax error on line (\d+)/i.test(message)) {
      const m = /XML syntax error on line (\d+)/i.exec(message);
      message = `The selected XML file is incomplete or contains invalid XML formatting on line ${m?.[1] ?? '1'}.`;
    } else if (message.includes('XML syntax error') || message.includes('unexpected EOF')) {
      message = 'The selected file ended unexpectedly or contains invalid formatting.';
    } else if (/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\b[^:]*:\s*(?:no such file or directory|cannot find the file)/i.test(message)) {
      message = 'The selected file or folder was not found. Check the path and try again.';
    } else if (/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\b[^:]*:\s*(?:permission denied|access is denied)/i.test(message)) {
      message = 'VPro does not have permission to read or write the selected file path.';
    } else {
      message = message
        .replace(/\b(?:lstat|stat|open|CreateFile|GetFileAttributesEx)\s+[^:]+:\s*/gi, '')
        .replace(/:\s*sql:\s*no rows in result set/gi, '')
        .replace(/\bsql:\s*no rows in result set\b/gi, 'the requested table or record was not found')
        .trim();
    }
    if (!message) message = 'An unexpected error occurred.';
    error = message;
    if (typeof notifications !== 'undefined' && typeof notifications?.error === 'function') {
      notifications.error(title, message, { category: 'background', source: 'Interchange Hub' });
    }
  }

  async function pickFilePath(
    mode: 'open' | 'save',
    title: string,
    defaultFilename: string,
    filters: FileDialogFilter[],
    assign: (chosen: string) => void | Promise<void>
  ) {
    if (busy || operationHeld) return;
    const owner = contextId;
    error = '';
    try {
      const chosen =
        mode === 'open'
          ? await (port.chooseOpenFile ?? defaultInterchangeHubPort.chooseOpenFile)?.(title, filters)
          : await (port.chooseSaveFile ?? defaultInterchangeHubPort.chooseSaveFile)?.(title, defaultFilename, filters);
      if (owner !== contextId) return;
      if (typeof chosen === 'string' && chosen.trim()) {
        await assign(chosen.trim());
      }
    } catch (cause) {
      pushHubError('File picker failed', String(cause));
    }
  }

  async function inspectVenus() {
    if (!venusSourcePath.trim()) {
      pushHubError('VENUS source path required', 'Enter a VENUS 5.0 .mdb or .xml source file path.');
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    venusInspection = null;
    try {
      const rawRpc = port.inspectVenusSource(owner, venusSourcePath.trim());
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<VenusSourceInspection>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      venusInspection = res;
      if (res.projects.length > 0) {
        venusSelectedProject = res.projects[0].projectName;
        venusTargetProject = res.projects[0].suggestedTarget;
        venusDestinationPath = res.projects[0].suggestedDestPath;
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('VENUS inspection failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runVenusImport() {
    const check = validateTargetProjectName(venusTargetProject);
    if (!check.valid) {
      pushHubError('Invalid VENUS target project', check.error);
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const payload = $state.snapshot({
      sourcePath: venusSourcePath.trim(),
      sourceProject: venusSelectedProject.trim(),
      targetProject: check.normalized,
      destinationPath: venusDestinationPath.trim(),
      activateOnSuccess: venusActivate,
    });
    error = '';
    try {
      const rawRpc = port.importVenusProject(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<VenusImportResult>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      venusResult = res;
      if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Interchange · VENUS 5.0',
          title: `Imported ${res.plotCount} plots into ${res.targetProject}`,
          message: `Saved to ${res.destinationPath}`,
        });
      }
      if (res.activated && res.state) {
        onProjectActivated(res.state);
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('VENUS import failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runTurboVegExport() {
    if (!tvExportPath.trim()) {
      pushHubError('TurboVeg destination required', 'Enter a destination path for TurboVeg export.');
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = typeof tvExportLumpDbPath === 'string' ? tvExportLumpDbPath.trim() : '';
    const payload = $state.snapshot({
      format: tvExportFormat,
      destinationPath: tvExportPath.trim(),
      lumpTable: tvExportLump.trim(),
      ...(lumpDb ? { lumpDbPath: lumpDb } : {}),
    });
    error = '';
    try {
      const rawRpc = port.exportTurboVeg(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<TurboVegExportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      tvExportOutcome = res;
      if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Interchange · TurboVeg',
          title: `Exported ${res.plotCount} TurboVeg plot(s)`,
          message: res.path,
        });
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('TurboVeg export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function checkTurboVegXmlSnippet() {
    if (busy || operationHeld) return;
    const reqGen = ++generation;
    const owner = contextId;
    error = '';
    tvXmlSnippetCount = null;
    setBusy(true);
    try {
      const check = await validateXMLSnippetChunked(
        tvXmlSnippet,
        8192,
        yieldScheduler,
        () => reqGen !== generation || owner !== contextId
      );
      if (reqGen !== generation || owner !== contextId) return;
      if (!check.valid) {
        pushHubError('TurboVeg XML validation failed', check.error);
        return;
      }
      tvXmlSnippetCount = check.plotTagCount;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('TurboVeg XML validation failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runTurboVegImport() {
    const check = validateTargetProjectName(tvImportTarget);
    if (!check.valid) {
      pushHubError('Invalid TurboVeg target project', check.error);
      return;
    }
    if (!tvImportPath.trim()) {
      pushHubError('TurboVeg source path required', 'Enter a TurboVeg .xml or .sqlite source path.');
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const payload = $state.snapshot({
      sourcePath: tvImportPath.trim(),
      format: tvImportFormat,
      targetProject: check.normalized,
      destinationPath: tvImportDestPath.trim(),
      activateOnSuccess: tvImportActivate,
      resolveVProCodeSynonyms: tvResolveSynonyms,
    });
    error = '';
    try {
      const rawRpc = port.importTurboVeg(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<TurboVegImportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      tvImportOutcome = res;
      if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Interchange · TurboVeg',
          title: `Imported ${res.plotCount} TurboVeg plot(s) into ${res.targetProject}`,
          message: res.destinationPath,
        });
      }
      if (res.activated && res.state) {
        onProjectActivated(res.state);
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('TurboVeg import failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runUserSpeciesExport() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const payload = $state.snapshot({
      format: userSppExportFormat,
      destinationPath: userSppExportPath.trim(),
    });
    error = '';
    try {
      const rawRpc = port.exportUserSpeciesList(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<UserSpeciesExportResult>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      userSppExportResult = res;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('User species export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runUserSpeciesPreview() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const payload = $state.snapshot({
      sourcePath: userSppImportPath.trim(),
      content: userSppImportContent,
      collisionPolicy: userSppPolicy,
    });
    error = '';
    try {
      const rawRpc = port.previewUserSpeciesImport(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<UserSpeciesImportPreview>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      userSppPreview = res;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('User species preview failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runUserSpeciesImport() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const payload = $state.snapshot({
      sourcePath: userSppImportPath.trim(),
      content: userSppImportContent,
      collisionPolicy: userSppPolicy,
    });
    error = '';
    try {
      const rawRpc = port.importUserSpeciesList(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<UserSpeciesImportResult>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      userSppImportResult = res;
      userSppPreview = res.preview;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('User species import failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runLongCsvExport() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = typeof csvLumpDbPath === 'string' ? csvLumpDbPath.trim() : '';
    const payload = $state.snapshot({
      destinationPath: longCsvDest.trim(),
      lumpTable: csvLumpTable.trim(),
      ...(lumpDb ? { lumpDbPath: lumpDb } : {}),
    });
    error = '';
    try {
      const rawRpc = port.exportLongTidyCSV(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<CSVExportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      csvOutcome = res;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('Long CSV export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runWideCsvExport() {
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = typeof csvLumpDbPath === 'string' ? csvLumpDbPath.trim() : '';
    const payload = $state.snapshot({
      destinationPath: wideCsvDest.trim(),
      layerMode: wideLayerMode,
      zeroFill: wideZeroFill,
      includeSiteUnit: wideIncludeSiteUnit,
      lumpTable: csvLumpTable.trim(),
      ...(lumpDb ? { lumpDbPath: lumpDb } : {}),
    });
    error = '';
    try {
      const rawRpc = port.exportWideMatrixCSV(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<CSVExportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      csvOutcome = res;
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('Wide CSV export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runRdsExport() {
    if (!rdsDestPath.trim()) {
      pushHubError('R .rds destination required', 'Enter a destination .rds file path.');
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = typeof csvLumpDbPath === 'string' ? csvLumpDbPath.trim() : '';
    const payload = $state.snapshot({
      destinationPath: rdsDestPath.trim(),
      lumpTable: csvLumpTable.trim(),
      ...(lumpDb ? { lumpDbPath: lumpDb } : {}),
    });
    error = '';
    try {
      const rawRpc = port.exportProjectRDS(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<RDSExportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      rdsOutcome = res;
      if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Interchange · R .rds',
          title: `Exported R .rds (${res.plotCount} plots)`,
          message: res.path,
        });
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('R .rds export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  async function runGeoPackageExport() {
    if (!gpkgDestPath.trim()) {
      pushHubError('GeoPackage destination required', 'Enter a destination .gpkg file path.');
      return;
    }
    if (busy || operationHeld || !contextId) return;
    const reqGen = ++generation;
    const owner = contextId;
    const lumpDb = typeof gpkgLumpDbPath === 'string' ? gpkgLumpDbPath.trim() : '';
    const payload = $state.snapshot({
      destinationPath: gpkgDestPath.trim(),
      crs: gpkgCrs,
      includeAttributeTables: gpkgIncludeAttributes,
      includeUnlocatedPlots: gpkgIncludeUnlocated,
      lumpTable: gpkgLumpTable.trim(),
      ...(lumpDb ? { lumpDbPath: lumpDb } : {}),
    });
    error = '';
    try {
      const rawRpc = port.exportGeoPackage(owner, payload);
      const trackedRpc =
        typeof rpcRequests !== 'undefined' &&
        rawRpc !== null &&
        typeof rawRpc === 'object' &&
        typeof (rawRpc as { cancel?: unknown }).cancel === 'function'
          ? rpcRequests.track(rawRpc as unknown as CancellableRead<GeoPackageExportOutcome>)
          : rawRpc;
      setBusy(true, trackedRpc === rawRpc ? rawRpc : null);
      const res = await trackedRpc;
      if (reqGen !== generation || owner !== contextId) return;
      gpkgOutcome = res;
      if (typeof notifications !== 'undefined' && typeof notifications?.push === 'function') {
        notifications.push({
          severity: 'success',
          category: 'background',
          source: 'Interchange · GeoPackage',
          title: `Exported ${res.featureCount} GeoPackage plot features (${res.crs})`,
          message: res.path,
        });
      }
    } catch (cause) {
      if (reqGen === generation && owner === contextId && !(cause instanceof Error && cause.name === 'CancelError')) {
        pushHubError('GeoPackage export failed', String(cause));
      }
    } finally {
      if (reqGen === generation && busy) setBusy(false);
    }
  }

  onDestroy(() => {
    lumpDiscoveryReads.cancelAll();
    cancelOperation();
  });
</script>

<section class="bcgov-interchange" data-tour="interchange-hub-root" data-interchange-hub aria-label="VPro Standards and Analytical Interchange Hub">
  <header class="bcgov-banner">
    <div>
      <p class="eyebrow-gold">STANDARDS, ANALYTICS &amp; GIS INTERCHANGE</p>
      <h2>VENUS 5.0, TurboVeg 3 / XML, User Species, CSV / R (.rds) &amp; OGC GeoPackage (.gpkg)</h2>
    </div>
    <nav class="hub-tabs" aria-label="Interchange formats">
      <button type="button" class:active={section === 'venus'} onclick={() => (section = 'venus')}>VENUS 5.0</button>
      <button type="button" class:active={section === 'turboveg'} onclick={() => (section = 'turboveg')}>TurboVeg 3 / XML</button>
      <button type="button" class:active={section === 'userspecies'} onclick={() => (section = 'userspecies')}>User Species List</button>
      <button type="button" class:active={section === 'analytics'} onclick={() => (section = 'analytics')}>Long/Wide CSV &amp; R .rds</button>
      <button type="button" class:active={section === 'geopackage'} onclick={() => (section = 'geopackage')}>GeoPackage (.gpkg)</button>
      {#if busy}
        <button type="button" class="cancel-btn" onclick={cancelOperation}>Cancel</button>
      {/if}
    </nav>
  </header>

  {#if section === 'venus'}
    <div class="hub-card">
      <h3>VENUS 5.0 (.mdb &amp; .xml) Project Importer</h3>
      <p class="desc">Pivots normalized VENUS 5.0 vegetation layers, site/soil attributes, and organic/mineral horizons into a verified VPro project (.db).</p>
      <div class="form-row">
        <label class="grow">
          <span>VENUS Source File (.mdb, .accdb, or .xml)</span>
          <div class="input-with-browse">
            <input type="text" class="grow" bind:value={venusSourcePath} placeholder="/path/to/VenusProject.mdb or .xml" disabled={busy || operationHeld} />
            <button type="button" class="btn-secondary" data-browse-venus-source disabled={busy || operationHeld} onclick={() => pickFilePath('open', 'Choose VENUS Source File', '', [{ DisplayName: 'VENUS Files (*.mdb, *.accdb, *.xml)', Pattern: '*.mdb;*.accdb;*.xml' }], (p) => { venusSourcePath = p; })}>Browse...</button>
          </div>
        </label>
        <button type="button" class="btn-secondary" disabled={busy || operationHeld || !contextId} onclick={inspectVenus}>
          Inspect Source
        </button>
      </div>

      {#if venusInspection}
        <div class="receipt-box">
          <p>
            <strong>Detected:</strong> VENUS {venusInspection.venusVersion} ({venusInspection.sourceFormat.toUpperCase()}) |
            <strong>SHA-256:</strong> <code>{venusInspection.sourceSha256.slice(0, 16)}...</code>
          </p>
          <div class="form-row">
            <label>
              <span>Source VENUS Project</span>
              <select bind:value={venusSelectedProject} disabled={busy || operationHeld}>
                {#each venusInspection.projects as cand (cand.projectName)}
                  <option value={cand.projectName}>{cand.projectName} ({cand.plotCount} plots)</option>
                {/each}
              </select>
            </label>
            <label>
              <span>Target VPro Project Name</span>
              <input type="text" bind:value={venusTargetProject} disabled={busy || operationHeld} />
            </label>
            <label class="grow">
              <span>Destination .db Path</span>
              <input type="text" bind:value={venusDestinationPath} disabled={busy || operationHeld} />
            </label>
            <label class="check-inline">
              <input type="checkbox" bind:checked={venusActivate} disabled={busy || operationHeld} />
              <span>Open after import</span>
            </label>
            <button type="button" class="btn-primary" disabled={busy || operationHeld} onclick={runVenusImport}>
              Import into VPro
            </button>
          </div>
        </div>
      {/if}

      {#if venusResult}
        <div class="receipt-box success">
          <strong>Imported {venusResult.plotCount} plots into {venusResult.targetProject}</strong>
          <span>Veg rows: {venusResult.vegRowCount} | Humus: {venusResult.humusRowCount} | Mineral: {venusResult.mineralRowCount}</span>
          <span>Saved to: <code>{venusResult.destinationPath}</code></span>
        </div>
      {/if}
    </div>
  {:else if section === 'turboveg'}
    <div class="two-col">
      <div class="hub-card">
        <h3>Export TurboVeg 3 (31-Table .sqlite) or Standard XML (&lt;Plot_package&gt;)</h3>
        <div class="form-stack">
          <label>
            <span>Target Format</span>
            <select bind:value={tvExportFormat} disabled={busy || operationHeld}>
              <option value="sqlite">TurboVeg 3 Official 31-Table SQLite (.sqlite)</option>
              <option value="xml">TurboVeg Standard XML (&lt;Plot_package&gt; for TV2 / TV3 / JUICE / vegdata)</option>
            </select>
          </label>
          <label>
            <span>Destination File Path</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={tvExportPath} placeholder="/path/to/export.sqlite or .xml" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-save-tv-export disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save TurboVeg Export', tvExportFormat === 'xml' ? 'turboveg_export.xml' : 'turboveg_export.sqlite', [{ DisplayName: 'TurboVeg (*.sqlite, *.xml)', Pattern: '*.sqlite;*.xml' }], (p) => { tvExportPath = p; })}>Save As...</button>
            </div>
          </label>
          <label>
            <span>Optional *_Lump Table</span>
            <div class="input-with-browse">
              <select
                class="grow"
                data-lump-select="turboveg"
                value={selectedLumpOptionKey(tvExportLump, tvExportLumpDbPath)}
                onchange={e => applySelectedLumpOption('tv', (e.currentTarget as HTMLSelectElement).value)}
                disabled={busy || operationHeld}
              >
                <option value="">None (raw unlumped species)</option>
                {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
                  <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
                {/each}
              </select>
              <button
                type="button"
                class="btn-secondary"
                data-browse-lump-db="turboveg"
                disabled={busy || operationHeld}
                onclick={() => void browseExternalLumpDatabase('tv')}
              >
                From .db…
              </button>
            </div>
          </label>
          <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runTurboVegExport}>
            Export TurboVeg
          </button>
        </div>

        {#if tvExportOutcome}
          <div class="receipt-box success">
            <strong>Exported {tvExportOutcome.plotCount} plots ({tvExportOutcome.observationCount} abundances, {tvExportOutcome.speciesCount} taxa)</strong>
            <span>File: <code>{tvExportOutcome.path}</code></span>
          </div>
        {/if}

        <h4>Canonical VPro &lt;-&gt; TurboVeg Layer Crosswalk (0..10 + UDF Sublayer Tags)</h4>
        <div class="table-scroll">
          <table class="compact-table">
            <thead><tr><th>VPro Columns</th><th>TurboVeg Layer</th><th>Crosswalk &amp; UDF Provenance</th></tr></thead>
            <tbody>
              {#each TURBOVEG_LAYER_CROSSWALK as cw (cw.tvGroup)}
                <tr><td class="mono">{cw.vproLayers}</td><td><strong>{cw.tvGroup}</strong></td><td>{cw.description}</td></tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>

      <div class="hub-card">
        <h3>Import TurboVeg (.sqlite or &lt;Plot_package&gt; .xml) into VPro</h3>
        <div class="form-stack">
          <label>
            <span>Source TurboVeg File (.sqlite or .xml)</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={tvImportPath} placeholder="/path/to/turboveg.sqlite or .xml" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-browse-tv-import disabled={busy || operationHeld} onclick={() => pickFilePath('open', 'Choose TurboVeg File', '', [{ DisplayName: 'TurboVeg (*.sqlite, *.xml)', Pattern: '*.sqlite;*.xml' }], (p) => { tvImportPath = p; })}>Browse...</button>
            </div>
          </label>
          <label>
            <span>Format Override</span>
            <select bind:value={tvImportFormat} disabled={busy || operationHeld}>
              <option value="">Auto-detect from extension</option>
              <option value="sqlite">TurboVeg 3 31-Table SQLite (.sqlite)</option>
              <option value="xml">TurboVeg Standard XML (&lt;Plot_package&gt; .xml)</option>
            </select>
          </label>
          <label>
            <span>Target VPro Project Name</span>
            <input type="text" bind:value={tvImportTarget} placeholder="e.g. Phytosoc2026" disabled={busy || operationHeld} />
          </label>
          <label>
            <span>Destination .db Path (optional)</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={tvImportDestPath} placeholder="Defaults to projects/<Target>.db" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-save-tv-dest disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Choose VPro Project Destination', `${tvImportTarget.trim() || 'project'}.db`, [{ DisplayName: 'VPro Project (*.db)', Pattern: '*.db' }], (p) => { tvImportDestPath = p; })}>Save As...</button>
            </div>
          </label>
          <label class="check-inline">
            <input type="checkbox" bind:checked={tvResolveSynonyms} disabled={busy || operationHeld} />
            <span>Resolve VPro OldCode synonyms (USysAllSpecs Codetype='S')</span>
          </label>
          <label class="check-inline">
            <input type="checkbox" bind:checked={tvImportActivate} disabled={busy || operationHeld} />
            <span>Activate imported project</span>
          </label>
          <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runTurboVegImport}>
            Import TurboVeg Project
          </button>
        </div>

        <details class="xml-check-box">
          <summary>Pre-validate pasted XML snippet</summary>
          <textarea bind:value={tvXmlSnippet} rows={3} placeholder="<Plot_package><Plots><Plot releve_nr=&quot;1&quot;>..." disabled={busy || operationHeld}></textarea>
          <button type="button" class="btn-secondary" disabled={busy || operationHeld} onclick={checkTurboVegXmlSnippet}>
            Validate XML Snippet
          </button>
          {#if tvXmlSnippetCount !== null}
            <p class="ok-text">Valid UTF-8 XML ({tvXmlSnippetCount} plot element(s) detected).</p>
          {/if}
        </details>

        {#if tvImportOutcome}
          <div class="receipt-box success">
            <strong>Imported {tvImportOutcome.plotCount} plots ({tvImportOutcome.observationCount} observations) into {tvImportOutcome.targetProject}</strong>
            <span>Destination: <code>{tvImportOutcome.destinationPath}</code></span>
          </div>
        {/if}
      </div>
    </div>
  {:else if section === 'userspecies'}
    <div class="two-col">
      <div class="hub-card">
        <h3>Export User Species List (VUser.USysUserSpp)</h3>
        <div class="form-stack">
          <label>
            <span>Manifest Format</span>
            <select bind:value={userSppExportFormat} disabled={busy || operationHeld}>
              <option value="json">Signed JSON Manifest (with SHA-256)</option>
              <option value="csv">Portable CSV</option>
            </select>
          </label>
          <label>
            <span>Destination File Path (optional; leave blank for inline copy)</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={userSppExportPath} placeholder="/path/to/user_species.json" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-save-userspp-export disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save User Species List', userSppExportFormat === 'csv' ? 'user_species.csv' : 'user_species.json', [{ DisplayName: 'Species List (*.json, *.csv)', Pattern: '*.json;*.csv' }], (p) => { userSppExportPath = p; })}>Save As...</button>
            </div>
          </label>
          <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runUserSpeciesExport}>
            Export User Species
          </button>
        </div>
        {#if userSppExportResult}
          <div class="receipt-box">
            <strong>{userSppExportResult.rowCount} species | Payload SHA-256: <code>{userSppExportResult.payloadSha256.slice(0, 16)}...</code></strong>
            <textarea readonly rows={6} value={userSppExportResult.content}></textarea>
          </div>
        {/if}
      </div>

      <div class="hub-card">
        <h3>Import Crew Provisional Species with Collision Review</h3>
        <div class="form-stack">
          <label>
            <span>Source File Path (.json or .csv, optional if pasting below)</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={userSppImportPath} placeholder="/path/to/crew_species.json" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-browse-userspp-import disabled={busy || operationHeld} onclick={() => pickFilePath('open', 'Choose User Species File', '', [{ DisplayName: 'Species List (*.json, *.csv)', Pattern: '*.json;*.csv' }], (p) => { userSppImportPath = p; })}>Browse...</button>
            </div>
          </label>
          <label>
            <span>Or Paste JSON / CSV Payload</span>
            <textarea bind:value={userSppImportContent} rows={4} placeholder="Code,ScientificName,LifeForm,EnglishName" disabled={busy || operationHeld}></textarea>
          </label>
          <label>
            <span>Collision Policy for Existing VUser.USysUserSpp Codes</span>
            <select bind:value={userSppPolicy} disabled={busy || operationHeld}>
              <option value="skip">Skip existing user codes (preserve local definitions)</option>
              <option value="overwrite">Overwrite existing user codes (provincial VLists always protected)</option>
            </select>
          </label>
          <div class="form-row">
            <button type="button" class="btn-secondary" disabled={busy || operationHeld || !contextId} onclick={runUserSpeciesPreview}>
              Review Collisions
            </button>
            <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runUserSpeciesImport}>
              Import User Species
            </button>
          </div>
        </div>

        {#if userSppPreview}
          <div class="receipt-box">
            <p>
              <strong>Total:</strong> {userSppPreview.totalRows} |
              <strong>New:</strong> {userSppPreview.newCount} |
              <strong>User Collisions:</strong> {userSppPreview.userCollisions} |
              <strong>Protected Master Collisions:</strong> {userSppPreview.masterCollisions}
            </p>
          </div>
        {/if}
        {#if userSppImportResult}
          <div class="receipt-box success">
            <strong>Inserted: {userSppImportResult.insertedCount} | Overwritten: {userSppImportResult.overwrittenCount} | Skipped: {userSppImportResult.skippedCount}</strong>
          </div>
        {/if}
      </div>
    </div>
  {:else if section === 'analytics'}
    <div class="two-col">
      <div class="hub-card">
        <h3>Long Tidy CSV &amp; Wide Plot-by-Species Matrix CSV</h3>
        <label class="field-label-block">
          <span>Optional *_Lump Table Applied at Export Time</span>
          <div class="input-with-browse">
            <select
              class="grow"
              data-lump-select="analytics"
              value={selectedLumpOptionKey(csvLumpTable, csvLumpDbPath)}
              onchange={e => applySelectedLumpOption('csv', (e.currentTarget as HTMLSelectElement).value)}
              disabled={busy || operationHeld}
            >
              <option value="">None (raw unlumped species)</option>
              {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
                <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
              {/each}
            </select>
            <button
              type="button"
              class="btn-secondary"
              data-browse-lump-db="analytics"
              disabled={busy || operationHeld}
              onclick={() => void browseExternalLumpDatabase('csv')}
            >
              From .db…
            </button>
          </div>
        </label>

        <div class="sub-box">
          <h4>Long Tidy CSV (PlotNumber, SiteUnit, Layer, Species, ScientificName, Lifeform, Cover, Height, Collected)</h4>
          <div class="form-row">
            <input type="text" class="grow" bind:value={longCsvDest} placeholder="/path/to/veg_long.csv (optional for preview)" disabled={busy || operationHeld} />
            <button type="button" class="btn-secondary" data-save-long-csv disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save Long Tidy CSV', 'veg_long.csv', [{ DisplayName: 'CSV (*.csv)', Pattern: '*.csv' }], (p) => { longCsvDest = p; })}>Save As...</button>
            <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runLongCsvExport}>
              Export Long CSV
            </button>
          </div>
        </div>

        <div class="sub-box">
          <h4>Wide Plot x Species Matrix CSV</h4>
          <div class="form-row">
            <label>
              <span>Column Rollup</span>
              <select bind:value={wideLayerMode} disabled={busy || operationHeld}>
                <option value="rollup_all">Species Rollup (summed across layers, 99% cap)</option>
                <option value="strata_4">4-Strata Columns (Species_A, _B, _C, _D)</option>
                <option value="species_layer">Full Sub-Layer Columns (Species_A1..Ep)</option>
              </select>
            </label>
            <label class="check-inline">
              <input type="checkbox" bind:checked={wideZeroFill} disabled={busy || operationHeld} />
              <span>Zero-fill absences</span>
            </label>
            <label class="check-inline">
              <input type="checkbox" bind:checked={wideIncludeSiteUnit} disabled={busy || operationHeld} />
              <span>Include SiteUnit column</span>
            </label>
          </div>
          <div class="form-row">
            <input type="text" class="grow" bind:value={wideCsvDest} placeholder="/path/to/veg_wide_matrix.csv" disabled={busy || operationHeld} />
            <button type="button" class="btn-secondary" data-save-wide-csv disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save Wide Matrix CSV', 'veg_wide_matrix.csv', [{ DisplayName: 'CSV (*.csv)', Pattern: '*.csv' }], (p) => { wideCsvDest = p; })}>Save As...</button>
            <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runWideCsvExport}>
              Export Wide Matrix CSV
            </button>
          </div>
        </div>

        {#if csvOutcome}
          <div class="receipt-box">
            <strong>{csvOutcome.mode}: {csvOutcome.rowCount} rows x {csvOutcome.columnCount} cols ({csvOutcome.speciesCount} taxa)</strong>
            <textarea readonly rows={6} value={csvOutcome.previewCsv}></textarea>
          </div>
        {/if}
      </div>

      <div class="hub-card">
        <h3>Native R Serialization Format v2 (.rds) Export</h3>
        <p class="desc">Exports project tables (<code>env</code>, <code>admin</code>, <code>veg_long</code>, <code>humus</code>, <code>mineral</code>, <code>su</code>, <code>metadata</code>) as an .rds file ready for <code>readRDS()</code> in R, without requiring R to be installed.</p>
        <div class="form-stack">
          <label>
            <span>Optional *_Lump Table Applied to veg_long</span>
            <select
              data-lump-select="rds"
              value={selectedLumpOptionKey(csvLumpTable, csvLumpDbPath)}
              onchange={e => applySelectedLumpOption('csv', (e.currentTarget as HTMLSelectElement).value)}
              disabled={busy || operationHeld}
            >
              <option value="">None (raw unlumped species)</option>
              {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
                <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
              {/each}
            </select>
          </label>
          <label>
            <span>Destination .rds Path</span>
            <div class="input-with-browse">
              <input type="text" class="grow" bind:value={rdsDestPath} placeholder="/path/to/project_snapshot.rds" disabled={busy || operationHeld} />
              <button type="button" class="btn-secondary" data-save-rds disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save Native R .rds', 'project_snapshot.rds', [{ DisplayName: 'R Data (*.rds)', Pattern: '*.rds' }], (p) => { rdsDestPath = p; })}>Save As...</button>
            </div>
          </label>
          <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runRdsExport}>
            Export Native R .rds
          </button>
        </div>

        {#if rdsOutcome}
          <div class="receipt-box success">
            <strong>Exported {rdsOutcome.plotCount} plots ({rdsOutcome.byteSize} bytes) to <code>{rdsOutcome.path}</code></strong>
            <div class="table-scroll">
              <table class="compact-table">
                <thead><tr><th>R data.frame</th><th>Rows</th><th>Columns</th></tr></thead>
                <tbody>
                  {#each rdsOutcome.tables as tbl (tbl.name)}
                    <tr><td class="mono">{tbl.name}</td><td>{tbl.rowCount}</td><td>{tbl.columnCount}</td></tr>
                  {/each}
                </tbody>
              </table>
            </div>
          </div>
        {/if}
      </div>
    </div>
  {:else}
    <div class="hub-card">
      <h3>OGC GeoPackage 1.3 (.gpkg) Spatial &amp; Relational Exporter</h3>
      <p class="desc">Writes native SQLite GeoPackage Point features with full untruncated Env + Admin + SiteUnit columns, automatic Western Hemisphere longitude sign normalization, and optional non-spatial relational tables for QGIS and ArcGIS Pro. Coordinate bounds enforced: BC / Western North America [45..85 N, -170..-100 W] (positive Western longitudes [100..170] are normalized automatically).</p>
      <div class="form-row">
        <label class="grow">
          <span>Destination .gpkg File Path</span>
          <div class="input-with-browse">
            <input type="text" class="grow" bind:value={gpkgDestPath} placeholder="/path/to/bec_plots.gpkg" disabled={busy || operationHeld} />
            <button type="button" class="btn-secondary" data-save-gpkg disabled={busy || operationHeld} onclick={() => pickFilePath('save', 'Save GeoPackage (.gpkg)', 'bec_plots.gpkg', [{ DisplayName: 'GeoPackage (*.gpkg)', Pattern: '*.gpkg' }], (p) => { gpkgDestPath = p; })}>Save As...</button>
          </div>
        </label>
        <label>
          <span>Coordinate Reference System</span>
          <select bind:value={gpkgCrs} disabled={busy || operationHeld}>
            <option value="EPSG:3005">EPSG:3005 — NAD83 / BC Albers (Ministry Standard)</option>
            <option value="EPSG:4326">EPSG:4326 — NAD83 Geographic (Lon/Lat)</option>
          </select>
        </label>
      </div>
      <div class="form-row">
        <label class="check-inline">
          <input type="checkbox" bind:checked={gpkgIncludeAttributes} disabled={busy || operationHeld} />
          <span>Include veg, humus, mineral attribute tables</span>
        </label>
        <label class="check-inline">
          <input type="checkbox" bind:checked={gpkgIncludeUnlocated} disabled={busy || operationHeld} />
          <span>Include unlocated plots (NULL geometry)</span>
        </label>
        <label class="grow">
          <span>Optional *_Lump Table</span>
          <div class="input-with-browse">
            <select
              class="grow"
              data-lump-select="geopackage"
              value={selectedLumpOptionKey(gpkgLumpTable, gpkgLumpDbPath)}
              onchange={e => applySelectedLumpOption('gpkg', (e.currentTarget as HTMLSelectElement).value)}
              disabled={busy || operationHeld}
            >
              <option value="">None (raw unlumped species)</option>
              {#each discoveredLumpTables as item (item.tableName + '::' + item.databasePath)}
                <option value={lumpOptionValue(item, discoveredLumpTables)}>{formatLumpOptionLabel(item)}</option>
              {/each}
            </select>
            <button
              type="button"
              class="btn-secondary"
              data-browse-lump-db="geopackage"
              disabled={busy || operationHeld}
              onclick={() => void browseExternalLumpDatabase('gpkg')}
            >
              From .db…
            </button>
          </div>
        </label>
        <button type="button" class="btn-primary" disabled={busy || operationHeld || !contextId} onclick={runGeoPackageExport}>
          Export GeoPackage (.gpkg)
        </button>
      </div>

      {#if gpkgOutcome}
        <div class="receipt-box success">
          <strong>Exported {gpkgOutcome.featureCount} plot features ({gpkgOutcome.crs}, SRS {gpkgOutcome.srsId})</strong>
          <span>Located: {gpkgOutcome.locatedPlotCount} | Skipped unlocated: {gpkgOutcome.skippedUnlocatedCount} | Flipped positive West longitudes: {gpkgOutcome.normalizedWestLongitudes}</span>
          <span>Attribute tables: {gpkgOutcome.attributeTables.join(', ') || 'none'} | Path: <code>{gpkgOutcome.path}</code></span>
        </div>
      {/if}
    </div>
  {/if}
</section>

<style>
  .bcgov-interchange { display: grid; gap: 1rem; min-width: 0; }
  .bcgov-banner { background: #003366; color: #FFFFFF; border-bottom: 4px solid #FCBA19; border-radius: 4px; padding: 1rem 1.25rem; display: grid; gap: 0.75rem; min-width: 0; }
  .bcgov-banner h2 { margin: 0.15rem 0 0; font-size: 1.15rem; color: #FFFFFF; }
  .eyebrow-gold { margin: 0; font-size: 0.72rem; letter-spacing: 0.08em; color: #FCBA19; font-weight: 700; }
  .hub-tabs { display: flex; flex-wrap: wrap; gap: 0.45rem; }
  .hub-tabs button { background: rgba(255, 255, 255, 0.12); color: #FFFFFF; border: 1px solid rgba(255, 255, 255, 0.3); border-radius: 4px; padding: 0.42rem 0.8rem; font-size: 0.82rem; }
  .hub-tabs button.active { background: #FCBA19; color: #003366; border-color: #FCBA19; font-weight: 700; }
  .hub-tabs button.cancel-btn { background: #D8292F; border-color: #FBEAEA; margin-left: auto; }
  .two-col { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 320px), 1fr)); gap: 1rem; min-width: 0; }
  .hub-card { background: #FFFFFF; border: 1px solid #D8D8D8; border-top: 3px solid #003366; border-radius: 4px; padding: 1rem; display: grid; gap: 0.75rem; align-content: start; min-width: 0; }
  .hub-card h3 { margin: 0; color: #003366; font-size: 1rem; }
  .hub-card h4 { margin: 0.35rem 0 0.25rem; color: #003366; font-size: 0.86rem; }
  .desc { margin: 0; color: #474543; font-size: 0.83rem; line-height: 1.45; }
  .form-row { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: end; min-width: 0; }
  .form-stack { display: grid; gap: 0.6rem; min-width: 0; }
  .form-row label, .form-stack label, .field-label-block { display: grid; gap: 0.25rem; font-size: 0.8rem; color: #313132; min-width: 0; }
  .input-with-browse { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; min-width: 0; }
  .grow { flex: 1 1 200px; min-width: 0; }
  .check-inline { display: inline-flex !important; flex-direction: row; align-items: center; gap: 0.4rem; padding-bottom: 0.35rem; }
  input:not([type="checkbox"]), select, textarea { padding: 0.45rem 0.6rem; border: 1px solid #9F9F9F; border-radius: 4px; font-size: 0.84rem; font-family: inherit; color: #313132; background: #FFFFFF; min-width: 0; max-width: 100%; box-sizing: border-box; }
  textarea { font-family: var(--font-mono, monospace); font-size: 0.78rem; width: 100%; }
  .btn-primary { background: #003366; color: #FFFFFF; border: 1px solid #003366; border-radius: 4px; padding: 0.48rem 0.9rem; font-weight: 600; font-size: 0.83rem; }
  .btn-secondary { background: #FFFFFF; color: #003366; border: 1px solid #003366; border-radius: 4px; padding: 0.48rem 0.9rem; font-weight: 600; font-size: 0.83rem; }
  .sub-box { border: 1px solid #D8D8D8; border-left: 3px solid #FCBA19; padding: 0.65rem; border-radius: 4px; display: grid; gap: 0.5rem; min-width: 0; }
  .receipt-box { background: #F2F2F2; border: 1px solid #D8D8D8; border-left: 4px solid #003366; padding: 0.65rem 0.8rem; border-radius: 4px; display: grid; gap: 0.35rem; font-size: 0.82rem; min-width: 0; overflow-wrap: anywhere; }
  .receipt-box.success { background: #EBF5ED; border-left-color: #2E8540; }
  .table-scroll { overflow-x: auto; max-width: 100%; }
  .compact-table { width: 100%; min-width: 0; border-collapse: collapse; font-size: 0.78rem; }
  .compact-table th, .compact-table td { padding: 0.35rem 0.5rem; border-bottom: 1px solid #D8D8D8; white-space: normal; text-align: left; }
  .mono { font-family: var(--vpro-font-mono, var(--font-mono, monospace)); font-variant-numeric: tabular-nums; }
  .xml-check-box { font-size: 0.8rem; border-top: 1px solid #D8D8D8; padding-top: 0.5rem; }
  .ok-text { color: #2E8540; margin: 0.3rem 0 0; font-weight: 600; }
  @media (pointer: coarse) {
    .hub-tabs button,
    .btn-primary,
    .btn-secondary,
    input:not([type="checkbox"]),
    select {
      min-height: 44px;
    }
  }
</style>
