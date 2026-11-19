import { wellFormedUTF16 } from './qualityEditor';
import type { SpeciesCodeCheckOption, SpeciesCodeCheckReview, SpeciesCodeCheckUpdate } from '../../bindings/github.com/boostao/vpro/app';
import type { SpeciesCodeCheckRow } from '../../bindings/github.com/boostao/vpro/app/internal/validation/models';

export interface CodeCheckCell {
  row: SpeciesCodeCheckRow;
  raw: string;
  error: string | null;
  reviewed: string | null;
}
export interface CodeCheckDraft {
  review: { project: string; su: string; rows: SpeciesCodeCheckRow[] };
  cells: Record<string, CodeCheckCell>;
  ignored: number[];
}

export const CODE_CHECK_STATUSES = ['master', 'user', 'missing', 'unlisted', 'synonym'] as const;
export const UNRESOLVED_CODE_CHECK_STATUSES = ['unlisted', 'missing', 'synonym'] as const;

export function beginCodeCheck(review: SpeciesCodeCheckReview): CodeCheckDraft {
  if (!review.project || !review.su || !Array.isArray(review.rows)) throw new Error('Species check needs an explicit project/working-unit scope and complete rows.');
  const ids = new Set<number>();
  for (const row of review.rows) {
    const validCode = row.code === null || (typeof row.code === 'string' && wellFormedUTF16(row.code));
    const validSuggested = row.suggestedCode === undefined || row.suggestedCode === null ||
      (typeof row.suggestedCode === 'string' && wellFormedUTF16(row.suggestedCode));
    if (!Number.isInteger(row.id) || row.id < -2147483648 || row.id > 2147483647 || ids.has(row.id) || !row.plotNumber ||
        !(CODE_CHECK_STATUSES as readonly string[]).includes(row.status) || !validCode || !validSuggested) {
      throw new Error('Species check returned a missing, ambiguous or malformed source identity; reload the scope.');
    }
    ids.add(row.id);
  }
  return { review: { project: review.project, su: review.su, rows: review.rows }, cells: {}, ignored: [] };
}

export function unresolvedCodeCheckRows(draft: CodeCheckDraft): SpeciesCodeCheckRow[] {
  return draft.review.rows.filter(row => (UNRESOLVED_CODE_CHECK_STATUSES as readonly string[]).includes(row.status) && !draft.ignored.includes(row.id));
}

export function suggestedCodeForRow(row: SpeciesCodeCheckRow): string | null {
  const suggested = row.suggestedCode ?? null;
  if (row.status !== 'synonym' || typeof suggested !== 'string' || suggested === '' || suggested === row.code) return null;
  if (!wellFormedUTF16(suggested) || suggested.length > 8) return null;
  return suggested;
}

export function stageSuggestedCodeCheck(draft: CodeCheckDraft, id: number): CodeCheckDraft {
  const row = sourceRow(draft, id);
  const suggested = suggestedCodeForRow(row);
  if (!suggested) throw new Error('Species check row has no valid <= 8 UTF-16 suggested replacement code.');
  return stageCodeCheck(draft, id, suggested);
}

function sourceRow(draft: CodeCheckDraft, id: number): SpeciesCodeCheckRow {
  const rows = draft.review.rows.filter(row => row.id === id);
  if (rows.length !== 1) throw new Error('Species check source row is missing or ambiguous.');
  return rows[0];
}

export function stageCodeCheck(draft: CodeCheckDraft, id: number, raw: string): CodeCheckDraft {
  const row = sourceRow(draft, id);
  const error = !wellFormedUTF16(raw) ? 'Replacement contains incomplete Unicode; raw input was not repaired.'
    : raw.length > 8 ? 'Replacement exceeds 8 UTF-16 units; raw input was not truncated.'
    : raw === '' ? 'Enter a nonempty literal replacement or Ignore without writing.'
    : raw === row.code ? null : 'Review this literal replacement against current master/user definitions before saving.';
  return { ...draft, ignored: draft.ignored.filter(value => value !== id),
    cells: { ...draft.cells, [String(id)]: { row, raw, error, reviewed: null } } };
}

export function acceptCodeCheckTarget(draft: CodeCheckDraft, id: number, entered: string, options: readonly SpeciesCodeCheckOption[], all: boolean): CodeCheckDraft {
  const cell = draft.cells[String(id)];
  if (!cell || cell.raw !== entered || entered === '' || !wellFormedUTF16(entered) || entered.length > 8 ||
      !options.some(option => option.code === entered && ['master', 'user'].includes(option.source))) {
    throw new Error('Reviewed replacement no longer matches the original entry or a literal registered definition.');
  }
  const selected = all ? draft.review.rows.filter(row => row.code === cell.row.code) : [sourceRow(draft, id)];
  let next = draft;
  for (const row of selected) {
    next = stageCodeCheck(next, row.id, entered);
    next = { ...next, cells: { ...next.cells, [String(row.id)]: { ...next.cells[String(row.id)], error: null, reviewed: entered } } };
  }
  return next;
}

export function ignoreCodeCheck(draft: CodeCheckDraft, id: number, all: boolean): CodeCheckDraft {
  const source = sourceRow(draft, id);
  const ids = all ? draft.review.rows.filter(row => row.code === source.code).map(row => row.id) : [id];
  const cells = { ...draft.cells };
  for (const value of ids) delete cells[String(value)];
  return { ...draft, cells, ignored: [...new Set([...draft.ignored, ...ids])] };
}

export function codeCheckErrors(draft: CodeCheckDraft): string[] {
  return Object.values(draft.cells).flatMap(cell => cell.error ? [`${cell.row.plotNumber}, row ${cell.row.id}: ${cell.error}`] : []);
}

export function codeCheckUpdates(draft: CodeCheckDraft): SpeciesCodeCheckUpdate[] {
  const errors = codeCheckErrors(draft);
  if (errors.length) throw new Error(errors[0]);
  return Object.values(draft.cells).flatMap(cell => {
    const source = sourceRow(draft, cell.row.id);
    if (source.plotNumber !== cell.row.plotNumber || source.code !== cell.row.code) throw new Error('Species check original context changed; review it again.');
    if (cell.raw === source.code) return [];
    if (cell.reviewed !== cell.raw) throw new Error('Species check requires the original explicit replacement review.');
    return [{ id: source.id, plotNumber: source.plotNumber, expected: source.code, value: cell.raw }];
  });
}
