// 「正在播放」的全局旁路通道。
//
// **为什么需要它。** 底栏的迷你播放条要显示曲名/演唱者/封面，而这些只在
// **启动播放的那个 ChatPage** 的 MessageEntry 里：
//   - MainScreen（底栏的家）对播放一无所知，全文一处播放服务都不引用；
//   - VoicePlayback 的 VoiceState 只有 playingId / mode / paused / status，
//     没有任何曲目信息；
//   - MediaPlaybackKeepAlive 给系统媒体通知填的也只是通用的 str('svc_playing')。
// 回到会话列表时 ChatPage 已经销毁，那份 MessageEntry 就没了——所以曲目信息
// 必须在起播的那一刻**离开页面**，存到一个和页面生命周期无关的地方。
//
// 和 translationChannel / chatJumpChannel 同构。区别是这里**要留状态**：订阅方
// （底栏）是在播放开始之后才挂上来的（用户从会话页退回列表），没有当前值就
// 什么都画不出来。所以 current 存着，subscribe 时立刻回灌一次。
//
// path 也一起带走：暂停/继续走 VoicePlayback 的全局单例，它要文件路径，而那
// 同样是页面里的东西。带上之后底栏不依赖任何页面就能控制播放。

export interface NowPlaying {
  chatId: number;
  messageId: number;
  // 空串表示没有元数据，调用方自己退回文件名/占位文案。
  title: string;
  performer: string;
  coverPath: string;
  // 本地文件路径，暂停/继续要用。
  path: string;
  durationSec: number;
}

type NowPlayingListener = (state: NowPlaying | null) => void;

let current: NowPlaying | null = null;
const subs: Set<NowPlayingListener> = new Set();

export function currentNowPlaying(): NowPlaying | null {
  return current;
}

// 订阅并**立刻收到一次当前值**：底栏可能在播放开始很久之后才挂上来。
export function subscribeNowPlaying(listener: NowPlayingListener): () => void {
  subs.add(listener);
  listener(current);
  return (): void => { subs.delete(listener); };
}

export function publishNowPlaying(state: NowPlaying | null): void {
  current = state;
  subs.forEach((cb: NowPlayingListener): void => cb(state));
}

// 播放停止/切走时清空。带 messageId 是为了**只让当前这条清自己**：切下一首时
// 旧条目的收尾回调可能晚于新条目的发布到达，无条件清会把新的一起抹掉。
export function clearNowPlaying(messageId: number): void {
  if (current === null || current.messageId !== messageId) {
    return;
  }
  publishNowPlaying(null);
}

// 只给单测用：模块级状态在同一个进程里跨用例活着。
export function resetNowPlayingChannel(): void {
  current = null;
  subs.clear();
}
