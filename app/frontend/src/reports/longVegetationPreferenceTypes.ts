export interface LongVegetationStandardPreferenceProps<TSession> {
  contextId: string;
  preferences: TSession;
  operationHeld?: boolean;
  mutationHeld?: boolean;
  onReadBusyChange: (busy: boolean) => void;
}
