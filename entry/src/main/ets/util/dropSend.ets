import { SharedPayload } from './sharedContent';
import { ShareArrivalHost, sendShareDirectly, remainingDirectShare } from './shareArrival';
import { ShareMediaGeometry } from './shareLivePhoto';
import { SendProgress } from './sendProgress';
import { SendPermissionError } from '../store/SendPermissionApi';
import { str } from './strings';

export interface DropSendResult {
  remaining: SharedPayload | null;
  uncertain: boolean;
  error: string;
}

// One attempt is O(N). Only failed attempts construct a remaining batch; completed
// requests and their caption are excluded. Unknown outcomes must not be retried.
export async function sendDropBatch(payload: SharedPayload, host: ShareArrivalHost,
  active: () => boolean): Promise<DropSendResult> {
  const progress = new SendProgress();
  try {
    await sendShareDirectly(payload, host, new Map<string, ShareMediaGeometry>(), progress, active);
    return { remaining: null, uncertain: false, error: '' };
  } catch (error) {
    if (!active()) { return { remaining: null, uncertain: false, error: '' }; }
    const uncertain = progress.hasUncertain();
    return { remaining: remainingDirectShare(payload, progress), uncertain,
      error: uncertain ? '' : (error instanceof SendPermissionError ? error.message : str('fw_failed')) };
  }
}
