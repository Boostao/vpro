import { Call, CancelledRejectionError } from '@wailsio/runtime';

export interface CancellableRead<T> extends PromiseLike<T> {
  cancel(): void;
}

const cancelledReads = new WeakSet<object>();

export class ReadRequests {
  private pending = new Set<CancellableRead<unknown>>();

  track<T>(request: CancellableRead<T>): Promise<T> {
    this.pending.add(request);
    return Promise.resolve(request).finally(() => this.pending.delete(request));
  }

  cancelAll(): void {
    const requests = [...this.pending];
    this.pending.clear();
    for (const request of requests) {
      cancelledReads.add(request);
      request.cancel();
    }
  }
}

export function trackIfCancellable<T>(reads: ReadRequests, request: PromiseLike<T>): Promise<T> {
  if (
    request !== null &&
    typeof request === 'object' &&
    typeof (request as { cancel?: unknown }).cancel === 'function'
  ) {
    return reads.track(request as CancellableRead<T>);
  }
  return Promise.resolve(request);
}

const LEADING_ERROR_PREFIX_RE = /^(?:(?:RuntimeError|CallError|Error|TypeError|RangeError):\s*)+/;

function translateInternalBackendJargon(cleaned: string): string {
  if (/literal plot requires exactly one original Env and Admin record/i.test(cleaned)) {
    return 'Plot was not found in the active project scope, or its site and admin records are incomplete.';
  }
  if (/literal plot requires\b/i.test(cleaned)) {
    return 'Plot number must contain 1 to 7 characters without spaces or unsupported control characters.';
  }
  if (/certified physical source membership/i.test(cleaned)) {
    return 'Plot changes could not be saved because one or more plot key fields (such as Plot Number or Project ID) are missing or unsupported. Check the plot header and try again.';
  }
  if (/is missing a required physical table/i.test(cleaned)) {
    return 'The selected file is missing required VPro project tables. Choose a complete VPro project file (.db).';
  }
  if (/file is not a database|file is encrypted or is not a database/i.test(cleaned)) {
    return 'The selected file is not a valid VPro project file (.db).';
  }
  return cleaned;
}

export function formatError(cause: unknown): string {
  let raw = '';
  if (cause instanceof Error) {
    raw = cause.message || cause.name || 'Unexpected error';
  } else if (typeof cause === 'string') {
    raw = cause;
  } else if (
    cause !== null &&
    typeof cause === 'object' &&
    'message' in cause &&
    typeof (cause as { message: unknown }).message === 'string'
  ) {
    raw = (cause as { message: string }).message;
  } else {
    raw = String(cause ?? '');
  }
  const stripped = raw.replace(LEADING_ERROR_PREFIX_RE, '').trim();
  if (!stripped) return 'Unexpected error';
  return translateInternalBackendJargon(stripped);
}

export function expectedReadCancellation(reason: unknown): boolean {
  return (
    reason instanceof CancelledRejectionError &&
    cancelledReads.has(reason.promise) &&
    reason.cause instanceof Call.RuntimeError &&
    reason.cause.message === 'context canceled'
  );
}

// Wails v3.1.0 runtime reports the backend acknowledgement even after its promise was cancelled.
if (typeof window !== 'undefined') {
  window.addEventListener('unhandledrejection', (event) => {
    if (expectedReadCancellation(event.reason)) event.preventDefault();
  });
}
