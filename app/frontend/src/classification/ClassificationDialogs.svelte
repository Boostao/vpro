<script lang="ts">
  import type {
    ClassificationBackendPort,
    CreateSUFromEnvFieldsResult,
    SUFromEnvMode,
  } from './classificationExplorer';

  type DialogKind = 'none' | 'new_su' | 'save_su_as' | 'su_from_env' | 'new_hierarchy' | 'save_hierarchy_as';

  interface Props {
    activeDialog: DialogKind;
    effectiveContextId: string;
    activeHierarchy: string;
    port: ClassificationBackendPort;
    mutating: boolean;
    newSUName: string;
    newSUDestination: 'project' | 'new_file';
    newSUFilePath: string;
    populateAllPlots: boolean;
    seedFromUserSU: boolean;
    onClose: () => void;
    onSubmitCreateSU: () => void;
    onMutatingChange: (v: boolean) => void;
    onError: (msg: string) => void;
    onStatus: (msg: string) => void;
    onActivated: (contextId: string, newState: unknown) => void;
    onReloadSU: () => Promise<void>;
    onReloadHierarchy: () => Promise<void>;
  }

  let {
    activeDialog,
    effectiveContextId,
    activeHierarchy,
    port,
    mutating,
    newSUName = $bindable(),
    newSUDestination = $bindable(),
    newSUFilePath = $bindable(),
    populateAllPlots = $bindable(),
    seedFromUserSU = $bindable(),
    onClose,
    onSubmitCreateSU,
    onMutatingChange,
    onError,
    onStatus,
    onActivated,
    onReloadSU,
    onReloadHierarchy,
  }: Props = $props();

  const AVAILABLE_ENV_FIELDS = [
    'Zone',
    'SubZone',
    'SiteSeries',
    'SiteModifier1',
    'MoistureRegime',
    'NutrientRegime',
    'StructuralStage',
    'Ecosection',
    'UserSiteUnit',
    'GIS_BGC',
  ];

  let saveAsNewName = $state('');
  let saveAsDestination = $state<'project' | 'new_file'>('project');
  let saveAsFilePath = $state('');

  let envConcatFields = $state<string[]>(['Zone', 'SubZone', 'SiteSeries']);
  let envSeparator = $state('/');
  let envUseBECSlash = $state(true);
  let envConcatMode = $state<SUFromEnvMode>('fill_unassigned_only');
  let envNewSUName = $state('');
  let envDestination = $state<'project' | 'new_file'>('project');
  let envFilePath = $state('');
  let envScopeToExistingOnly = $state(false);
  let envSkipIncomplete = $state(false);
  let envConcatPreview = $state.raw<CreateSUFromEnvFieldsResult | null>(null);

  let newHierarchyTableName = $state('');
  let newHierarchyDestination = $state<'project' | 'new_file'>('project');
  let newHierarchyFilePath = $state('');

  let saveHierarchyAsName = $state('');
  let saveHierarchyAsDestination = $state<'project' | 'new_file'>('project');
  let saveHierarchyAsFilePath = $state('');

  async function browseNewSQLitePath(suggestedName: string, applyPath: (picked: string) => void) {
    if (!effectiveContextId || !port.chooseNewSQLiteProjectFile) return;
    try {
      const picked = await port.chooseNewSQLiteProjectFile(
        effectiveContextId,
        suggestedName.trim() || 'StandaloneTable'
      );
      if (picked) applyPath(picked);
    } catch (err) {
      onError(`Select external SQLite path failed: ${String(err)}`);
    }
  }

  async function submitSaveSUAs() {
    if (!saveAsNewName.trim() || mutating) return;
    if (saveAsDestination === 'new_file' && !saveAsFilePath.trim()) {
      onError('Enter or browse an external .db file path for Save SU As.');
      return;
    }
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.saveSUTableAs(effectiveContextId, {
        sourceSu: '',
        newName: saveAsNewName.trim(),
        destination: saveAsDestination,
        filePath: saveAsDestination === 'new_file' ? saveAsFilePath.trim() : '',
        activate: true,
      });
      if (res.activated) onActivated(res.contextId, res.newState);
      onClose();
      saveAsNewName = '';
      saveAsFilePath = '';
      saveAsDestination = 'project';
      onStatus(`Saved SU copy as ${res.tableName} (${res.plotCount} plot(s)).`);
      await onReloadSU();
    } catch (err) {
      onError(`Save SU As failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function runSUFromEnv(previewOnly: boolean) {
    if (envConcatFields.length === 0 || mutating) return;
    if (envConcatMode === 'new_table' && envDestination === 'new_file' && !envFilePath.trim()) {
      onError('Enter or browse an external .db file path when writing a new SU file.');
      return;
    }
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.createSUFromEnvFields(effectiveContextId, {
        fields: $state.snapshot(envConcatFields),
        separator: envSeparator,
        useBecSlashFormat: envUseBECSlash,
        mode: envConcatMode,
        targetSuName: envConcatMode === 'new_table' ? envNewSUName.trim() : undefined,
        destination: envConcatMode === 'new_table' ? envDestination : 'project',
        filePath:
          envConcatMode === 'new_table' && envDestination === 'new_file'
            ? envFilePath.trim()
            : undefined,
        scopeToExistingSuRowsOnly: envScopeToExistingOnly,
        skipIncompleteRows: envSkipIncomplete,
        previewOnly,
        activate: envConcatMode === 'new_table',
      });
      if (previewOnly) {
        envConcatPreview = res;
      } else {
        if (res.activated) onActivated(res.contextId, res.newState);
        envConcatPreview = null;
        onClose();
        onStatus(`Populated ${res.tableName}: ${res.insertedCount} inserted, ${res.updatedCount} updated, ${res.preservedCount} preserved.`);
        await onReloadSU();
      }
    } catch (err) {
      onError(`Create SU from Env Fields failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function submitCreateHierarchyTable() {
    if (!newHierarchyTableName.trim() || mutating) return;
    if (newHierarchyDestination === 'new_file' && !newHierarchyFilePath.trim()) {
      onError('Enter or browse an external .db file path for the new hierarchy.');
      return;
    }
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.createHierarchyTable(effectiveContextId, {
        name: newHierarchyTableName.trim(),
        destination: newHierarchyDestination,
        filePath: newHierarchyDestination === 'new_file' ? newHierarchyFilePath.trim() : '',
        activate: true,
      });
      if (res.activated) onActivated(res.contextId, res.newState);
      onClose();
      newHierarchyTableName = '';
      newHierarchyFilePath = '';
      newHierarchyDestination = 'project';
      onStatus(`Created and activated ${res.tableName}.`);
      await onReloadHierarchy();
    } catch (err) {
      onError(`Create Hierarchy failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }

  async function submitSaveHierarchyAs() {
    if (!saveHierarchyAsName.trim() || !port.saveHierarchyTableAs || mutating) return;
    if (saveHierarchyAsDestination === 'new_file' && !saveHierarchyAsFilePath.trim()) {
      onError('Enter or browse an external .db file path for Save Hierarchy As.');
      return;
    }
    onMutatingChange(true);
    onError('');
    try {
      const res = await port.saveHierarchyTableAs(effectiveContextId, {
        sourceHierarchy: activeHierarchy,
        newName: saveHierarchyAsName.trim(),
        destination: saveHierarchyAsDestination,
        filePath:
          saveHierarchyAsDestination === 'new_file' ? saveHierarchyAsFilePath.trim() : '',
        activate: true,
      });
      if (res?.activated) onActivated(res.contextId, res.newState);
      onClose();
      saveHierarchyAsName = '';
      saveHierarchyAsFilePath = '';
      saveHierarchyAsDestination = 'project';
      onStatus(res ? `Saved hierarchy copy as ${res.tableName}.` : 'Saved hierarchy table copy.');
      await onReloadHierarchy();
    } catch (err) {
      onError(`Save Hierarchy As failed: ${String(err)}`);
    } finally {
      onMutatingChange(false);
    }
  }
</script>

{#if activeDialog === 'new_su'}
  <section class="vpro-cls-dialog" aria-label="Create New Site Unit Table">
    <h3>Create Standalone Site Unit (*_SU) Table</h3>
    <div class="vpro-cls-dialog-row">
      <label>
        <span>SU Name (without _SU)</span>
        <input type="text" bind:value={newSUName} placeholder="e.g. Working2026" />
      </label>
      <label>
        <span>Destination</span>
        <select bind:value={newSUDestination}>
          <option value="project">Active Project DB</option>
          <option value="new_file">External .db File</option>
        </select>
      </label>
      {#if newSUDestination === 'new_file'}
        <label class="vpro-cls-filepath-field">
          <span>External .db Path</span>
          <div class="vpro-cls-inline-browse">
            <input type="text" bind:value={newSUFilePath} placeholder="/path/to/WorkingSU.db" />
            {#if port.chooseNewSQLiteProjectFile}
              <button type="button" class="vpro-btn-secondary" onclick={() => browseNewSQLitePath(newSUName || 'WorkingSU', picked => { newSUFilePath = picked; })}>
                Browse...
              </button>
            {/if}
          </div>
        </label>
      {/if}
      <label class="vpro-cls-check"><input type="checkbox" bind:checked={populateAllPlots} /><span>Include all project plots</span></label>
      <label class="vpro-cls-check"><input type="checkbox" bind:checked={seedFromUserSU} disabled={!populateAllPlots} /><span>Seed from Admin.UserSiteUnit</span></label>
      <button type="button" class="vpro-btn-primary" disabled={mutating} onclick={onSubmitCreateSU}>Create &amp; Activate</button>
      <button type="button" class="vpro-btn-secondary" onclick={onClose}>Cancel</button>
    </div>
  </section>
{:else if activeDialog === 'save_su_as'}
  <section class="vpro-cls-dialog" aria-label="Save Site Unit Table As">
    <h3>Save Active SU Table Under New Name</h3>
    <div class="vpro-cls-dialog-row">
      <label><span>New SU Name</span><input type="text" bind:value={saveAsNewName} placeholder="e.g. RegionalSubset" /></label>
      <label>
        <span>Destination</span>
        <select bind:value={saveAsDestination}>
          <option value="project">Active Project DB</option>
          <option value="new_file">External .db File</option>
        </select>
      </label>
      {#if saveAsDestination === 'new_file'}
        <label class="vpro-cls-filepath-field">
          <span>External .db Path</span>
          <div class="vpro-cls-inline-browse">
            <input type="text" bind:value={saveAsFilePath} placeholder="/path/to/RegionalSubset.db" />
            {#if port.chooseNewSQLiteProjectFile}
              <button type="button" class="vpro-btn-secondary" onclick={() => browseNewSQLitePath(saveAsNewName || 'RegionalSubset', picked => { saveAsFilePath = picked; })}>
                Browse...
              </button>
            {/if}
          </div>
        </label>
      {/if}
      <button type="button" class="vpro-btn-primary" disabled={mutating} onclick={submitSaveSUAs}>Save Copy &amp; Activate</button>
      <button type="button" class="vpro-btn-secondary" onclick={onClose}>Cancel</button>
    </div>
  </section>
{:else if activeDialog === 'su_from_env'}
  <section class="vpro-cls-dialog" aria-label="Create Site Units from Environment Fields">
    <h3>Populate Site Units from Concatenated Env / Admin Fields</h3>
    <div class="vpro-cls-dialog-row">
      <label>
        <span>Target Mode</span>
        <select bind:value={envConcatMode}>
          <option value="fill_unassigned_only">Existing SU — Fill Unassigned Only</option>
          <option value="overwrite">Existing SU — Overwrite All Plots</option>
          <option value="new_table">Create New *_SU Table</option>
        </select>
      </label>
      {#if envConcatMode === 'new_table'}
        <label><span>New SU Table Name</span><input type="text" bind:value={envNewSUName} placeholder="e.g. FieldBEC" /></label>
        <label>
          <span>Destination</span>
          <select bind:value={envDestination}>
            <option value="project">Active Project DB</option>
            <option value="new_file">External .db File</option>
          </select>
        </label>
        {#if envDestination === 'new_file'}
          <label class="vpro-cls-filepath-field">
            <span>External .db Path</span>
            <div class="vpro-cls-inline-browse">
              <input type="text" bind:value={envFilePath} placeholder="/path/to/FieldBEC.db" />
              {#if port.chooseNewSQLiteProjectFile}
                <button type="button" class="vpro-btn-secondary" onclick={() => browseNewSQLitePath(envNewSUName || 'FieldBEC', picked => { envFilePath = picked; })}>
                  Browse...
                </button>
              {/if}
            </div>
          </label>
        {/if}
      {/if}
      <label><span>Separator</span><input type="text" class="vpro-cls-sep-input" bind:value={envSeparator} /></label>
      <label class="vpro-cls-check"><input type="checkbox" bind:checked={envUseBECSlash} /><span>BEC format (Zone+SubZone + "/" + SiteSeries)</span></label>
      <label class="vpro-cls-check"><input type="checkbox" bind:checked={envScopeToExistingOnly} /><span>Limit to plots already in SU table</span></label>
      <label class="vpro-cls-check"><input type="checkbox" bind:checked={envSkipIncomplete} /><span>Skip incomplete rows</span></label>
    </div>

    <div class="vpro-cls-field-chips" aria-label="Selected Env/Admin Columns">
      {#each AVAILABLE_ENV_FIELDS as fieldName (fieldName)}
        {@const selected = envConcatFields.includes(fieldName)}
        <button
          type="button"
          class="vpro-cls-chip"
          class:selected
          onclick={() => {
            envConcatFields = selected ? envConcatFields.filter(f => f !== fieldName) : [...envConcatFields, fieldName];
          }}
        >
          {selected ? `${envConcatFields.indexOf(fieldName) + 1}. ` : '+ '}{fieldName}
        </button>
      {/each}
    </div>

    <div class="vpro-cls-dialog-row">
      <button type="button" class="vpro-btn-secondary" disabled={mutating || envConcatFields.length === 0} onclick={() => runSUFromEnv(true)}>Preview Assignments</button>
      <button type="button" class="vpro-btn-primary" disabled={mutating || envConcatFields.length === 0} onclick={() => runSUFromEnv(false)}>Apply to SU</button>
      <button type="button" class="vpro-btn-secondary" onclick={onClose}>Close</button>
    </div>

    {#if envConcatPreview}
      <p class="vpro-cls-preview-note">
        Preview for <code>{envConcatPreview.tableName}</code>:
        <strong>{envConcatPreview.insertedCount}</strong> insert,
        <strong>{envConcatPreview.updatedCount}</strong> update,
        <strong>{envConcatPreview.preservedCount}</strong> preserved,
        <strong>{envConcatPreview.skippedCount}</strong> blank skipped.
      </p>
    {/if}
  </section>
{:else if activeDialog === 'new_hierarchy'}
  <section class="vpro-cls-dialog" aria-label="Create New Hierarchy Table">
    <h3>Create Standalone *_Hierarchy Table</h3>
    <div class="vpro-cls-dialog-row">
      <label><span>Hierarchy Name (without _Hierarchy)</span><input type="text" bind:value={newHierarchyTableName} placeholder="e.g. Coast2026" /></label>
      <label>
        <span>Destination</span>
        <select bind:value={newHierarchyDestination}>
          <option value="project">Active Project DB</option>
          <option value="new_file">External .db File</option>
        </select>
      </label>
      {#if newHierarchyDestination === 'new_file'}
        <label class="vpro-cls-filepath-field">
          <span>External .db Path</span>
          <div class="vpro-cls-inline-browse">
            <input type="text" bind:value={newHierarchyFilePath} placeholder="/path/to/Coast2026_Hierarchy.db" />
            {#if port.chooseNewSQLiteProjectFile}
              <button type="button" class="vpro-btn-secondary" onclick={() => browseNewSQLitePath(newHierarchyTableName || 'Coast2026', picked => { newHierarchyFilePath = picked; })}>
                Browse...
              </button>
            {/if}
          </div>
        </label>
      {/if}
      <button type="button" class="vpro-btn-primary" disabled={mutating} onclick={submitCreateHierarchyTable}>Create &amp; Activate</button>
      <button type="button" class="vpro-btn-secondary" onclick={onClose}>Cancel</button>
    </div>
  </section>
{:else if activeDialog === 'save_hierarchy_as'}
  <section class="vpro-cls-dialog" aria-label="Save Hierarchy Table As">
    <h3>Save Active Hierarchy Table As</h3>
    <div class="vpro-cls-dialog-row">
      <label><span>New Hierarchy Name</span><input type="text" bind:value={saveHierarchyAsName} placeholder="e.g. CoastBackup" /></label>
      <label>
        <span>Destination</span>
        <select bind:value={saveHierarchyAsDestination}>
          <option value="project">Active Project DB</option>
          <option value="new_file">External .db File</option>
        </select>
      </label>
      {#if saveHierarchyAsDestination === 'new_file'}
        <label class="vpro-cls-filepath-field">
          <span>External .db Path</span>
          <div class="vpro-cls-inline-browse">
            <input type="text" bind:value={saveHierarchyAsFilePath} placeholder="/path/to/CoastBackup.db" />
            {#if port.chooseNewSQLiteProjectFile}
              <button type="button" class="vpro-btn-secondary" onclick={() => browseNewSQLitePath(saveHierarchyAsName || 'CoastBackup', picked => { saveHierarchyAsFilePath = picked; })}>
                Browse...
              </button>
            {/if}
          </div>
        </label>
      {/if}
      <button type="button" class="vpro-btn-primary" disabled={mutating || !saveHierarchyAsName.trim()} onclick={submitSaveHierarchyAs}>Save Copy &amp; Activate</button>
      <button type="button" class="vpro-btn-secondary" onclick={onClose}>Cancel</button>
    </div>
  </section>
{/if}
