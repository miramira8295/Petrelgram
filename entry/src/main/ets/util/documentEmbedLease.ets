// A separate pool: WebViews must not consume sticker/video animation slots.
// O(1) acquire/release/cancel; invisible owners remove themselves immediately.
import { AnimationSlotPool } from './animationSlotPool';
export const documentEmbedPool: AnimationSlotPool = new AnimationSlotPool(2);
