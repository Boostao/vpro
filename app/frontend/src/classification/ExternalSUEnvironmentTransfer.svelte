<script lang="ts">
  import { onMount, onDestroy, untrack } from 'svelte';
  import { ClassificationService } from '../../bindings/github.com/boostao/vpro/app';
  import type { ExternalSUEnvironmentReview, ProjectMetadataCell } from '../../bindings/github.com/boostao/vpro/app';
  import { externalSUEnvironmentSession, validateExternalSUEnvironmentReview } from './externalSUEnvironment';
  import { ReadRequests, formatError } from '../shared/readRequests';
  import type { EditorCloseState } from '../shell/closeLifecycle';

  let {
    contextId,
    project,
    projectPath,
    su,
    suPath,
    onclosed,
  }: {
    contextId: string;
    project: string;
    projectPath: string;
    su: string;
    suPath: string;
    onclosed: () => void;
  } = $props();
  const scope = untrack(() => ({ contextId, project, projectPath, su, suPath }));
  const session = externalSUEnvironmentSession(scope);
  let activity = $state.raw(session.view());
  let review = $state.raw<ExternalSUEnvironmentReview | null>(null);
  let reading = $state(false);
  let error = $state('');
  let generation = 0;
  const reads = new ReadRequests();
  onMount(() => {
    const unsubscribe = session.subscribe(() => {
      activity = session.view();
    });
    if (!session.view().request) void reload();
    return unsubscribe;
  });
  onDestroy(() => {
    generation++;
    reads.cancelAll();
  });
  export function getCloseState(): EditorCloseState {
    const retained = session.closeState();
    if (retained.blocked || retained.busy) return retained;
    return {
      unsaved: reading || !!error || Boolean(review?.review.changes?.length),
      busy: reading,
      canSave: false,
      error: error || null,
      saveReason: 'Finish or dismiss the explicit transfer review before ordinary Save, Lock or close.',
    };
  }
  export function undo() {
    if (session.view().blocked) {
      error = 'Recover and acknowledge the retained transfer; Undo cannot reverse or erase its outcome.';
      return;
    }
    cancelReview();
    review = null;
    error = '';
  }
  function cancelReview() {
    generation++;
    reads.cancelAll();
    reading = false;
  }
  function cancel() {
    if (reading) {
      cancelReview();
      error = 'Review cancelled; no transfer request was sent.';
    } else session.cancel();
  }
  async function reload() {
    if (reading || session.view().blocked || session.view().busy) return;
    const request = ++generation;
    reading = true;
    error = '';
    review = null;
    try {
      const value = await reads.track(ClassificationService.GetExternalSUEnvironmentReview(scope.contextId));
      if (request !== generation) return;
      const checked = validateExternalSUEnvironmentReview(value, scope);
      if (request !== generation) return;
      review = checked;
    } catch (cause) {
      if (request === generation)
        error = `External SU Into Env review unavailable; no transfer applied: ${formatError(cause)}`;
    } finally {
      if (request === generation) reading = false;
    }
  }
  async function transfer() {
    if (!review || reading || session.view().busy || session.view().blocked) {
      error = 'Review available changes and resolve the retained transfer before explicit confirmation.';
      return;
    }
    const approved = review;
    try {
      await session.transfer(approved, (request) =>
        ClassificationService.TransferExternalSUEnvironmentReviewed(scope.contextId, JSON.stringify(request))
      );
      review = null;
    } catch (cause) {
      error = `Transfer was not started: ${formatError(cause)}`;
    }
  }
  async function recover() {
    try {
      await session.recover((request) =>
        ClassificationService.RecoverExternalSUEnvironmentOutcome(scope.contextId, JSON.stringify(request))
      );
    } catch (cause) {
      error = `Readonly recovery unavailable; retain the exact request: ${formatError(cause)}`;
    }
  }
  function acknowledge() {
    try {
      session.acknowledge();
      review = null;
      error = '';
    } catch (cause) {
      error = formatError(cause);
    }
  }
  function close() {
    if (getCloseState().unsaved || getCloseState().busy) {
      error = 'Finish or dismiss the review and resolve any retained transfer before returning.';
      return;
    }
    onclosed();
  }
  function cell(value: ProjectMetadataCell) {
    return value.storage === 'null' ? 'NULL' : `Text ${JSON.stringify(value.text)}`;
  }
</script>

