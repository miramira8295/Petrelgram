// 把同一份内容发给多个会话的编排层。
//
// 【为什么单独一个文件】这里只做编排——串行、计数、收集失败——不碰
// ShareInbox 也不碰 MessageStore，所以能在宿主上单测；真正的发送由调用方
// 喂进来的 send 回调完成（转发那边是 forwardMessages 分批，分享那边是
// util/shareArrival 的 sendShareDirectly）。两个面板共用这一份。

export interface FanoutResult {
  ok: number;
  failed: number;
  // 失败的会话 id，按发送顺序。调用方据此决定提示什么、要不要留住载荷。
  failedIds: number[];
}

// 去重但保序：选择态那边已经守了一次（util/targetSelection 不让同一个 id
// 进两次），这里再守一次——任何一处出错都不会真的发两遍。
function uniqueInOrder(ids: number[]): number[] {
  const out: number[] = [];
  for (const id of ids) {
    if (out.indexOf(id) < 0) {
      out.push(id);
    }
  }
  return out;
}

// 依次发给每个目标。
//
// **串行**是有意的，不是图省事：并发会同时挤占 TDLib 的上传队列（一次分享
// 可能带着几十兆的视频），而且失败时分不清是这一条自己的问题还是被别的拖垮。
//
// **永不 reject**：一个目标失败不能中断其余的——用户选了 5 个，不能因为第 2 个
// 发不出去就把后面 3 个也吞掉。失败如实计进 failedIds，由调用方汇总提示。
export async function fanoutShare(
  chatIds: number[],
  send: (chatId: number) => Promise<void>
): Promise<FanoutResult> {
  const targets: number[] = uniqueInOrder(chatIds);
  const failedIds: number[] = [];
  let ok: number = 0;
  for (const chatId of targets) {
    try {
      await send(chatId);
      ok++;
    } catch (e) {
      failedIds.push(chatId);
    }
  }
  return { ok: ok, failed: failedIds.length, failedIds: failedIds };
}
