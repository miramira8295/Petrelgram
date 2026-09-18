// 点了一个**外部**链接（不是 t.me / tg:// 这类应用内能直接落到会话的）该干什么。
//
// 2026-09-18 用户要的三档：直接浏览器打开 / 点击复制 / 点击弹窗选择。
//
// 【为什么判据要单独一层】这件事有两个输入，而且第二个不能被设置覆盖：
//   · 用户选的档位；
//   · 这条链接**显示的文字是不是藏着另一个网址**（issue #169 第 6 条那道防钓鱼，
//     判据在 util/messageLinkAction.linkTextHidesUrl）。
// 藏链必须让用户看清真网址再决定，所以它把「直接打开」提级成「弹窗」——否则这个
// 新设置等于给钓鱼链接开了一条直通车。反过来「点击复制」不用提级：复制本身不出网，
// 是三档里最安全的那个。
//
// 纯函数，判据全部钉在单测里。执行在 util/webBrowserNav（所有入口唯一的分叉点）。

export const EXT_LINK_OPEN: string = 'open';   // 直接交给浏览器（默认，和以前一样）
export const EXT_LINK_COPY: string = 'copy';   // 只复制网址，不出网
export const EXT_LINK_ASK: string = 'ask';     // 弹一层「打开 / 复制」

export const EXT_LINK_DEFAULT: string = EXT_LINK_OPEN;

export function normalizeExternalLinkPolicy(value: string): string {
  if (value === EXT_LINK_OPEN || value === EXT_LINK_COPY || value === EXT_LINK_ASK) {
    return value;
  }
  // 认不出来（旧版本写进去的、或者被人手改过）一律回默认，别让一个坏值把链接点死。
  return EXT_LINK_DEFAULT;
}

// deceptive：显示文字和真实网址对不上。
export function externalLinkDecision(policy: string, deceptive: boolean): string {
  const p: string = normalizeExternalLinkPolicy(policy);
  if (p === EXT_LINK_COPY) {
    return EXT_LINK_COPY;
  }
  return (p === EXT_LINK_ASK || deceptive) ? EXT_LINK_ASK : EXT_LINK_OPEN;
}
