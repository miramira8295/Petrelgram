// 会话列表数据源：V1（ChatStore 自己算）与 V2（worker 投递、镜像维护）。
//
// **切换就是这一行**：把 SOURCE_V2 改成 false 即回到 V1，一次编译的事，没有
// 运行时状态需要回滚——两条生产路径各自独立，V1 的 handler 一行没动。
//
// V2 下读的是 store/chatMirror 里由 worker 投递维护的那份；镜像还没有的条目
// 回退本地，避免启动早期列表空一格。

import { ChatEntry } from '../store/ChatEntry';

const SOURCE_V2: boolean = false;

export function chatListV2Enabled(): boolean {
  return SOURCE_V2;
}

// V2 下优先用镜像；镜像还没有这条（worker 慢一拍、刚启动）就回退本地。
export function pickEntry(useMirror: boolean, local: ChatEntry | undefined,
  mirrored: ChatEntry | undefined): ChatEntry | undefined {
  if (!useMirror) {
    return local;
  }
  return mirrored !== undefined ? mirrored : local;
}
