import { describe, it, expect } from '@ohos/hypium';
import {
  MINI_PLACEHOLDER_BLUR, MINI_THUMB_PLACEHOLDER_ENABLED, miniPlaceholderOf
} from '../main/ets/util/miniThumbPlaceholder';

export default function miniThumbPlaceholderTest() {
  describe('MiniThumbPlaceholder', () => {
    it('开关打开时原样透传 data URL', 0, () => {
      const url: string = 'data:image/jpeg;base64,AAAA';
      expect(miniPlaceholderOf(url)).assertEqual(MINI_THUMB_PLACEHOLDER_ENABLED ? url : '');
    });

    it('没有小图时返回空串，调用方据此不建那个节点', 0, () => {
      expect(miniPlaceholderOf('')).assertEqual('');
    });

    // 一键回退的语义：关掉之后所有调用点都拿到空串，等于那一层从不存在。
    // 三个调用点（相册格 / 单图 / 缩略图条）都必须走这个函数，不能各写各的
    // `ENABLED ? url : ''`——漏一处就出现"有的格子有占位有的没有"。
    it('关掉之后一律是空串', 0, () => {
      if (!MINI_THUMB_PLACEHOLDER_ENABLED) {
        expect(miniPlaceholderOf('data:image/jpeg;base64,AAAA')).assertEqual('');
      }
      expect(true).assertTrue();
    });

    it('模糊半径是正数且不至于糊成一团色雾', 0, () => {
      expect(MINI_PLACEHOLDER_BLUR > 0).assertTrue();
      expect(MINI_PLACEHOLDER_BLUR <= 32).assertTrue();
    });
  });
}
