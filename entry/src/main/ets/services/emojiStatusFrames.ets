import { display } from '@kit.ArkUI';
import { stickerFramesCached, warmStickerFrameIndex } from './stickerFrameIndex';
import { alphaStickerHighBudget } from '../util/webm/AlphaStickerBudget';

// 表情状态（顶栏 / 资料页 / 设置页名字旁那个小图标）的帧缓存查询（2026-10-10）。
//
// 决定下不下载发生在拿到贴纸信息、还没有界面尺寸的地方（ProfileStore / 顶栏的 HeaderIdentitySession），所以
// 按各处里最大的那个框算：缓存只认不小于要的尺寸档，按最大框查到的对每一处都够用。
const EMOJI_STATUS_MAX_VP: number = 24;
const EMOJI_STATUS_CATEGORY: string = 'emojiStatus';

function maxBoxPx(): number {
  try {
    return Math.ceil(EMOJI_STATUS_MAX_VP * display.getDefaultDisplaySync().densityPixels);
  } catch (e) {
    // 取不到屏幕密度就按常见的 3.5 倍算，尺寸档向上取，偏大只会少命中、不会出错。
    return Math.ceil(EMOJI_STATUS_MAX_VP * 3.5);
  }
}

// 这个 ID 的帧缓存在不在盘上。索引没建好先等它建完（第一次进资料页时可能还没扫过）。
export async function emojiStatusFramesCached(uid: string): Promise<boolean> {
  if (uid === '') {
    return false;
  }
  try {
    await warmStickerFrameIndex();
  } catch (e) {
    console.error(`emojiStatusFrames: warm failed: ${e}`);
    return false;
  }
  return stickerFramesCached(uid, maxBoxPx(), alphaStickerHighBudget(EMOJI_STATUS_CATEGORY));
}
