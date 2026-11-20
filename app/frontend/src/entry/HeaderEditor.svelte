<script lang="ts">
  import { paperPage, type PaperControl } from './paperLayout';
  import { controlLabel, headerFieldSpecs, presentationGroups, type HeaderEditorBaseProps } from './formPresentation';
  import CoordinateFields from './CoordinateFields.svelte';
  import BECFields from './BECFields.svelte';
  import WorkingUnitFields from './WorkingUnitFields.svelte';
  import QualityFields from './QualityFields.svelte';
  import SubstrateFields from './SubstrateFields.svelte';
  import SiteCodeFields from './SiteCodeFields.svelte';
  import { siteCodeKey } from './siteCodeEditor';
  import RegionCodeFields from './RegionCodeFields.svelte';
  import { regionCodeKey } from './regionCodeEditor';
  import { substrateKey } from './substrateEditor';
  import { qualityKey } from './qualityEditor';
  import { becKey } from './becEditor';
  import { isWorkingUnitControl } from './workingUnitEditor';
  import { isCoordinateControl, type CoordinateDisplayMode } from './coordinateEditor';
  import { nullableParentField } from './ordinaryEditor';
  import HeaderStandardField, { type HeaderFieldDef } from './HeaderStandardField.svelte';
  import HeaderGroupGrid, { type HeaderValidationContext } from './HeaderGroupGrid.svelte';

  type HeaderEditorProps = HeaderEditorBaseProps & { onCoordinateBusyChange?: (busy: boolean) => void };

  let {
    draft = $bindable(),
    original,
    capabilities,
    disabled,
    existing,
    lists,
    onchange,
    onerror,
    onvalidation,
    onCoordinateBusyChange,
    onWorkingUnitBusyChange,
    onQualityBusyChange,
    onSiteCodeBusyChange,
    onRegionCodeBusyChange,
    workingUnitSession,
    masterAllowed = false,
    extendedShrubs = false,
    snowCoverRegime = '',
    activeLayerDepth = '',
    snowCoverRegimeDisabled,
    activeLayerDepthDisabled,
    snowCoverRegimeError = null,
    activeLayerDepthError = null,
    onSnowCoverRegimeChange,
    onActiveLayerDepthChange,
    editor,
    additionalEditor,
    onMetadata,
    metadataDisabled = true,
    onOpenPictureManager,
    projectIds = [],
    pictureEditor,
    sourcePage,
    coordinateMode = $bindable<CoordinateDisplayMode>('dd'),
    children: layoutContent,
  }: HeaderEditorProps = $props();

  const pageName = $derived(sourcePage ? 'Site/Veg' : 'Site');
  const page = $derived(sourcePage ?? paperPage('Site', 'initial', coordinateMode));
  const groups = $derived(presentationGroups(pageName, page.controls));
  const byColumn = new Map<string, HeaderFieldDef>(headerFieldSpecs as readonly [string, HeaderFieldDef][]);
  const storedValues = $derived(new Map(Object.entries(draft).map(([key, value]) => [key.toLowerCase(), value])));
  const ordered = $derived(page.controls);
  const ownedColumns = $derived([
    ...new Set(
      ordered.flatMap((control) => {
        const column = control.column;
        if (!column || column === 'PlotNumber') return [];
        return isCoordinateControl(control.controlName) ||
          isWorkingUnitControl(control.controlName) ||
          becKey(column) ||
          qualityKey(column) ||
          substrateKey(column) ||
          siteCodeKey(column) ||
          regionCodeKey(column) ||
          additionalEditor?.columns.includes(column) ||
          editor?.columns.includes(column) ||
          byColumn.has(column)
          ? [column]
          : [];
      })
    ),
  ]);
  const ownedControls = $derived(
    ordered
      .filter(
        (control) =>
          !control.column && isCoordinateControl(control.controlName) && control.controlName !== 'optCoordMethod2'
      )
      .map((control) => control.controlId)
  );

  function inputOwner(control: PaperControl): PaperControl {
    const source = ordered.find(
      (candidate) => candidate.controlId === control.controlId && candidate.column === control.column
    );
    if (
      !(control.column ? ownedColumns.includes(control.column) : ownedControls.includes(control.controlId)) ||
      !source
    ) {
      throw new Error(`Header input ${control.controlName} has no exact source field owner.`);
    }
    return source;
  }

  function position(control: PaperControl) {
    if (['CheckBox', 'OptionButton'].includes(control.type)) return 'box-sizing:border-box;';
    return 'box-sizing:border-box;width:100%;min-width:0;min-height:40px;font:inherit;';
  }

  function inputId(control: PaperControl): string {
    if (isCoordinateControl(control.controlName)) return `header-coordinate-${control.controlName}`;
    if (isWorkingUnitControl(control.controlName)) {
      if (control.column === 'BECSiteUnit') return 'header-becSiteUnit';
      if (control.column === 'UserSiteUnit') return 'header-userSiteUnit';
      return `header-working-unit-${control.controlName}`;
    }
    const key =
      becKey(control.column) ??
      qualityKey(control.column) ??
      substrateKey(control.column) ??
      siteCodeKey(control.column) ??
      regionCodeKey(control.column) ??
      (additionalEditor?.columns.includes(control.column ?? '')
        ? nullableParentField(control.column)?.key
        : undefined) ??
      byColumn.get(control.column ?? '')?.key;
    return key
      ? `header-${key}`
      : control.column === 'RealmClass' && editor?.columns.includes('RealmClass')
        ? 'header-realmClass'
        : control.column === 'PlotNumber'
          ? 'header-plotNumber'
          : `header-source-${control.controlId}`;
  }

  function attachSuContextMenu(node: HTMLElement) {
    function onContextMenu(event: MouseEvent) {
      event.preventDefault();
      const copyBtn = node
        .closest('.responsive-form')
        ?.querySelector<HTMLButtonElement>('[data-source-control="btnCoptToWorkingUnit"]');
      if (copyBtn && !copyBtn.disabled) copyBtn.click();
    }
    node.addEventListener('contextmenu', onContextMenu);
    return {
      destroy() {
        node.removeEventListener('contextmenu', onContextMenu);
      },
    };
  }
