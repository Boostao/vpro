<script lang="ts">
  import LongVegetationSwitchPreferences from '../LongVegetationSwitchPreferences.svelte';
  import LongVegetationThresholdPreferences from '../LongVegetationThresholdPreferences.svelte';
  import LongVegetationGroupPreferences from '../LongVegetationGroupPreferences.svelte';
  import LongVegetationQualityNullPreferences from '../LongVegetationQualityNullPreferences.svelte';
  import LongVegetationQualityMinimumPreferences from '../LongVegetationQualityMinimumPreferences.svelte';
  import LongVegetationNamingPreferences from '../LongVegetationNamingPreferences.svelte';
  import LongVegetationSelectedFieldPreferences from '../LongVegetationSelectedFieldPreferences.svelte';
  import LongVegetationEnforcementPreferences from '../LongVegetationEnforcementPreferences.svelte';
  import LongVegetationUnitPreferences from '../LongVegetationUnitPreferences.svelte';
  import LongVegetationSelectedUnitSelection from '../LongVegetationSelectedUnitSelection.svelte';
  import type { LongVegetationSwitchPreferencesSession } from '../longVegetationSwitchPreferences';
  import type { LongVegetationThresholdPreferencesSession } from '../longVegetationThresholdPreferences';
  import type { LongVegetationGroupPreferencesSession } from '../longVegetationGroupPreferences';
  import type { LongVegetationQualityNullPreferencesSession } from '../longVegetationQualityNullPreferences';
  import type { LongVegetationQualityMinimumPreferencesSession } from '../longVegetationQualityMinimumPreferences';
  import type { LongVegetationNamingPreferencesSession } from '../longVegetationNamingPreferences';
  import type { LongVegetationSelectedFieldPreferencesSession } from '../longVegetationSelectedFieldPreferences';
  import type { LongVegetationEnforcementPreferencesSession } from '../longVegetationEnforcementPreferences';
  import type { LongVegetationUnitPreferencesSession } from '../longVegetationUnitPreferences';
  import type { SelectedUnitSelectionSession } from '../longVegetationSelectedUnitSelection';

  export type SecondaryBusyKind =
    | 'switch'
    | 'threshold'
    | 'group'
    | 'qualityNull'
    | 'qualityMinimum'
    | 'naming'
    | 'selectedField'
    | 'enforcement'
    | 'unit';

  export interface SecondarySessions {
    switches: LongVegetationSwitchPreferencesSession | null;
    thresholds: LongVegetationThresholdPreferencesSession | null;
    groups: LongVegetationGroupPreferencesSession | null;
    qualityNulls: LongVegetationQualityNullPreferencesSession | null;
    qualityMinima: LongVegetationQualityMinimumPreferencesSession | null;
    naming: LongVegetationNamingPreferencesSession | null;
    selectedField: LongVegetationSelectedFieldPreferencesSession | null;
    enforcement: LongVegetationEnforcementPreferencesSession | null;
    units: LongVegetationUnitPreferencesSession | null;
    selectedUnitSelection: SelectedUnitSelectionSession | null;
  }

  export interface SecondaryState {
    unitView: ReturnType<LongVegetationUnitPreferencesSession['view']> | null;
    unitReadBusy: boolean;
    switchBarrier: boolean;
    switchMutationHeld: boolean;
    thresholdBarrier: boolean;
    thresholdMutationHeld: boolean;
    groupBarrier: boolean;
    groupMutationHeld: boolean;
    qualityNullBarrier: boolean;
    qualityNullMutationHeld: boolean;
    qualityMinimumBarrier: boolean;
    qualityMinimumMutationHeld: boolean;
    namingBarrier: boolean;
    namingMutationHeld: boolean;
    selectedFieldBarrier: boolean;
    selectedFieldMutationHeld: boolean;
    enforcementBarrier: boolean;
    enforcementMutationHeld: boolean;
    selectedUnitBarrier: boolean;
    selectedUnitMutationHeld: boolean;
    peerPreferenceBarriers: boolean;
    peerMutationHeld: boolean;
  }

  export interface SecondaryPrefHolds {
    projectActive: boolean;
    projectScopeKnown: boolean;
    projectBarrier: boolean;
    projectMutationHeld: boolean;
    busy: boolean;
    operationHeld: boolean;
    workbookBarrier: boolean;
    unitBarrier: boolean;
    unitMutationHeld: boolean;
    titleBarrier: boolean;
    statisticsBarrier: boolean;
    titleStatsMutationHeld: boolean;
  }

  let {
    contextId,
    sessions,
    secState,
    holds,
    onReadBusy,
    onSelectedUnitChanged,
  }: {
    contextId: string;
    sessions: SecondarySessions;
    secState: SecondaryState;
    holds: SecondaryPrefHolds;
    onReadBusy: (kind: SecondaryBusyKind, value: boolean) => void;
    onSelectedUnitChanged: () => void;
  } = $props();

  const commonOpBase = $derived(
    holds.unitBarrier ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      holds.titleBarrier ||
      holds.statisticsBarrier
  );
  const commonMutBase = $derived(
    holds.unitMutationHeld || holds.busy || holds.operationHeld || holds.workbookBarrier || holds.titleStatsMutationHeld
  );
  const nonUnitBarriers = $derived(holds.titleBarrier || holds.statisticsBarrier || secState.peerPreferenceBarriers);
  const nonUnitMutations = $derived(holds.titleStatsMutationHeld || secState.peerMutationHeld);
