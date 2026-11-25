<script lang="ts">
  import { IS_WEB_READONLY } from '../web/runtimeMode';
  import type {
    FileDialogFilter,
    InterchangeHubPort,
    UserSpeciesCollisionPolicy,
    UserSpeciesExportResult,
    UserSpeciesImportPreview,
    UserSpeciesImportResult,
  } from './interchangeHub';

  let {
    contextId,
    busy,
    operationHeld,
    port,
    onPickFilePath,
    onRunHubRpc,
  }: {
    contextId: string;
    busy: boolean;
    operationHeld: boolean;
    port: InterchangeHubPort;
    onPickFilePath: (
      mode: 'open' | 'save',
      title: string,
      defaultFilename: string,
      filters: FileDialogFilter[],
      assign: (chosen: string) => void | Promise<void>
    ) => Promise<void>;
    onRunHubRpc: <T>(
      errorTitle: string,
      call: (owner: string) => Promise<T>,
      onSuccess: (res: T) => void
    ) => Promise<void>;
  } = $props();

  let userSppExportFormat = $state<'json' | 'csv'>('json');
  let userSppExportPath = $state('');
  let userSppExportResult = $state.raw<UserSpeciesExportResult | null>(null);

  let userSppImportPath = $state('');
  let userSppImportContent = $state('');
  let userSppPolicy = $state<UserSpeciesCollisionPolicy>('skip');
  let userSppPreview = $state.raw<UserSpeciesImportPreview | null>(null);
  let userSppImportResult = $state.raw<UserSpeciesImportResult | null>(null);

  async function runUserSpeciesExport() {
    const webReadOnly = typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY;
    const payload = $state.snapshot({
      format: userSppExportFormat,
      destinationPath:
        webReadOnly && !userSppExportPath.trim()
          ? userSppExportFormat === 'csv'
            ? 'user_species.csv'
            : 'user_species.json'
          : userSppExportPath.trim(),
    });
    await onRunHubRpc(
      'User species export failed',
      (owner) => port.exportUserSpeciesList(owner, payload),
      (res) => {
        userSppExportResult = res;
      }
    );
  }

  async function runUserSpeciesPreview() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const payload = $state.snapshot({
      sourcePath: userSppImportPath.trim(),
      content: userSppImportContent,
      collisionPolicy: userSppPolicy,
    });
    await onRunHubRpc(
      'User species preview failed',
      (owner) => port.previewUserSpeciesImport(owner, payload),
      (res) => {
        userSppPreview = res;
      }
    );
  }

  async function runUserSpeciesImport() {
    if (typeof IS_WEB_READONLY !== 'undefined' && IS_WEB_READONLY) return;
    const payload = $state.snapshot({
      sourcePath: userSppImportPath.trim(),
      content: userSppImportContent,
      collisionPolicy: userSppPolicy,
    });
    await onRunHubRpc(
      'User species import failed',
      (owner) => port.importUserSpeciesList(owner, payload),
      (res) => {
        userSppImportResult = res;
        userSppPreview = res.preview;
      }
    );
  }
