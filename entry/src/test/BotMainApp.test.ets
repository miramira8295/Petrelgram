import { describe, expect, it } from '@ohos/hypium';
import { botHasMainApp, mainAppChatId } from '../main/ets/util/botMainApp';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function user(type: TdObject | null): TdObject {
  const u: TdObject = { '@type': 'user', 'id': 42 };
  if (type !== null) {
    u['type'] = type;
  }
  return u;
}

// 机器人资料页的「打开应用」（#201 第 2 条）。
export default function botMainAppTest() {
  describe('BotMainApp', () => {
    it('带主小程序的机器人才出入口', 0, () => {
      expect(botHasMainApp(user({ '@type': 'userTypeBot', 'has_main_web_app': true } as TdObject)))
        .assertTrue();
      expect(botHasMainApp(user({ '@type': 'userTypeBot', 'has_main_web_app': false } as TdObject)))
        .assertFalse();
      expect(botHasMainApp(user({ '@type': 'userTypeBot' } as TdObject))).assertFalse();
    });

    it('普通用户、缺类型、空对象都没有', 0, () => {
      expect(botHasMainApp(user({ '@type': 'userTypeRegular' } as TdObject))).assertFalse();
      expect(botHasMainApp(user(null))).assertFalse();
      expect(botHasMainApp(undefined)).assertFalse();
      const nullType: TdObject = JSON.parse('{"id":1,"type":null}') as TdObject;
      expect(botHasMainApp(nullType)).assertFalse();
    });

    // 从群里点进来：面板管的是那个群；群 id 是负数，不能用 > 0 判断。
    it('从群里进来用群，否则用和机器人的私聊', 0, () => {
      expect(mainAppChatId(-1001234, 42)).assertEqual(-1001234);
      expect(mainAppChatId(0, 42)).assertEqual(42);
    });
  });
}