</script>

{#if projectIds.length}
  <datalist id="header-projectId-options"
    >{#each projectIds as pid (pid)}<option value={pid}></option>{/each}</datalist
  >
{/if}

<WorkingUnitFields
  bind:draft
  {original}
  controls={ordered}
  {position}
  {capabilities}
  {disabled}
  {onchange}
  {onerror}
  {onvalidation}
  {masterAllowed}
  onbusy={onWorkingUnitBusyChange}
  session={workingUnitSession}
>
  {#snippet children(workingUnitInputs)}
    <QualityFields
      bind:draft
      {original}
      controls={ordered}
      {position}
      {capabilities}
      {disabled}
      {onchange}
      {onvalidation}
      onbusy={onQualityBusyChange}
    >
      {#snippet children(qualityInputs)}
        <SiteCodeFields
          bind:draft
          {original}
          controls={ordered}
          {position}
          {capabilities}
          {disabled}
          {onchange}
          {onvalidation}
          onbusy={onSiteCodeBusyChange}
        >
          {#snippet children(siteCodeInputs)}
            <RegionCodeFields
              bind:draft
              {original}
              controls={ordered}
              {position}
              {capabilities}
              {disabled}
              {onchange}
              {onvalidation}
              onbusy={onRegionCodeBusyChange}
            >
              {#snippet children(regionCodeInputs)}
                <SubstrateFields
                  bind:draft
                  {original}
                  controls={ordered}
                  {position}
                  {capabilities}
                  {disabled}
                  {onchange}
                  {onvalidation}
                >
                  {#snippet children(substrateInputs)}
                    <BECFields
                      bind:draft
                      {original}
                      controls={ordered}
                      {position}
                      {capabilities}
                      {disabled}
                      {onchange}
                      {onvalidation}
                    >
                      {#snippet children(becInputs)}
                        <CoordinateFields
                          bind:draft
                          bind:mode={coordinateMode}
                          controls={ordered}
                          {position}
                          {capabilities}
                          {disabled}
                          {onchange}
                          {onerror}
                          {onvalidation}
                          onbusy={onCoordinateBusyChange}
                        >
                          {#snippet children(coordinateInputs)}
                            {#snippet fieldInput(control: PaperControl, vCtx: HeaderValidationContext)}
                              {@const field = byColumn.get(control.column ?? '')}
                              {@const stored = control.column
                                ? storedValues.get(control.column.toLowerCase())
                                : undefined}
                              {@const unavailable = disabled || !control.enabled || control.locked}
                              {@const action =
                                control.type === 'CommandButton' ||
                                control.type === 'ToggleButton' ||
                                control.type === 'Subform'}
                              {#if !action}<label class="field-label" for={inputId(control)}
                                  >{controlLabel(control, Boolean(sourcePage))}</label
                                >{/if}
                              {#if isCoordinateControl(control.controlName)}{@render coordinateInputs(control)}
                              {:else if isWorkingUnitControl(control.controlName)}
                                {#if control.controlName === 'UserSiteUnit' || control.controlName === 'BECSiteUnit'}
                                  <span
                                    class="su-context-wrap"
                                    use:attachSuContextMenu
                                    title="Right-click to copy BEC Master Site Unit to Working Unit"
                                    >{@render workingUnitInputs(control)}</span
                                  >
                                {:else}{@render workingUnitInputs(control)}{/if}
                              {:else if becKey(control.column)}{@render becInputs(control)}
                              {:else if qualityKey(control.column)}{@render qualityInputs(control)}
                              {:else if substrateKey(control.column)}{@render substrateInputs(control)}
                              {:else if siteCodeKey(control.column)}{@render siteCodeInputs(control)}
                              {:else if regionCodeKey(control.column)}{@render regionCodeInputs(control)}
                              {:else if additionalEditor && control.column && additionalEditor.columns.includes(control.column)}{@render additionalEditor.input(
                                  control,
                                  position(control)
                                )}
                              {:else if editor && control.column && editor.columns.includes(control.column)}{@render editor.input(
                                  control,
                                  position(control)
                                )}
                              {:else if control.type === 'CommandButton' || control.type === 'ToggleButton'}
                                {#if control.controlName === 'btnLoadMetadata' && onMetadata}
                                  <button
                                    type="button"
                                    class="paper-control"
                                    data-source-control={control.controlName}
                                    disabled={metadataDisabled}
                                    onclick={onMetadata}>{controlLabel(control)}</button
                                  >
                                {:else if control.controlName === 'btnManagePictures' && onOpenPictureManager}
                                  <button
                                    type="button"
                                    class="paper-control"
                                    data-source-control={control.controlName}
                                    disabled={!draft.plotNumber.trim()}
                                    title={draft.plotNumber.trim()
                                      ? `Manage pictures for plot ${draft.plotNumber.trim()}`
                                      : 'Select or enter a Plot Number first'}
                                    onclick={() => {
                                      if (draft.plotNumber.trim()) onOpenPictureManager(draft.plotNumber.trim());
                                    }}>{controlLabel(control)}</button
                                  >
                                {:else}
                                  <button
                                    type="button"
                                    class="paper-control pending"
                                    data-source-control={control.controlName}
                                    disabled
                                    title={control.controlName === 'Toggle408' || control.controlName === 'Toggle409'
                                      ? 'Legacy Access paper-form display toggle (not used in VPro 2.0 web layout)'
                                      : 'Legacy Access paper-form action; use the corresponding VPro 2.0 workflow'}
                                    >{controlLabel(control)}</button
                                  >
                                {/if}
                              {:else if control.type === 'Subform'}
                                {#if pictureEditor && control.controlName === 'frmVPics' && control.properties.SourceObject?.value === 'Form.frmVPicsXL'}
                                  <div class="embedded" data-source-control={control.controlName}>
                                    {@render pictureEditor()}
                                  </div>
                                {:else}<div
                                    class="pending embedded"
                                    data-source-control={control.controlName}
                                    title="Pictures subform is managed via Pictures tab or Picture Manager"
                                  >
                                    Pictures panel
                                  </div>{/if}
                              {:else}
                                <HeaderStandardField
                                  {control}
                                  {field}
                                  bind:draft
                                  {vCtx}
                                  {onchange}
                                  opts={{
                                    existing,
                                    unavailable,
                                    capabilities,
                                    lists,
                                    stored,
                                    hasProjectIds: projectIds.length > 0,
                                    controlInputId: inputId(control),
                                  }}
                                />
                              {/if}
                            {/snippet}
                            <HeaderGroupGrid
                              bind:draft
                              {original}
                              {existing}
                              {disabled}
                              {pageName}
                              {groups}
                              hasCustomLayout={Boolean(layoutContent)}
                              {onchange}
                              {onerror}
                              {onvalidation}
                              renderControl={fieldInput}
                            >
                              {#snippet customLayout(vCtx)}
                                {#snippet slotInput(control: PaperControl, _position: string)}{@render fieldInput(
                                    inputOwner(control),
                                    vCtx
                                  )}{/snippet}
                                {#if layoutContent}{@render layoutContent(
                                    {
                                      columns: ownedColumns,
                                      controls: ownedControls,
                                      input: slotInput,
                                      labelled: true,
                                    },
                                    coordinateMode
                                  )}{/if}
                              {/snippet}
                              {#snippet arcticFields()}
                                {#if extendedShrubs}
                                  <fieldset
                                    class="form-group"
                                    data-card-zone="full"
                                    data-extended-arctic-fields
                                    data-help-id="site.realm_class"
                                  >
                                    <legend>Arctic / extended site fields</legend>
                                    <div class="field-grid">
                                      <div class="form-field" data-col-span={6} data-help-id="site.realm_class">
                                        <label class="field-label" for="header-snowCoverregime">Snow cover regime</label
                                        >
                                        <input
                                          class="paper-control"
                                          id="header-snowCoverregime"
                                          data-column="SnowCoverregime"
                                          type="text"
                                          value={snowCoverRegime}
                                          disabled={(snowCoverRegimeDisabled ?? disabled) ||
                                            capabilities.snowCoverRegime !== true ||
                                            !onSnowCoverRegimeChange}
                                          aria-invalid={snowCoverRegimeError ? 'true' : undefined}
                                          data-help-id="site.realm_class"
                                          title={onSnowCoverRegimeChange
                                            ? 'SnowCoverregime'
                                            : 'Use Complete two-page entry or SIVI parent editor to save SnowCoverregime'}
                                          oninput={(event) => onSnowCoverRegimeChange?.(event.currentTarget.value)}
                                        />
                                        {#if snowCoverRegimeError}<p role="alert" class="text-xs text-red-700 mt-1">
                                            {snowCoverRegimeError}
                                          </p>{/if}
                                      </div>
                                      <div class="form-field" data-col-span={6} data-help-id="site.realm_class">
                                        <label class="field-label" for="header-activeLayerDepth"
                                          >Active layer depth (cm)</label
                                        >
                                        <input
                                          class="paper-control numeric-control"
                                          id="header-activeLayerDepth"
                                          data-column="ActiveLayerDepth"
                                          type="text"
                                          inputmode="decimal"
                                          value={activeLayerDepth}
                                          disabled={(activeLayerDepthDisabled ?? disabled) ||
                                            capabilities.activeLayerDepth !== true ||
                                            !onActiveLayerDepthChange}
                                          aria-invalid={activeLayerDepthError ? 'true' : undefined}
                                          data-help-id="site.realm_class"
                                          title={onActiveLayerDepthChange
                                            ? 'ActiveLayerDepth'
                                            : 'Use Complete two-page entry or Two-page additional fields to save ActiveLayerDepth'}
                                          oninput={(event) => onActiveLayerDepthChange?.(event.currentTarget.value)}
                                        />
                                        {#if activeLayerDepthError}<p role="alert" class="text-xs text-red-700 mt-1">
                                            {activeLayerDepthError}
                                          </p>{/if}
                                      </div>
                                    </div>
                                  </fieldset>
                                {/if}
                              {/snippet}
                            </HeaderGroupGrid>
                          {/snippet}</CoordinateFields
                        >
                      {/snippet}</BECFields
                    >
                  {/snippet}</SubstrateFields
                >
              {/snippet}</RegionCodeFields
            >
          {/snippet}</SiteCodeFields
        >
      {/snippet}</QualityFields
    >
  {/snippet}</WorkingUnitFields
>

<style>
  .su-context-wrap {
    display: contents;
  }
  .form-group {
    grid-column: 1 / -1;
    margin: 0;
    border-color: var(--vpro-border);
    border-top: 3px solid var(--vpro-gold);
    background: var(--vpro-surface);
  }
  .form-group :global(legend) {
    color: var(--vpro-navy);
  }
  .paper-control[aria-invalid='true'] {
    border-color: var(--vpro-error);
  }
  .paper-control {
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
    line-height: 1.4;
  }
  .numeric-control {
    font-family: var(--vpro-font-mono, monospace);
    font-variant-numeric: tabular-nums;
  }
  .paper-control:focus {
    outline: 2px solid var(--vpro-focus-ring);
    outline-offset: 1px;
  }
  .paper-control:disabled {
    color: var(--vpro-ink-muted);
    background: var(--vpro-surface-subtle);
  }
  .pending {
    opacity: 0.65;
  }
  .embedded {
    display: flex;
    align-items: center;
    justify-content: center;
  }
</style>
