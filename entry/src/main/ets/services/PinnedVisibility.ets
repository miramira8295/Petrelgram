import { PinnedVisibility } from '../util/pinnedVisibilityState';

// 置顶条显隐已经收敛成一个全局开关（理由见 util/pinnedVisibilityState 的注释），
// 所以这里不再按 account:chatId 缓存实例、也不再读 preferences：所有会话看的是
// 同一份状态。函数签名保留，调用点（LiveTopCardController.resetTopCardState）
// 一个字都不用改。
const sharedPinnedVisibility: PinnedVisibility = new PinnedVisibility();

export function pinnedVisibilityFor(_chatId: number): PinnedVisibility {
  return sharedPinnedVisibility;
}
