<script lang="ts">
  import ProjectAdminLifecycleTab, { type LifecycleViewMeta } from './ProjectAdminLifecycleTab.svelte';
  import {
    formatError,
    validateNewProjectInputs,
    validateProjectNameInput,
    validateSplinterInputs,
    type CompareProjectsResult,
    type ComplianceValidationReport,
    type ExportSplinterResult,
    type FieldDiff,
    type MergeResolutionChoice,
    type NewProjectResult,
    type OptimizeVegPreview,
    type OptimizeVegResult,
    type ProjectMetadataPreset,
    type QuarantineOrphanResult,
    type SaveProjectAsResult,
    type ThreeWayMergePreview,
    type ThreeWayMergeResult,
  } from './projectAdminWorkbench';

  export interface AdminLazyTabSnapshot {
    activeTab: 'lifecycle' | 'compliance' | 'optimizeveg' | 'merge';
    busy: boolean;
    activeProject: string;
    activeSu: string;
    availablePresets: ProjectMetadataPreset[];
    newProjIdTruncationWarning: string | null;
    newProjResult: NewProjectResult | null;
    saveAsResult: SaveProjectAsResult | null;
    splinterResult: ExportSplinterResult | null;
    complianceReport: ComplianceValidationReport | null;
    quarantineResult: QuarantineOrphanResult | null;
    complianceFindingCounts: { envAdmin: number; orphan: number; taxonomy: number } | null;
    optPreview: OptimizeVegPreview | null;
    optResult: OptimizeVegResult | null;
    optUnresolvedConflictCount: number;
    cmpResult: CompareProjectsResult | null;
    cmpAllDiffs: FieldDiff[];
    cmpExportPreview: { format: 'CSV' | 'TSV'; text: string } | null;
    mergePreview: ThreeWayMergePreview | null;
    mergePlotResolutions: Record<string, MergeResolutionChoice>;
    mergeFieldResolutions: Record<string, MergeResolutionChoice>;
    mergeResult: ThreeWayMergeResult | null;
  }

  export interface AdminLazyTabActions {
    submitCreateNewProject: () => void;
    submitSaveProjectAs: () => void;
    submitExportSplinter: () => void;
    runCompliance: () => void;
    runQuarantine: () => void;
    openOptimizeVeg: () => void;
    resetOptPreview: () => void;
    previewOptimizeVeg: () => void;
    applyOptimizeVeg: () => void;
    runCompare: () => void;
    exportCompareDiffs: (format: 'CSV' | 'TSV') => void;
    previewMerge: () => void;
    executeMerge: () => void;
    setPlotResolution: (plotNumber: string, choice: MergeResolutionChoice) => void;
    setFieldResolution: (conflictId: string, choice: MergeResolutionChoice) => void;
  }

  let {
    view,
    actions,
    newProjName = $bindable(''),
    newProjId = $bindable(''),
    newProjTitle = $bindable(''),
    newProjPreset = $bindable('LMH25_2023_FS882'),
    newProjDest = $bindable(''),
    newProjActivate = $bindable(false),
    saveAsName = $bindable(''),
    saveAsDest = $bindable(''),
    saveAsActivate = $bindable(false),
    splinterName = $bindable(''),
    splinterDest = $bindable(''),
    splinterUseSu = $bindable(true),
    splinterUnitsRaw = $bindable(''),
    splinterPlotsRaw = $bindable(''),
    splinterActivate = $bindable(false),
    complianceUseSu = $bindable(false),
    confirmQuarantine = $bindable(false),
    optPlotNumbersRaw = $bindable(''),
    optCustodianAuditOverride = $bindable(false),
    optConfirmReviewed = $bindable(false),
    cmpTargetPath = $bindable(''),
    cmpTargetProject = $bindable(''),
    cmpSourceProject = $bindable(''),
    cmpSourcePath = $bindable(''),
    cmpCaseInsensitive = $bindable(false),
    mergeSourcePath = $bindable(''),
    mergeSourceProject = $bindable(''),
    mergeBasePath = $bindable(''),
    mergeBaseProject = $bindable(''),
    mergeTargetPath = $bindable(''),
    mergeTargetProject = $bindable(''),
    mergeCaseInsensitive = $bindable(false),
    mergeDefaultResolution = $bindable<MergeResolutionChoice>('keep_target'),
  }: {
    view: AdminLazyTabSnapshot;
    actions: AdminLazyTabActions;
    newProjName?: string;
    newProjId?: string;
    newProjTitle?: string;
    newProjPreset?: string;
    newProjDest?: string;
    newProjActivate?: boolean;
    saveAsName?: string;
    saveAsDest?: string;
    saveAsActivate?: boolean;
    splinterName?: string;
    splinterDest?: string;
    splinterUseSu?: boolean;
    splinterUnitsRaw?: string;
    splinterPlotsRaw?: string;
    splinterActivate?: boolean;
    complianceUseSu?: boolean;
    confirmQuarantine?: boolean;
    optPlotNumbersRaw?: string;
    optCustodianAuditOverride?: boolean;
    optConfirmReviewed?: boolean;
    cmpTargetPath?: string;
    cmpTargetProject?: string;
    cmpSourceProject?: string;
    cmpSourcePath?: string;
    cmpCaseInsensitive?: boolean;
    mergeSourcePath?: string;
    mergeSourceProject?: string;
    mergeBasePath?: string;
    mergeBaseProject?: string;
    mergeTargetPath?: string;
    mergeTargetProject?: string;
    mergeCaseInsensitive?: boolean;
    mergeDefaultResolution?: MergeResolutionChoice;
  } = $props();

  const lifecycleMeta: LifecycleViewMeta = $derived({
    busy: view.busy,
    activeProject: view.activeProject,
    activeSu: view.activeSu,
    availablePresets: view.availablePresets,
    selectedNewProjPreset: view.availablePresets.find((p) => p.id === newProjPreset) ?? null,
    newProjIdTruncationWarning: view.newProjIdTruncationWarning,
    newProjValidationError: validateNewProjectInputs(
      newProjName,
      newProjId,
      newProjTitle,
      newProjPreset,
      newProjDest,
      newProjActivate
    ),
    saveAsValidationError: saveAsName === '' ? null : validateProjectNameInput(saveAsName),
    splinterValidationError: validateSplinterInputs(
      splinterName,
      splinterDest,
      splinterUseSu,
      splinterUnitsRaw,
      splinterPlotsRaw,
      splinterActivate,
      view.activeSu
    ),
    newProjResult: view.newProjResult,
    saveAsResult: view.saveAsResult,
    splinterResult: view.splinterResult,
  });
