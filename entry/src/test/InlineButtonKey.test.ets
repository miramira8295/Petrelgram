import { describe, expect, it } from '@ohos/hypium';
import { InlineBtn } from '../main/ets/store/MessageEntry';
import { inlineButtonKey, inlineButtonRowKey } from '../main/ets/util/inlineButtonKey';

function button(url: string, callbackData: string, isGame: boolean, style: string = ''): InlineBtn {
  return { text: '查看', url, callbackData, isGame, style };
}

export default function inlineButtonKeyTest() {
  describe('inlineButtonKey', () => {
    it('同名按钮换链接时内外两层键都变化', 0, (): void => {
      const before: InlineBtn[] = [button('https://a.example', '', false)];
      const after: InlineBtn[] = [button('https://b.example', '', false)];
      expect(inlineButtonKey(0, 0, before[0]) === inlineButtonKey(0, 0, after[0])).assertFalse();
      expect(inlineButtonRowKey(0, before) === inlineButtonRowKey(0, after)).assertFalse();
    });

    it('回调、游戏分支和样式都属于身份', 0, (): void => {
      const base: InlineBtn = button('', 'one', false, '');
      expect(inlineButtonKey(0, 0, base) ===
        inlineButtonKey(0, 0, button('', 'two', false, ''))).assertFalse();
      expect(inlineButtonKey(0, 0, base) ===
        inlineButtonKey(0, 0, button('', 'one', true, ''))).assertFalse();
      expect(inlineButtonKey(0, 0, base) ===
        inlineButtonKey(0, 0, button('', 'one', false, 'danger'))).assertFalse();
    });

    it('相同按钮保持稳定键', 0, (): void => {
      const row: InlineBtn[] = [button('https://a.example', '', false, 'primary')];
      expect(inlineButtonRowKey(2, row)).assertEqual(inlineButtonRowKey(2, row));
    });
  });
}
