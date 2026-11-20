import { metadataCellText } from '../admin/projectMetadataEditor';
import { formatError } from '../shared/readRequests';
import { collectedNext } from './collectedEditor';
import { twoPageVegetationEditableID, twoPageVegetationFields } from './twoPageVegetationEditor';
import {
  vegetationColumnIndex,
  vegetationIdentifierKey,
  vegetationSourceCell,
  type TwoPageVegetationForm,
  type TwoPageVegetationOriginal,
} from './twoPageVegetationWire';
import type { DeletedVegetationRowEntry } from './TwoPageVegCrudSection.svelte';

export interface VegetationCrudPort {
  createRow(
    cid: string,
    req: {
      requestId: string;
      plotNumber: string;
      form: string;
      species: string;
      layer?: string | null;
      collected?: string | null;
      covers: Record<string, number | null>;
    }
  ): Promise<{ requestId: string; rowId: string; id: number; species: string }>;
  deleteRow(
    cid: string,
    req: { requestId: string; plotNumber: string; form: string; id: number; rowId?: string }
  ): Promise<{ requestId: string; deletedId: number; species: string }>;
  restoreRow(
    cid: string,
    req: { requestId: string; plotNumber: string; form: string; deleteRequestId: string }
  ): Promise<{ requestId: string; restoredId: number; restoredRowId: string; species: string }>;
  listDeletedRows(cid: string, plot: string, form: string): Promise<DeletedVegetationRowEntry[] | null>;
}
export interface VegPanelProps {
  vegetationCrudPort?: VegetationCrudPort;
  contextId: string;
  project: string;
  plot: string;
  form: TwoPageVegetationForm;
  parentBlocked: boolean;
}

interface VegetationGroup {
  label: string;
  fields: [string, string][];
}
export function twoPageVegetationGroups(form: TwoPageVegetationForm): VegetationGroup[] {
  const groups: VegetationGroup[] =
    form === 'SubVegCXL'
      ? [{ label: 'Herb', fields: [['Cover6', 'C']] }]
      : form === 'SubVegDXL'
        ? [
            {
              label: 'Moss/Lichen',
              fields: [
                ['Cover7', 'D'],
                ['Cover8', 'Dr/Dw'],
                ['Cover9', 'Ep'],
              ],
            },
          ]
        : [
            {
              label: 'Tree',
              fields: [
                ['Cover1', 'A1'],
                ['Cover2', 'A2'],
                ['Cover3', 'A3'],
                ['TotalA', 'A'],
              ],
            },
            {
              label: 'Shrubs',
              fields: [
                ['Cover4', 'B1'],
                ['Cover5', 'B2'],
                ...(form === 'SubVegAXL'
                  ? ([
                      ['Cover5a', 'B3'],
                      ['Cover5b', 'B4'],
                      ['Cover5c', 'B5'],
                    ] satisfies [string, string][])
                  : []),
                ['TotalB', 'B'],
              ],
            },
          ];
  return [...groups, { label: 'Collection/verification', fields: [['Collected', '? (Collected)']] }];
}
export function twoPageVegetationStoredText(
  original: TwoPageVegetationOriginal,
  rowId: string,
  column: string
): string {
  const cell = vegetationSourceCell(original, rowId, column);
  return cell.storage === 'null'
    ? 'NULL'
    : cell.storage === 'text' && cell.text === ''
      ? '(empty text)'
      : metadataCellText(cell);
}
export function twoPageVegetationHasColumn(original: TwoPageVegetationOriginal, column: string): boolean {
  const key = vegetationIdentifierKey(column);
  return original.records.columns.some((field) => vegetationIdentifierKey(field.name) === key);
}
export function twoPageVegetationRowDiagnostic(original: TwoPageVegetationOriginal, rowId: string): string | null {
  try {
    twoPageVegetationEditableID(original, rowId);
    for (const field of [...twoPageVegetationFields(original), 'Species']) vegetationColumnIndex(original, field);
    return null;
  } catch (cause) {
    return `Read-only physical row ${rowId}: ${formatError(cause)}`;
  }
}

export function validateVegSpeciesPick(opts: {
  available: boolean;
  warningUnavailable: boolean;
  fieldsDisabled: boolean;
  currentRowId: string | undefined;
  plannedRow: string;
  panel: HTMLElement | undefined;
  event: Event;
  options: readonly { code: string }[];
}): string {
  const { available, warningUnavailable, fieldsDisabled, currentRowId, plannedRow, panel, event, options } = opts;
  const select = event.currentTarget;
  if (
    !available ||
    warningUnavailable ||
    fieldsDisabled ||
    !currentRowId ||
    currentRowId !== plannedRow ||
    !panel ||
    panel.dataset.vegetationCurrentRow !== plannedRow ||
    !(select instanceof HTMLSelectElement) ||
    select.disabled ||
    !select.checkVisibility() ||
    !panel.contains(select) ||
    !options.some((o) => o.code === select.value)
  ) {
    throw new Error('Observed Species list control, physical row or exact code differs from the planned selection.');
  }
  return select.value;
}

