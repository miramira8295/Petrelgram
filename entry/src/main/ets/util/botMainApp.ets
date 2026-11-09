import { TdObject } from '../tdkit/TdTypes';

// 机器人的主小程序（Main Mini App）入口（#201 第 2 条、#219 第 4 条）。
//
// 报告人说的「机器人设置面板」是 nmBot 这类机器人的主小程序：官方客户端在机器人资料页
// 有「打开应用」，点开就是它的网页管理面板。TDLib 在 userTypeBot.has_main_web_app 上
// 标出有没有（字段名已在随包 libtdjson.so 里核对过），URL 用 getMainWebApp 取。

// 这个用户是不是一个带主小程序的机器人。
export function botHasMainApp(user: TdObject | undefined | null): boolean {
  if (user === undefined || user === null) {
    return false;
  }
  const type = user['type'] as TdObject | undefined | null;
  if (type === undefined || type === null || type['@type'] !== 'userTypeBot') {
    return false;
  }
  return (type['has_main_web_app'] as boolean | undefined) === true;
}

// 在哪个会话里打开。从群成员列表点进来就是那个群——nmBot 的管理面板管的就是
// 「当前这个群」（#201 截图的标题就是报告人的群名）；否则用和机器人的私聊，
// 私聊的 chat_id 就是对方的 user_id。
export function mainAppChatId(fromChatId: number, botUserId: number): number {
  return fromChatId !== 0 ? fromChatId : botUserId;
}
