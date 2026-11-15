import { ContextService, PlotEntryService } from '../../bindings/github.com/boostao/vpro/app';
import type { UserAccreditation } from '../../bindings/github.com/boostao/vpro/app/internal/vprocore/models';

export type { UserAccreditation };

export interface UserSetupPort {
  getUserSetup(contextId: string): Promise<UserAccreditation>;
  setUserName(contextId: string, user: string): Promise<UserAccreditation>;
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
