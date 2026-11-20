import type {
  FS882Header,
  HumusRecord,
  MineralRecord,
  SoilSuggestion,
} from '../../bindings/github.com/boostao/vpro/app';
import type { SoilDrafts, SoilKind } from './soilChildEditor';

export interface FS882SoilHorizonSectionProps {
  draft: FS882Header;
  original: FS882Header | null;
  capabilities: Record<string, boolean | undefined>;
  sourceHeaderValues: Map<string, unknown>;
  ordinarySoilUnavailable: string | null;
  historicalSoilUnavailable: string | null;
  showSoilCodeReference?: boolean;
  soilReferenceBusy: boolean;
  soilReferenceError: string | null;
  soilEditingDisabled: boolean;
  soilUnsaved: boolean;
  headerInputsDisabled: boolean;
  busy: boolean;
  headerWorkflowBusy: boolean;
  coordinateBusy: boolean;
  workingUnitBusy: boolean;
  qualityBusy: boolean;
  siteCodeBusy: boolean;
  regionCodeBusy: boolean;
  soilCodeBusy: boolean;
  geologyCodeBusy: boolean;
  parentCodeBusy: boolean;
  drainageBusy: boolean;
  childRevision: number;
  soilDrafts: SoilDrafts;
  soilSuggestions: SoilSuggestion[];
  humusList: HumusRecord[];
  mineralList: MineralRecord[];
  sourceRows: (
    name: string
  ) => Array<{ id: number; values: Record<string, string | number | boolean | null | undefined> }>;
  markDirty: () => void;
  validateHeader: (key: string, message: string | null) => void;
  loadSoilSuggestions: () => Promise<void>;
  openNewChild: (kind: 'humus' | 'mineral' | 'other') => void;
  stageSoilCell: (kind: SoilKind, id: number, column: string, raw: string) => void;
  deleteSourceChild: (name: string, id: number) => Promise<void>;
  deleteHumus: (id: number) => Promise<void>;
}