</script>

{#if sessions.switches}
  <LongVegetationSwitchPreferences
    {contextId}
    preferences={sessions.switches}
    operationHeld={commonOpBase ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('switch', value)}
  />
{/if}
{#if sessions.thresholds}
  <LongVegetationThresholdPreferences
    {contextId}
    preferences={sessions.thresholds}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('threshold', value)}
  />
{/if}
{#if sessions.groups}
  <LongVegetationGroupPreferences
    {contextId}
    preferences={sessions.groups}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('group', value)}
  />
{/if}
{#if sessions.qualityNulls}
  <LongVegetationQualityNullPreferences
    {contextId}
    preferences={sessions.qualityNulls}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('qualityNull', value)}
  />
{/if}
{#if sessions.qualityMinima}
  <LongVegetationQualityMinimumPreferences
    {contextId}
    preferences={sessions.qualityMinima}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('qualityMinimum', value)}
  />
{/if}
{#if sessions.naming}
  <LongVegetationNamingPreferences
    {contextId}
    preferences={sessions.naming}
    selectedFieldEnabled={true}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.selectedFieldBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.selectedFieldMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('naming', value)}
  />
{/if}
{#if sessions.selectedField}
  <LongVegetationSelectedFieldPreferences
    {contextId}
    preferences={sessions.selectedField}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.enforcementBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.enforcementMutationHeld}
    onReadBusyChange={(value) => onReadBusy('selectedField', value)}
  />
{/if}
{#if sessions.enforcement}
  <LongVegetationEnforcementPreferences
    {contextId}
    preferences={sessions.enforcement}
    operationHeld={commonOpBase ||
      secState.switchBarrier ||
      secState.thresholdBarrier ||
      secState.groupBarrier ||
      secState.qualityNullBarrier ||
      secState.qualityMinimumBarrier ||
      secState.namingBarrier ||
      secState.selectedFieldBarrier}
    mutationHeld={commonMutBase ||
      secState.switchMutationHeld ||
      secState.thresholdMutationHeld ||
      secState.groupMutationHeld ||
      secState.qualityNullMutationHeld ||
      secState.qualityMinimumMutationHeld ||
      secState.namingMutationHeld ||
      secState.selectedFieldMutationHeld}
    onReadBusyChange={(value) => onReadBusy('enforcement', value)}
  />
{/if}
{#if sessions.units && ((!holds.projectActive && holds.projectScopeKnown) || secState.unitReadBusy || secState.unitView?.busy || secState.unitView?.blocked || secState.unitView?.authorityUnknown)}
  <LongVegetationUnitPreferences
    {contextId}
    preferences={sessions.units}
    operationHeld={holds.projectBarrier ||
      secState.selectedUnitBarrier ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      nonUnitBarriers}
    mutationHeld={holds.projectMutationHeld ||
      secState.selectedUnitMutationHeld ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      nonUnitMutations}
    onReadBusyChange={(value) => onReadBusy('unit', value)}
  />
{/if}
{#if sessions.selectedUnitSelection && ((!holds.projectActive && holds.projectScopeKnown) || secState.selectedUnitBarrier)}
  <LongVegetationSelectedUnitSelection
    {contextId}
    selection={sessions.selectedUnitSelection}
    operationHeld={holds.projectBarrier ||
      secState.unitReadBusy ||
      (!!secState.unitView &&
        Boolean(secState.unitView.busy || secState.unitView.blocked || secState.unitView.draftError)) ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      nonUnitBarriers}
    mutationHeld={holds.projectMutationHeld ||
      secState.unitReadBusy ||
      (!!secState.unitView && Boolean(secState.unitView.busy || secState.unitView.blocked)) ||
      holds.busy ||
      holds.operationHeld ||
      holds.workbookBarrier ||
      nonUnitMutations}
    onChange={onSelectedUnitChanged}
  />
{/if}
