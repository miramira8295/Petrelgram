// 「有上限的钉」的顺序逻辑。纯函数，不碰位图。
//
// 【为什么需要它】pixelCache 的 pinPixelMap 是**钉一辈子、无上限**的，注释也
// 写明只该给"贵且到处复用"的东西（目前只有聊天背景）。头像不属于那一档：
// 它便宜，但**数量随发送者增长**，无上限地钉会一路涨下去。
//
// 可它又确实需要保护——头像和大图挤在同一个 LRU 预算里，滑过图多的会话就被
// 挤掉，回滚时重新解码，那一两帧露出首字母圆底，就是用户报的
// 「翻消息的时候对话头像会闪」（issue #137）。
//
// 折中：钉最近用到的 N 张，超出就把最旧的松开、还给 LRU。

export interface PinUpdate {
  // 更新后的钉住顺序，最旧的在前。
  next: string[];
  // 这一次被松开的（调用方据此 unpin）。
  released: string[];
}

// key 已经钉着就挪到末尾（刷新它的"最近使用"），否则追加；超出上限从头部松开。
// 不修改入参。
export function updateBoundedPins(current: string[], key: string, cap: number): PinUpdate {
  if (key === '' || cap <= 0) {
    return { next: current, released: [] };
  }
  const next: string[] = current.filter((k: string): boolean => k !== key);
  next.push(key);
  const released: string[] = [];
  while (next.length > cap) {
    released.push(next[0]);
    next.shift();
  }
  return { next: next, released: released };
}