export function validateVegEnterTarget(opts: {
  fieldsDisabled: boolean;
  closeBlocked: boolean | undefined;
  rowId: string | undefined;
  original: TwoPageVegetationOriginal | null;
  panel: HTMLElement | undefined;
  form: TwoPageVegetationForm;
  mode: string | null;
  event: KeyboardEvent;
  column: string;
  doc?: { activeElement: unknown };
  InputCtor?: abstract new (...args: never[]) => HTMLInputElement;
}): { nextInput: HTMLInputElement | null; nextRowId: string | null } {
  const { fieldsDisabled, closeBlocked, rowId, original, panel, form, mode, event, column } = opts;
  const activeDoc = opts.doc ?? document;
  const InputClass = opts.InputCtor ?? HTMLInputElement;
  if (fieldsDisabled || closeBlocked || !rowId || !original || !panel || mode !== 'record') {
    throw new Error(
      'Correct retained validation and resolve parent/vegetation operations before source record navigation.'
    );
  }
  const control = event.currentTarget;
  if (
    !(control instanceof InputClass) ||
    control !== event.target ||
    activeDoc.activeElement !== control ||
    !panel.contains(control) ||
    !control.checkVisibility() ||
    control.disabled ||
    control.closest<HTMLElement>('[data-vegetation-column]')?.dataset.vegetationColumn !== column ||
    panel.dataset.twoPageVegetationPanel !== form ||
    panel.dataset.vegetationCurrentRow !== rowId
  ) {
    throw new Error('Observed Enter focus/control/physical owner differs from its planned vegetation field.');
  }
  if (typeof panel.querySelectorAll === 'function') {
    const inputs = Array.from(
      panel.querySelectorAll<HTMLInputElement>('[data-vegetation-column] input[type="text"]')
    ).filter((el) => !el.disabled && el.checkVisibility());
    const idx = inputs.indexOf(control);
    if (idx >= 0 && idx + 1 < inputs.length) return { nextInput: inputs[idx + 1], nextRowId: null };
  }
  const current = original.records.rows.findIndex((candidate) => candidate.rowId === rowId);
  const next = current >= 0 ? original.records.rows[current + 1] : undefined;
  if (!next) throw new Error('No next existing vegetation record. Automatic Save is unavailable.');
  return { nextInput: null, nextRowId: next.rowId };
}

export function computeVegCollectedCycle(opts: {
  fieldsDisabled: boolean;
  currentRowId: string | undefined;
  plannedRow: string;
  original: TwoPageVegetationOriginal | null;
  panel: HTMLElement | undefined;
  form: TwoPageVegetationForm;
  event: MouseEvent;
  draft: { value?: ReturnType<typeof vegetationSourceCell>; error?: string | null; raw?: string } | undefined;
  ButtonCtor?: abstract new (...args: never[]) => HTMLButtonElement;
}): string | null {
  const { fieldsDisabled, currentRowId, plannedRow, original, panel, form, event, draft } = opts;
  const ButtonClass = opts.ButtonCtor ?? HTMLButtonElement;
  if (
    fieldsDisabled ||
    !currentRowId ||
    currentRowId !== plannedRow ||
    !original ||
    !panel ||
    panel.dataset.twoPageVegetationPanel !== form ||
    panel.dataset.vegetationCurrentRow !== plannedRow
  ) {
    throw new Error('Observed vegetation owner/physical row differs from the planned Collected click.');
  }
  const button = event.currentTarget;
  const input = panel.querySelector<HTMLInputElement>('[data-vegetation-column="Collected"] input[type="text"]');
  if (
    !(button instanceof ButtonClass) ||
    button.disabled ||
    !panel.contains(button) ||
    !button.checkVisibility() ||
    !input ||
    input.disabled ||
    !input.checkVisibility()
  ) {
    throw new Error('Observed Collected controls are unavailable; no source value was cycled.');
  }
  const source = draft?.value ?? vegetationSourceCell(original, plannedRow, 'Collected');
  if (draft?.error || (source.storage !== 'null' && source.storage !== 'text'))
    throw new Error('Correct Collected validation/nontext storage manually before its source click.');
  const raw = draft?.raw ?? metadataCellText(source);
  if (input.value !== (source.storage === 'null' ? '' : raw.replace(/[\r\n]/g, '')))
    throw new Error('Observed Collected display differs from its retained draft/original.');
  return collectedNext(source.storage === 'null' ? null : source.text);
}
