<script lang="ts">
  import type {
    ClassificationBackendPort,
    UserSiteUnitEntry,
    UserSiteUnitImportResult,
  } from './classificationExplorer';

  interface Props {
    effectiveContextId: string;
    project: string;
    port: ClassificationBackendPort;
    userSiteUnits: UserSiteUnitEntry[];
    selectedPlots: string[];
    mutating: boolean;
    onLoadUserSiteUnitList: () => Promise<void>;
    onAssignPlots: (plots: string[], targetUnit: string) => void;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
  }

  let {
    effectiveContextId,
    project,
    port,
    userSiteUnits,
    selectedPlots,
    mutating,
    onLoadUserSiteUnitList,
    onAssignPlots,
    onMutatingChange,
    onError,
    onStatus,
  }: Props = $props();

  let userSUFilter = $state('');
  let userSULoading = $state(false);
  let userSUFormId = $state<number | null>(null);
  let userSUSeries = $state('');
  let userSULongName = $state('');
  let userSUSciName = $state('');
  let userSULevel = $state<number>(11);
  let userSUCSVText = $state('');
  let userSUOverwrite = $state(false);
  let userSUImportResult = $state.raw<UserSiteUnitImportResult | null>(null);

  const filteredUserSiteUnits = $derived(
    userSUFilter.trim()
      ? userSiteUnits.filter(entry => {
          const needle = userSUFilter.trim().toLowerCase();
          return (
            entry.siteSeries.toLowerCase().includes(needle) ||
            entry.siteSeriesLongName.toLowerCase().includes(needle) ||
            entry.siteSeriesScientificName.toLowerCase().includes(needle)
          );
        })
      : userSiteUnits
  );

  function resetUserSiteUnitForm() {
    userSUFormId = null;
    userSUSeries = '';
    userSULongName = '';
    userSUSciName = '';
    userSULevel = 11;
  }

  function editUserSiteUnitEntry(entry: UserSiteUnitEntry) {
    userSUFormId = entry.id;
    userSUSeries = entry.siteSeries;
    userSULongName = entry.siteSeriesLongName;
    userSUSciName = entry.siteSeriesScientificName;
    userSULevel = entry.level || 11;
  }

  async function refreshList() {
    userSULoading = true;
    try {
      await onLoadUserSiteUnitList();
    } finally {
      userSULoading = false;
    }
  }

  async function submitUserSiteUnitEntry() {
    if (!effectiveContextId || !port.saveUserSiteUnitEntry || !userSUSeries.trim() || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const saved = await port.saveUserSiteUnitEntry(effectiveContextId, {
        id: userSUFormId,
        siteSeries: userSUSeries.trim(),
        siteSeriesLongName: userSULongName.trim(),
        siteSeriesScientificName: userSUSciName.trim(),
        level: Number.isFinite(userSULevel) ? userSULevel : 11,
      });
      onStatus(saved ? `Saved UserSiteUnit "${saved.siteSeries}".` : 'Saved UserSiteUnit entry.');
      resetUserSiteUnitForm();
      await onLoadUserSiteUnitList();
    } catch (err) {
      onError(`Save UserSiteUnit failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function removeUserSiteUnitEntry(entry: UserSiteUnitEntry) {
    if (!effectiveContextId || !port.deleteUserSiteUnitEntry || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      await port.deleteUserSiteUnitEntry(effectiveContextId, { id: entry.id });
      if (userSUFormId === entry.id) resetUserSiteUnitForm();
      onStatus(`Deleted UserSiteUnit "${entry.siteSeries}".`);
      await onLoadUserSiteUnitList();
    } catch (err) {
      onError(`Delete UserSiteUnit failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function exportUserSiteUnitsCSV() {
    if (!effectiveContextId || !port.exportUserSiteUnitListCSV || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const csv = await port.exportUserSiteUnitListCSV(effectiveContextId);
      userSUCSVText = csv;
      if (typeof Blob !== 'undefined' && typeof URL !== 'undefined' && typeof document !== 'undefined') {
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `${(project || 'UserSiteUnitList').replace(/[^A-Za-z0-9_-]+/g, '_')}_UserSiteUnits.csv`;
        link.click();
        URL.revokeObjectURL(url);
      }
      onStatus('Exported UserSiteUnitList CSV.');
    } catch (err) {
      onError(`Export UserSiteUnit CSV failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function handleUserSUCSVFile(event: Event) {
    const file = (event.currentTarget as HTMLInputElement).files?.[0];
    if (file) userSUCSVText = await file.text();
  }

  async function importUserSiteUnitsCSV() {
    if (!effectiveContextId || !port.importUserSiteUnitListCSV || !userSUCSVText.trim() || mutating) return;
    onMutatingChange(true);
    onError('');
    try {
      const result = await port.importUserSiteUnitListCSV(effectiveContextId, userSUCSVText, userSUOverwrite);
      userSUImportResult = result;
      onStatus(
        result
          ? `Imported UserSiteUnit CSV: ${result.inserted} inserted, ${result.updated} updated, ${result.skipped} skipped (${result.total} total).`
          : 'Imported UserSiteUnit CSV.'
      );
      await onLoadUserSiteUnitList();
    } catch (err) {
      onError(`Import UserSiteUnit CSV failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }
</script>

<div class="vpro-cls-user-su-panel" aria-label="User Site Unit List Editor">
  <div class="vpro-cls-subtoolbar">
    <input type="search" class="vpro-cls-filter" placeholder="Filter UserSiteUnitList..." bind:value={userSUFilter} />
    <button type="button" class="vpro-btn-secondary" disabled={userSULoading} onclick={refreshList}>Refresh</button>
    {#if port.exportUserSiteUnitListCSV}
      <button type="button" class="vpro-btn-secondary" disabled={mutating} onclick={exportUserSiteUnitsCSV}>Export CSV</button>
    {/if}
  </div>

  <div class="vpro-cls-dialog-row">
    <label><span>SiteSeries</span><input type="text" class="mono" bind:value={userSUSeries} placeholder="e.g. CWHvm1/01" /></label>
    <label><span>Long Name</span><input type="text" bind:value={userSULongName} placeholder="Descriptive unit name" /></label>
    <label><span>Scientific Name</span><input type="text" bind:value={userSUSciName} placeholder="Plant association" /></label>
    <label><span>Level</span><input type="number" class="vpro-cls-sep-input" bind:value={userSULevel} min={1} max={11} /></label>
    <button type="button" class="vpro-btn-primary" disabled={mutating || !userSUSeries.trim() || !port.saveUserSiteUnitEntry} onclick={submitUserSiteUnitEntry}>
      {userSUFormId !== null ? 'Update Entry' : 'Add Entry'}
    </button>
    {#if userSUFormId !== null}
      <button type="button" class="vpro-btn-secondary" onclick={resetUserSiteUnitForm}>Cancel Edit</button>
    {/if}
  </div>

  <div class="vpro-cls-bec-list">
    <div class="table-scroll">
      <table class="vpro-cls-spp-table">
        <thead>
          <tr><th>SiteSeries</th><th>Long Name</th><th>Scientific</th><th>Lvl</th><th>Actions</th></tr>
        </thead>
        <tbody>
          {#each filteredUserSiteUnits as entry (entry.id)}
            <tr>
              <td class="mono"><strong>{entry.siteSeries}</strong></td>
              <td>{entry.siteSeriesLongName}</td>
              <td>{entry.siteSeriesScientificName}</td>
              <td class="mono">{entry.level}</td>
              <td class="vpro-cls-actions">
                <button type="button" class="vpro-btn-mini" disabled={selectedPlots.length === 0 || mutating} onclick={() => onAssignPlots(selectedPlots, entry.siteSeries)}>
                  Assign ({selectedPlots.length})
                </button>
                <button type="button" class="vpro-btn-mini" onclick={() => editUserSiteUnitEntry(entry)}>Edit</button>
                {#if port.deleteUserSiteUnitEntry}
                  <button type="button" class="vpro-btn-mini" disabled={mutating} onclick={() => removeUserSiteUnitEntry(entry)}>Delete</button>
                {/if}
              </td>
            </tr>
          {/each}
          {#if filteredUserSiteUnits.length === 0}
            <tr>
              <td colspan="5" class="vpro-cls-empty">
                {userSULoading ? 'Loading UserSiteUnitList...' : 'No UserSiteUnitList entries stored yet.'}
              </td>
            </tr>
          {/if}
        </tbody>
      </table>
    </div>
  </div>

  {#if port.importUserSiteUnitListCSV}
    <div class="vpro-cls-csv-import">
      <div class="vpro-cls-subtoolbar">
        <label class="vpro-cls-check"><input type="checkbox" bind:checked={userSUOverwrite} /><span>Overwrite matching SiteSeries</span></label>
        <input type="file" accept=".csv,text/csv" onchange={handleUserSUCSVFile} />
        <button type="button" class="vpro-btn-secondary" disabled={mutating || !userSUCSVText.trim()} onclick={importUserSiteUnitsCSV}>Import CSV</button>
      </div>
      <textarea rows="3" class="vpro-cls-csv-box" placeholder="Paste or load UserSiteUnitList CSV rows..." bind:value={userSUCSVText}></textarea>
      {#if userSUImportResult}
        <p class="vpro-cls-preview-note">
          Imported: {userSUImportResult.inserted} inserted · {userSUImportResult.updated}
          updated · {userSUImportResult.skipped} skipped.
        </p>
      {/if}
    </div>
  {/if}
</div>
