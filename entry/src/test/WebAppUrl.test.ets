import { describe, expect, it } from '@ohos/hypium';
import { webAppUrlOf } from '../main/ets/util/webAppUrl';

// 小程序应答里的网址：旧形状是字符串，随包 TDLib 里是 {url, require_same_origin} 对象。
export default function webAppUrlTest() {
  describe('WebAppUrl', () => {
    it('字符串原样返回', 0, () => {
      expect(webAppUrlOf('https://example.org/app')).assertEqual('https://example.org/app');
    });

    // 这条是这个函数存在的理由（[MainApp] 探针实测的形状）。
    it('对象形状取里面那层 url', 0, () => {
      const v: Object = JSON.parse(
        '{"@type":"webAppUrl","url":"https://example.org/app#tgWebAppData=x","require_same_origin":true}');
      expect(webAppUrlOf(v)).assertEqual('https://example.org/app#tgWebAppData=x');
    });

    it('缺失、空值、形状不对都给空串', 0, () => {
      expect(webAppUrlOf(undefined)).assertEqual('');
      expect(webAppUrlOf(null)).assertEqual('');
      expect(webAppUrlOf(JSON.parse('{"@type":"webAppUrl"}') as Object)).assertEqual('');
      expect(webAppUrlOf(JSON.parse('{"url":{"nested":1}}') as Object)).assertEqual('');
      expect(webAppUrlOf(42 as Object)).assertEqual('');
    });
  });
}