<section class="external-transfer" aria-label="SU Into Env: separate selected file" data-external-su-environment>
  <h3>SU Into Env: separate selected file</h3>
  {#if error || activity.error}<p role="alert">{error || activity.error}</p>{/if}
  <dl class="scope">
    <dt>Target project</dt>
    <dd>{project} / {projectPath}</dd>
    <dt>Read-only selected SU</dt>
    <dd>{su} / {suPath}</dd>
  </dl>
  {#if reading}<p role="status">Reading the complete owned transfer sources...</p>{/if}
  {#if review}
    <p>
      {review.review.changes?.length} reviewed changed Admin cells across matching selected-SU plots, not only this plot.
    </p>
    <dl class="scope">
      <dt>Source digest</dt>
      <dd>{review.sourceHash}</dd>
      <dt>Approval</dt>
      <dd>{review.approvalHash}</dd>
    </dl>
    <div class="table-scroll">
      <table>
        <thead><tr><th>Plot / field</th><th>Current value</th><th>Reviewed value / source</th></tr></thead>
        <tbody
          >{#each review.review.changes ?? [] as change (`${change.adminRowId}/${change.field}`)}
            <tr
              ><th scope="row">{change.plotNumber} / {change.field}</th><td>{cell(change.before)}</td><td
                >{cell(change.after)} / {change.origin}</td
              ></tr
            >
          {/each}</tbody
        >
      </table>
    </div>
  {/if}
  {#if activity.request}
    <dl class="scope">
      <dt>Retained request</dt>
      <dd>{activity.request.requestId}</dd>
    </dl>
    {#if activity.outcome}
      <p role="status">Exact transfer outcome: {activity.outcome.status}.</p>
      {#if activity.outcome.receipt}{@const r = activity.outcome.receipt}
        <p data-external-su-receipt>
          {`${r.changedCells} cells across ${r.changedRows} plots; atomic history ${r.historyId}.`}
        </p>{/if}
      {#if activity.outcome.errorMessage}<p>{activity.outcome.errorMessage}</p>{/if}
    {:else}<p>
        Outcome is not yet certified. Retain this request and recover readonly; never repeat the transfer.
      </p>{/if}
  {/if}
  <div class="toolbar">
    <button
      type="button"
      disabled={reading || activity.busy || activity.blocked || !review?.review.changes?.length}
      onclick={transfer}>Confirm selected SU into environment</button
    >
    <button type="button" disabled={!reading && !activity.busy} onclick={cancel}>Cancel request wait</button>
    <button type="button" disabled={activity.busy || !activity.blocked} onclick={recover}
      >Recover transfer outcome readonly</button
    >
    <button type="button" disabled={activity.busy || !activity.blocked || !activity.outcome} onclick={acknowledge}
      >Acknowledge retained transfer outcome</button
    >
    <button type="button" disabled={reading || activity.busy || activity.blocked} onclick={undo}
      >Dismiss transfer review</button
    >
    <button type="button" disabled={reading || activity.busy || activity.blocked} onclick={reload}
      >Reload transfer review</button
    >
    <button
      type="button"
      disabled={reading ||
        activity.busy ||
        activity.blocked ||
        Boolean(error) ||
        Boolean(review?.review.changes?.length)}
      onclick={close}>Return to plot</button
    >
  </div>
  <p>
    Copies only reviewed selected-SU values and uniquely resolved names into the project Admin table. Personal
    definitions override master names; missing definitions preserve existing names. NULL and empty text remain distinct.
    Locked plots and ambiguous links/definitions refuse. Source SU, definitions, descriptions and original audits are
    not written; no forward external transfer is enabled.
  </p>
</section>

<style>
  .external-transfer {
    min-width: 0;
    padding: 1rem;
    border: 1px solid var(--vpro-border);
    border-top: 3px solid var(--vpro-navy);
    border-radius: 0.5rem;
    background: var(--vpro-surface);
    color: var(--vpro-ink);
  }
  h3 {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  p,
  dl {
    margin: 0.75rem 0;
  }
  [role='alert'] {
    color: var(--vpro-error);
  }
  .scope {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 0.25rem;
  }
  dt {
    font-weight: 600;
    color: var(--vpro-navy);
  }
  dd {
    min-width: 0;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }
  .toolbar {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin: 0.75rem 0;
  }
  button {
    max-width: 100%;
    padding: 0.5rem 0.75rem;
    border: 1px solid var(--vpro-navy);
    border-radius: 0.375rem;
    background: var(--vpro-surface);
    color: var(--vpro-navy);
  }
  button:disabled {
    opacity: 0.5;
  }
  .table-scroll {
    overflow-x: auto;
  }
  table {
    width: 100%;
    border-collapse: collapse;
  }
  th,
  td {
    padding: 0.5rem;
    border-bottom: 1px solid var(--vpro-border);
    text-align: left;
    overflow-wrap: anywhere;
  }
  thead th {
    background: var(--vpro-navy);
    color: var(--vpro-surface);
  }
</style>