</script>

{#if view.activeTab === 'lifecycle'}
  <ProjectAdminLifecycleTab
    meta={lifecycleMeta}
    bind:newProjName
    bind:newProjId
    bind:newProjTitle
    bind:newProjPreset
    bind:newProjDest
    bind:newProjActivate
    bind:saveAsName
    bind:saveAsDest
    bind:saveAsActivate
    bind:splinterName
    bind:splinterDest
    bind:splinterUseSu
    bind:splinterUnitsRaw
    bind:splinterPlotsRaw
    bind:splinterActivate
    onsubmitnewproject={actions.submitCreateNewProject}
    onsubmitsaveas={actions.submitSaveProjectAs}
    onsubmitsplinter={actions.submitExportSplinter}
  />
{:else if view.activeTab === 'compliance'}
  {#await import('./ProjectAdminComplianceTab.svelte')}
    <p role="status" class="p-4 text-sm text-vpro-ink-secondary">Loading Compliance Validator...</p>
  {:then { default: ProjectAdminComplianceTab }}
    <ProjectAdminComplianceTab
      busy={view.busy}
      activeSu={view.activeSu}
      bind:complianceUseSu
      bind:confirmQuarantine
      complianceReport={view.complianceReport}
      quarantineResult={view.quarantineResult}
      findingCounts={view.complianceFindingCounts}
      onRunCompliance={actions.runCompliance}
      onRunQuarantine={actions.runQuarantine}
      onOpenOptimizeVeg={actions.openOptimizeVeg}
    />
  {:catch loadError}
    <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">
      Compliance Validator could not load: {formatError(loadError)}
    </p>
  {/await}
{:else if view.activeTab === 'optimizeveg'}
  {#await import('./ProjectAdminOptimizeVegTab.svelte')}
    <p role="status" class="p-4 text-sm text-vpro-ink-secondary">Loading Safe OptimizeVeg...</p>
  {:then { default: ProjectAdminOptimizeVegTab }}
    <ProjectAdminOptimizeVegTab
      busy={view.busy}
      bind:optPlotNumbersRaw
      bind:optCustodianAuditOverride
      bind:optConfirmReviewed
      optPreview={view.optPreview}
      optResult={view.optResult}
      optUnresolvedConflictCount={view.optUnresolvedConflictCount}
      onOverrideChange={actions.resetOptPreview}
      onPreviewOptimizeVeg={actions.previewOptimizeVeg}
      onApplyOptimizeVeg={actions.applyOptimizeVeg}
    />
  {:catch loadError}
    <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">
      Safe OptimizeVeg could not load: {formatError(loadError)}
    </p>
  {/await}
{:else}
  {#await import('./ProjectAdminMergeTab.svelte')}
    <p role="status" class="p-4 text-sm text-vpro-ink-secondary">Loading Compare &amp; 3-Way Merge...</p>
  {:then { default: ProjectAdminMergeTab }}
    <ProjectAdminMergeTab
      busy={view.busy}
      bind:cmpTargetPath
      bind:cmpTargetProject
      bind:cmpSourceProject
      bind:cmpSourcePath
      bind:cmpCaseInsensitive
      cmpResult={view.cmpResult}
      cmpAllDiffs={view.cmpAllDiffs}
      cmpExportPreview={view.cmpExportPreview}
      bind:mergeSourcePath
      bind:mergeSourceProject
      bind:mergeBasePath
      bind:mergeBaseProject
      bind:mergeTargetPath
      bind:mergeTargetProject
      bind:mergeCaseInsensitive
      bind:mergeDefaultResolution
      mergePreview={view.mergePreview}
      mergePlotResolutions={view.mergePlotResolutions}
      mergeFieldResolutions={view.mergeFieldResolutions}
      mergeResult={view.mergeResult}
      onRunCompare={actions.runCompare}
      onExportCompareDiffs={actions.exportCompareDiffs}
      onPreviewMerge={actions.previewMerge}
      onExecuteMerge={actions.executeMerge}
      onSetPlotResolution={actions.setPlotResolution}
      onSetFieldResolution={actions.setFieldResolution}
    />
  {:catch loadError}
    <p role="alert" class="rounded border-l-4 border-red-700 bg-red-50 p-3 text-sm text-red-900">
      Compare &amp; 3-Way Merge could not load: {formatError(loadError)}
    </p>
  {/await}
{/if}
