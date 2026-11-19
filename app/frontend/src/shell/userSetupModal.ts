import { ContextService, PictureService, PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
import type { UserAccreditation } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';

export type { UserAccreditation };

export interface PictureOptionsState {
  pictureLibraryPath: string;
  childDirectory: string;
  managerDirectory: string;
  effectiveLibraryPath: string;
  effectiveChildDirectory: string;
  effectiveManagerDirectory: string;
  defaultLibraryPath: string;
  defaultImagesDirectory: string;
  envOverride: boolean;
}

export interface PictureOptionsUpdate {
  pictureLibraryPath: string;
  childDirectory: string;
  managerDirectory: string;
}

export interface UserSetupPort {
  getUserSetup(contextId: string): Promise<UserAccreditation>;
  setUserName(contextId: string, user: string): Promise<UserAccreditation>;
  getPictureOptions?(): Promise<PictureOptionsState>;
  savePictureOptions?(update: PictureOptionsUpdate): Promise<PictureOptionsState>;
}

export const defaultUserSetupPort: UserSetupPort = {
  async getUserSetup(contextId: string): Promise<UserAccreditation> {
    if (contextId) {
      return ContextService.GetUserSetup(contextId);
    }
    return PlotEntryService.UserAccreditationStatus();
  },
  async setUserName(contextId: string, user: string): Promise<UserAccreditation> {
    if (contextId) {
      return ContextService.SetUserName(contextId, user);
    }
    await PlotEntryService.SetCurrentUser(user);
    return PlotEntryService.UserAccreditationStatus();
  },
  async getPictureOptions(): Promise<PictureOptionsState> {
    const bound = PictureService as unknown as {
      GetPictureOptions?: () => Promise<PictureOptionsState>;
    } | undefined;
    if (bound && typeof bound.GetPictureOptions === 'function') {
      return bound.GetPictureOptions();
    }
    const { Call } = await import('@wailsio/runtime');
    return Call.ByName('main.PictureService.GetPictureOptions') as Promise<PictureOptionsState>;
  },
  async savePictureOptions(update: PictureOptionsUpdate): Promise<PictureOptionsState> {
    const bound = PictureService as unknown as {
      SavePictureOptions?: (req: PictureOptionsUpdate) => Promise<PictureOptionsState>;
    } | undefined;
    if (bound && typeof bound.SavePictureOptions === 'function') {
      return bound.SavePictureOptions(update);
    }
    const { Call } = await import('@wailsio/runtime');
    return Call.ByName('main.PictureService.SavePictureOptions', update) as Promise<PictureOptionsState>;
  },
};

export function validateUserSetupName(raw: string): { valid: boolean; value: string; error: string } {
  const value = String(raw ?? '').trim();
  if (!value || value.includes('\0')) {
    return {
      valid: false,
      value,
      error: 'Enter a non-empty VPro audit user name (stored as Current.User).',
    };
  }
  return { valid: true, value, error: '' };
}

function isAbsoluteFileSystemPath(value: string): boolean {
  return value.startsWith('/') || /^[A-Za-z]:[\\/]/.test(value) || /^\\\\[^\\]+\\[^\\]+/.test(value);
}

export function validatePictureOptionsInput(raw: PictureOptionsUpdate): {
  valid: boolean;
  value: PictureOptionsUpdate;
  error: string;
} {
  const pictureLibraryPath = String(raw.pictureLibraryPath ?? '').trim();
  const childDirectory = String(raw.childDirectory ?? '').trim();
  const managerDirectory = String(raw.managerDirectory ?? '').trim();
  const entries: Array<[string, string]> = [
    ['Picture library file', pictureLibraryPath],
    ['Plot form image folder', childDirectory],
    ['Plot Pictures manager image folder', managerDirectory],
  ];
  for (const [label, val] of entries) {
    if (val.includes('\0')) {
      return {
        valid: false,
        value: { pictureLibraryPath, childDirectory, managerDirectory },
        error: `${label} cannot contain NUL characters.`,
      };
    }
    if (val !== '' && !isAbsoluteFileSystemPath(val)) {
      return {
        valid: false,
        value: { pictureLibraryPath, childDirectory, managerDirectory },
        error: `${label} must be a full absolute path or left blank to use the workspace default.`,
      };
    }
  }
  return {
    valid: true,
    value: { pictureLibraryPath, childDirectory, managerDirectory },
    error: '',
  };
}