</script>

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
      {#if !IS_WEB_READONLY}
        <label>
          <span>Destination File Path (optional; leave blank for inline copy)</span>
          <div class="input-with-browse">
            <input
              type="text"
              class="grow"
              bind:value={userSppExportPath}
              placeholder="/path/to/user_species.json"
              disabled={busy || operationHeld}
            />
            <button
              type="button"
              class="btn-secondary"
              data-save-userspp-export
              disabled={busy || operationHeld}
              onclick={() =>
                onPickFilePath(
                  'save',
                  'Save User Species List',
                  userSppExportFormat === 'csv' ? 'user_species.csv' : 'user_species.json',
                  [{ DisplayName: 'Species List (*.json, *.csv)', Pattern: '*.json;*.csv' }],
                  (p) => {
                    userSppExportPath = p;
                  }
                )}
            >
              Save As...
            </button>
          </div>
        </label>
      {/if}
      <button
        type="button"
        class="btn-primary"
        disabled={busy || operationHeld || !contextId}
        onclick={runUserSpeciesExport}
      >
        {#if busy}
          {IS_WEB_READONLY ? 'Preparing download...' : 'Exporting User Species...'}
        {:else}
          {IS_WEB_READONLY ? 'Download User Species' : 'Export User Species'}
        {/if}
      </button>
    </div>
    {#if userSppExportResult}
      <div class="receipt-box">
        <strong>
          {userSppExportResult.rowCount} species | Payload SHA-256:
          <code>{userSppExportResult.payloadSha256.slice(0, 16)}...</code>
        </strong>
        <textarea aria-label="Exported user species payload" readonly rows={6} value={userSppExportResult.content}
        ></textarea>
      </div>
    {/if}
  </div>

  {#if !IS_WEB_READONLY}
    <div class="hub-card">
      <h3>Import Crew Provisional Species with Collision Review</h3>
    <div class="form-stack">
      <label>
        <span>Source File Path (.json or .csv, optional if pasting below)</span>
        <div class="input-with-browse">
          <input
            type="text"
            class="grow"
            bind:value={userSppImportPath}
            placeholder="/path/to/crew_species.json"
            disabled={busy || operationHeld}
          />
          <button
            type="button"
            class="btn-secondary"
            data-browse-userspp-import
            disabled={busy || operationHeld}
            onclick={() =>
              onPickFilePath(
                'open',
                'Choose User Species File',
                '',
                [{ DisplayName: 'Species List (*.json, *.csv)', Pattern: '*.json;*.csv' }],
                (p) => {
                  userSppImportPath = p;
                }
              )}
          >
            Browse...
          </button>
        </div>
      </label>
      <label>
        <span>Or Paste JSON / CSV Payload</span>
        <textarea
          bind:value={userSppImportContent}
          rows={4}
          placeholder="Code,ScientificName,LifeForm,EnglishName"
          disabled={busy || operationHeld}></textarea>
      </label>
      <label>
        <span>Collision Policy for Existing VUser.USysUserSpp Codes</span>
        <select bind:value={userSppPolicy} disabled={busy || operationHeld}>
          <option value="skip">Skip existing user codes (preserve local definitions)</option>
          <option value="overwrite">Overwrite existing user codes (provincial VLists always protected)</option>
        </select>
      </label>
      <div class="form-row">
        <button
          type="button"
          class="btn-secondary"
          disabled={busy || operationHeld || !contextId}
          onclick={runUserSpeciesPreview}
        >
          Review Collisions
        </button>
        <button
          type="button"
          class="btn-primary"
          disabled={busy || operationHeld || !contextId}
          onclick={runUserSpeciesImport}
        >
          Import User Species
        </button>
      </div>
    </div>

    {#if userSppPreview}
      <div class="receipt-box">
        <p>
          <strong>Total:</strong>
          {userSppPreview.totalRows} | <strong>New:</strong>
          {userSppPreview.newCount} |
          <strong>User Collisions:</strong>
          {userSppPreview.userCollisions} |
          <strong>Protected Master Collisions:</strong>
          {userSppPreview.masterCollisions}
        </p>
      </div>
    {/if}
    {#if userSppImportResult}
      <div class="receipt-box success">
        <strong>
          Inserted: {userSppImportResult.insertedCount} | Overwritten: {userSppImportResult.overwrittenCount} | Skipped: {userSppImportResult.skippedCount}
        </strong>
      </div>
    {/if}
    </div>
  {/if}
</div>

<style>
  .two-col {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 320px), 1fr));
    gap: 1rem;
    min-width: 0;
  }
  .hub-card {
    background: var(--vpro-surface);
    border: 1px solid var(--vpro-border);
    border-top: 3px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 1rem;
    display: grid;
    gap: 0.75rem;
    align-content: start;
    min-width: 0;
  }
  .hub-card h3 {
    margin: 0;
    color: var(--vpro-navy);
    font-size: 1rem;
  }
  .form-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.6rem;
    align-items: end;
    min-width: 0;
  }
  .form-stack {
    display: grid;
    gap: 0.6rem;
    min-width: 0;
  }
  .form-stack label {
    display: grid;
    gap: 0.25rem;
    font-size: 0.8rem;
    color: var(--vpro-ink);
    min-width: 0;
  }
  .input-with-browse {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    align-items: center;
    min-width: 0;
  }
  .grow {
    flex: 1 1 200px;
    min-width: 0;
  }
  input:not([type='checkbox']),
  select,
  textarea {
    padding: 0.45rem 0.6rem;
    border: 1px solid var(--vpro-border-strong);
    border-radius: 4px;
    font-size: 0.84rem;
    font-family: inherit;
    color: var(--vpro-ink);
    background: var(--vpro-surface);
    min-width: 0;
    max-width: 100%;
    box-sizing: border-box;
  }
  textarea {
    font-family: var(--font-mono, monospace);
    font-size: 0.78rem;
    width: 100%;
  }
  .btn-primary {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.48rem 0.9rem;
    font-weight: 600;
    font-size: 0.83rem;
  }
  .btn-secondary {
    background: var(--vpro-surface);
    color: var(--vpro-navy);
    border: 1px solid var(--vpro-navy);
    border-radius: 4px;
    padding: 0.48rem 0.9rem;
    font-weight: 600;
    font-size: 0.83rem;
  }
  .receipt-box {
    background: var(--vpro-canvas);
    border: 1px solid var(--vpro-border);
    border-left: 4px solid var(--vpro-navy);
    padding: 0.65rem 0.8rem;
    border-radius: 4px;
    display: grid;
    gap: 0.35rem;
    font-size: 0.82rem;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .receipt-box.success {
    background: var(--vpro-success-bg);
    border-left-color: var(--vpro-success);
  }
  @media (pointer: coarse) {
    .btn-primary,
    .btn-secondary,
    input:not([type='checkbox']),
    select {
      min-height: 44px;
    }
  }
</style>
