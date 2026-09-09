import { ChatKind } from './ChatEntry';
import { scopeOfKind } from './ScopeMuteStore';

// 分类「消息预览」开关（私聊 / 群组 / 频道）的进程内缓存。
//
// 【为什么需要它】`show_preview` 关掉之后，**服务端推送**会自己把内容裁掉，
// 但**应用在前台自己拼的本地通知**是另一条路：它直接 formatPreview(message)，
// 从来没查过这个开关。于是用户关掉「消息预览」之后，锁屏上照样能看到完整正文
// 和发送者名字——这个开关只生效了一半（2026-09-08 代码扫描发现）。
//
// 值本来就在 getScopeNotificationSettings 的返回里（store/NotificationApi 也
// 早就解析好了），只是拿到手就扔了：那段代码只取了 mute_for。
//
// 【为什么不做纪元】和 ScopeMuteStore 不同，这个值只在**构造通知的那一刻**读
// 一次，没有任何界面按它渲染，不需要带动全表重建。
//
// 【只认分类，不认单会话】TDLib 的会话级设置能覆盖分类默认
// （chatNotificationSettings.use_default_show_preview），但 ChatEntry 上没有
// 这个字段，加它要动 store 的一圈。而我们的通知设置页暴露的**就是按分类的
// 那三个开关**，覆盖到分类即覆盖了用户能操作的全部。单会话覆盖是后续的事。

// 读不到时按"显示预览"——与 TDLib 的默认值一致，也不会凭空把用户已有的
// 通知内容抹掉。真正关心隐私的用户会去关那个开关，那时才走另一支。
const preview: Map<string, boolean> = new Map<string, boolean>();

export function scopePreview(scope: string): boolean {
  return preview.get(scope) ?? true;
}

export function scopePreviewForKind(kind: ChatKind): boolean {
  return scopePreview(scopeOfKind(kind));
}

export function setScopePreview(scope: string, value: boolean): void {
  preview.set(scope, value);
}

// 换账号时清空：上一个账号关了预览，新账号没关，留着就是错的
// （与 resetScopeMute 同一理由）。
export function resetScopePreview(): void {
  preview.clear();
}
