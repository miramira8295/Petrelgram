import { TdObject } from './TdTypes';

// TDLib: 0=fatal, 1=error, 2=warning, 3=info, 4=debug.
// The native callback threshold only filters forwarding; it does not stop
// TDLib from formatting and writing its own info/debug logs.
export const TD_LOG_VERBOSITY: number = 2;

export interface TdLogPolicyResult {
  previousLevel: number | undefined;
  effectiveLevel: number | undefined;
  verified: boolean;
}

function executeLogRequest(execute: (json: string) => string, request: TdObject): TdObject | undefined {
  try {
    const response = JSON.parse(execute(JSON.stringify(request))) as TdObject | null;
    return response !== null && typeof response === 'object' ? response : undefined;
  } catch (_e) {
    // Logging policy failure must not prevent receiving messages. The caller
    // reports verification failure without logging arbitrary response payloads.
    return undefined;
  }
}

function readLevel(execute: (json: string) => string): number | undefined {
  const response = executeLogRequest(execute, { '@type': 'getLogVerbosityLevel' });
  if (response === undefined || response['@type'] !== 'logVerbosityLevel') { return undefined; }
  const level = response['verbosity_level'];
  return typeof level === 'number' && Number.isInteger(level) && level >= 0 ? level : undefined;
}

// Synchronous and process-wide. Call before starting either the direct or
// worker bridge, including account switches. Keep the existing log stream and
// warning/error callback; no polling, persistence or silent logging disable.
export function configureTdLogging(execute: (json: string) => string): TdLogPolicyResult {
  const previousLevel = readLevel(execute);
  const result = executeLogRequest(execute, {
    '@type': 'setLogVerbosityLevel', 'new_verbosity_level': TD_LOG_VERBOSITY
  });
  const effectiveLevel = readLevel(execute);
  return {
    previousLevel,
    effectiveLevel,
    verified: result !== undefined && result['@type'] === 'ok' && effectiveLevel === TD_LOG_VERBOSITY
  };
}
