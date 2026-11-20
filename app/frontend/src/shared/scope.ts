export type ProjectSUScope = {
  contextId: string;
  project: string;
  projectPath: string;
  su: string;
  suPath: string;
};

export type GoogleEarthScope = ProjectSUScope;

function isWellFormedUTF16(value: string): boolean {
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

export function ownedScope(value: ProjectSUScope, expected: ProjectSUScope): boolean {
  return (
    Boolean(expected.contextId) &&
    (['contextId', 'project', 'projectPath', 'su', 'suPath'] as const).every(
      (key) => typeof expected[key] === 'string' && isWellFormedUTF16(expected[key]) && value[key] === expected[key]
    )
  );
}
