// 分享面板里点头像之后干什么。纯函数，无 IO。
//
// 两档：
//   'send' 直接发送——点完就发出去，应用闪一下自动退回后台，人还留在图库里；
//   'edit' 进会话编辑——内容落到输入框上方，可以配文字、可以反悔，按发送才走。
//
// 【为什么要有这个开关】"直接发送"少一步，但**不可撤回**：点错人就发出去了。
// 两种用法都成立，取决于当下是"随手转给某人"还是"要配段话"，所以交给用户选，
// 并且记住上次的选择。
//
// 【为什么存文件不存 Preferences】面板跑在独立进程里，读不到 AppStorage、
// 也不能 import store（会把 ArkUI 依赖拖进那个进程）。文件是两个进程唯一的
// 公共地面，与 services/crashRecordStore 的"标记文件"同一思路。

export type ShareSendMode = 'send' | 'edit';

// 默认直接发送：分享面板本来就是"快"的场景，多数时候不需要配文字。
export const DEFAULT_SEND_MODE: ShareSendMode = 'send';

// 文件内容 → 档位。认不出来的一律回默认值——这个文件跨进程读写，
// 半截写入、手工改坏都可能，绝不能因此让面板起不来。
export function parseSendMode(text: string): ShareSendMode {
  const trimmed: string = text.trim();
  return trimmed === 'edit' ? 'edit' : (trimmed === 'send' ? 'send' : DEFAULT_SEND_MODE);
}

export function serializeSendMode(mode: ShareSendMode): string {
  return mode;
}

export function isAutoSend(mode: ShareSendMode): boolean {
  return mode === 'send';
}
