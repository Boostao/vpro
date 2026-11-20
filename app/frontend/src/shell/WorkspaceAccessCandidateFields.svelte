<script lang="ts">
  import type { AccessDatabaseInspection } from '../../bindings/github.com/boostao/vpro/app';
  import type { AccessProjectCandidate } from '../../bindings/github.com/boostao/vpro/app/internal/interchange/models';

  let {
    accessInspection,
    accessSelectedSourceProject,
    accessSelectedCandidate,
    accessTargetProject = $bindable(''),
    accessDestinationPath = $bindable(''),
    accessActivateOnSuccess = $bindable(true),
    busy,
    transitionWorking,
    accessWorking,
    contextReady,
    onSelectCandidate,
    onBrowseDestination,
  }: {
    accessInspection: AccessDatabaseInspection;
    accessSelectedSourceProject: string;
    accessSelectedCandidate: AccessProjectCandidate | null;
    accessTargetProject: string;
    accessDestinationPath: string;
    accessActivateOnSuccess: boolean;
    busy: boolean;
    transitionWorking: boolean;
    accessWorking: boolean;
    contextReady: boolean;
    onSelectCandidate: (candidate: AccessProjectCandidate | null) => void;
    onBrowseDestination: () => void;
  } = $props();
</script>

<label for="access-source-project">SOURCE PROJECT IN ACCESS DB</label>
<select
  id="access-source-project"
  value={accessSelectedSourceProject}
  onchange={(e) => {
    const chosen =
      (accessInspection.projects ?? []).find((p) => p.sourceProject === (e.currentTarget as HTMLSelectElement).value) ??
      null;
    onSelectCandidate(chosen);
  }}
  disabled={busy || transitionWorking || accessWorking}
>
  {#each accessInspection.projects ?? [] as cand (cand.sourceProject)}
    <option value={cand.sourceProject}>{cand.sourceProject} ({cand.sourceVersion} · {cand.plotCount} plots)</option>
  {/each}
</select>
{#if accessSelectedCandidate}
  <p class="text-xs break-words"><strong>Autoconversion:</strong> {accessSelectedCandidate.conversionMode}</p>
  <p class="text-xs break-words">{accessSelectedCandidate.statusMessage}</p>
  {#if (accessSelectedCandidate.optionalSUs?.length ?? 0) > 0}
    <p class="text-xs break-words">SU tables included: {(accessSelectedCandidate.optionalSUs ?? []).join(', ')}</p>
  {/if}
{/if}
<label for="access-target-project">NEW VPRO PROJECT PREFIX</label>
<input
  id="access-target-project"
  bind:value={accessTargetProject}
  required
  disabled={busy || transitionWorking || accessWorking}
/>
<label for="access-dest-path">NEW VPRO PROJECT FILE (.db)</label>
<input
  id="access-dest-path"
  bind:value={accessDestinationPath}
  required
  disabled={busy || transitionWorking || accessWorking}
/>
<button
  type="button"
  id="browse-access-dest"
  disabled={busy || transitionWorking || accessWorking || !contextReady}
  onclick={onBrowseDestination}
>
  Browse destination .db…
</button>
<label class="flex items-center gap-2 text-xs">
  <input
    type="checkbox"
    style="width:auto;min-height:auto;"
    bind:checked={accessActivateOnSuccess}
    disabled={busy || transitionWorking || accessWorking}
  />
  Switch to imported project on completion
</label>
<button
  type="submit"
  id="convert-import-access-btn"
  disabled={busy ||
    transitionWorking ||
    accessWorking ||
    !accessSelectedCandidate?.compatible ||
    !accessTargetProject ||
    !accessDestinationPath}
>
  {accessWorking ? 'Converting & importing…' : 'Convert & import to VPRO DB'}
</button>
