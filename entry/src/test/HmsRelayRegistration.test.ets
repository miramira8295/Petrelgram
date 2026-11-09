import { describe, expect, it } from '@ohos/hypium';
import {
  buildHmsRegisterBody, needsHmsRegistration, parseHmsRegisterResponse
} from '../main/ets/services/HmsRelayRegistration';

export default function hmsRelayRegistrationTest() {
  describe('hmsRelayRegistration', () => {
    it('注册请求体只带 subKey 与 pushToken', 0, () => {
      const body = buildHmsRegisterBody('SUB', 'TOKEN');
      expect(body.subKey).assertEqual('SUB');
      expect(body.pushToken).assertEqual('TOKEN');
    });

    it('正常响应解析出三元组', 0, () => {
      const r = parseHmsRegisterResponse(
        '{"endpoint":"https://x/webpush/a","p256dh":"BP","auth":"AU","secret":"S"}');
      expect(r.error).assertEqual('');
      expect(r.endpoint).assertEqual('https://x/webpush/a');
      expect(r.p256dh).assertEqual('BP');
      expect(r.auth).assertEqual('AU');
    });

    it('缺任何一项都算失败', 0, () => {
      // 少一项就注册不成推送，但错误会推迟到 Telegram 那步才暴露，且报的是
      // 一个和真实原因无关的参数错误。在这里就挡住。
      expect(parseHmsRegisterResponse('{"endpoint":"e","p256dh":"p"}').error.length > 0).assertTrue();
      expect(parseHmsRegisterResponse('{"p256dh":"p","auth":"a"}').error.length > 0).assertTrue();
      expect(parseHmsRegisterResponse('{"endpoint":"e","auth":"a"}').error.length > 0).assertTrue();
    });

    it('服务端返回的 error 字段优先', 0, () => {
      const r = parseHmsRegisterResponse('{"error":"本中转未启用华为推送通道"}');
      expect(r.error).assertEqual('本中转未启用华为推送通道');
      expect(r.endpoint).assertEqual('');
    });

    it('响应不是 JSON 时不抛', 0, () => {
      // 中转前面挂着反代，502 页面是 HTML；JSON.parse 抛出去会把整个登录回调
      // 带崩，而这条链路是可选功能。
      const r = parseHmsRegisterResponse('<html>502 Bad Gateway</html>');
      expect(r.error).assertEqual('invalid json');
    });

    it('没有 token 时不注册', 0, () => {
      expect(needsHmsRegistration('', '', '')).assertFalse();
      expect(needsHmsRegistration('OLD', '', 'https://x/e')).assertFalse();
    });

    it('从没注册过就要注册', 0, () => {
      expect(needsHmsRegistration('', 'T', '')).assertTrue();
    });

    it('token 变了就要重注册', 0, () => {
      // 重装应用、系统轮换 token 都会变。不重注册的话中转还往旧 token 推，
      // 华为侧静默丢弃，现象是"某天开始收不到了"。
      expect(needsHmsRegistration('OLD', 'NEW', 'https://x/e')).assertTrue();
    });

    it('token 没变就跳过', 0, () => {
      // 每次启动都注册是白白一次网络往返，还会把中转的注册限流桶打满
      // （每 IP 有窗口配额，同一个 Wi-Fi 下多台设备会互相挤掉）。
      expect(needsHmsRegistration('SAME', 'SAME', 'https://x/e')).assertFalse();
    });

    it('token 没变但 endpoint 丢了要补注册', 0, () => {
      // 清过数据、或者上一次落盘只成功了一半。endpoint 是真正起作用的那个，
      // 它空着就等于没注册。
      expect(needsHmsRegistration('SAME', 'SAME', '')).assertTrue();
    });
  });
}
