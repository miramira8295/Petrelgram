// 通知正文怎么拼。纯函数，无 IO。
//
// 关掉「消息预览」时**发送者名字也要一起藏**：只藏正文、留着"张三:"，等于
// 告诉旁人"张三给你发消息了"——泄露的信息量没少多少，而用户关这个开关就是
// 不想让人看见。官方客户端同样是整条换成一句中性文案。

export interface NotificationBody {
  // 通知标题。关掉预览时会被换成中性文案（会话名本身也是内容）。
  title: string;
  text: string;
}

// `allowPreview` 为 false 时，标题和正文都换成传进来的中性文案。
// `who` 是发送者前缀（群里才有，私聊为空串）。
export function notificationBody(chatTitle: string, who: string, preview: string,
  allowPreview: boolean, genericTitle: string, genericText: string): NotificationBody {
  if (!allowPreview) {
    return { title: genericTitle, text: genericText };
  }
  const body: string = preview !== '' ? preview : genericText;
  return {
    title: chatTitle,
    text: who !== '' ? `${who}: ${body}` : body
  };
}
