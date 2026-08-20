// 气泡里那枚身份标签显示什么字。
//
// 规则和成员列表保持一致（见 util/memberRole）：有自定义头衔就用头衔，否则
// 按身份给默认词。官方端也是这样——群主把"创建者"改成"打工皇帝"之后，消息
// 旁边显示的就该是"打工皇帝"。
//
// 返回 str() 的结果：宿主单测里没装文案源，str() 原样返回 key，于是断言落在
// "选了哪条文案"上而不是文案本身。

import { str } from './strings';

export function adminLabelOf(isCreator: boolean, customTitle: string): string {
  const trimmed: string = customTitle.trim();
  if (trimmed !== '') {
    return trimmed;
  }
  return isCreator ? str('ga_creator') : str('ga_admin');
}
