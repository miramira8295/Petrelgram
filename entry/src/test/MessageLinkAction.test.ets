import { describe, expect, it } from '@ohos/hypium';
import {
  LINK_COMMAND, LINK_COPY, LINK_HASHTAG, LINK_NONE, LINK_REMOTE, LINK_USER,
  LinkAction, linkActionOf, linkTextHidesUrl
} from '../main/ets/util/messageLinkAction';

export default function messageLinkActionTest() {
  describe('messageLinkAction', () => {
    it('四种本地 scheme 各自解出载荷', 0, () => {
      const cmd: LinkAction = linkActionOf('tg-command:/start@mybot');
      expect(cmd.kind).assertEqual(LINK_COMMAND);
      expect(cmd.text).assertEqual('/start@mybot');

      const copy: LinkAction = linkActionOf('tg-copy:+8613800138000');
      expect(copy.kind).assertEqual(LINK_COPY);
      expect(copy.text).assertEqual('+8613800138000');

      const tag: LinkAction = linkActionOf('tg-hashtag:鸿蒙');
      expect(tag.kind).assertEqual(LINK_HASHTAG);
      expect(tag.text).assertEqual('鸿蒙');

      const user: LinkAction = linkActionOf('tg://user?id=777000');
      expect(user.kind).assertEqual(LINK_USER);
      expect(user.userId).assertEqual(777000);
    });

    it('载荷为空时收成 NONE，不发空命令、不跳空话题', 0, () => {
      expect(linkActionOf('tg-command:').kind).assertEqual(LINK_NONE);
      expect(linkActionOf('tg-copy:').kind).assertEqual(LINK_NONE);
      expect(linkActionOf('tg-hashtag:').kind).assertEqual(LINK_NONE);
      expect(linkActionOf('tg://user?id=').kind).assertEqual(LINK_NONE);
    });

    it('用户 id 解析失败不能漏成 NaN', 0, () => {
      // Number('abc') 是 NaN，NaN > 0 为假——若不显式拦住，会静默什么都不做，
      // 且这条链接再也不会被当成普通网页处理。
      expect(linkActionOf('tg://user?id=abc').kind).assertEqual(LINK_NONE);
      expect(linkActionOf('tg://user?id=0').kind).assertEqual(LINK_NONE);
      expect(linkActionOf('tg://user?id=-5').kind).assertEqual(LINK_NONE);
      // 合法的大 id 要放行。
      expect(linkActionOf('tg://user?id=5000000000').userId).assertEqual(5000000000);
    });

    it('前缀必须锚在开头——正文里含前缀的普通网址不该被劫走', 0, () => {
      expect(linkActionOf('https://x.com/?q=tg-copy:123').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('https://example.com/tg-command:/start').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('  tg-copy:123').kind).assertEqual(LINK_REMOTE);
    });

    it('其余一律远程，交给页面走解析链', 0, () => {
      expect(linkActionOf('https://t.me/durov').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('https://t.me/+abcdef').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('tg://resolve?domain=durov').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('https://github.com/x').kind).assertEqual(LINK_REMOTE);
      expect(linkActionOf('').kind).assertEqual(LINK_REMOTE);
    });

    it('本地 scheme 从不返回远程档，远程也从不带载荷', 0, () => {
      const locals: string[] = ['tg-command:/a', 'tg-copy:1', 'tg-hashtag:x', 'tg://user?id=9'];
      for (const u of locals) {
        expect(linkActionOf(u).kind === LINK_REMOTE).assertFalse();
      }
      const remote: LinkAction = linkActionOf('https://t.me/x');
      expect(remote.text).assertEqual('');
      expect(remote.userId).assertEqual(0);
    });

    // issue #169 第 6 条：点普通链接不再先弹「打开 / 复制」，直接打开（复制与外部打开在
    // 内置浏览器的「⋯」里）。只有「显示的文字不是它指向的网址」时才先确认——那是
    // 防钓鱼的那一道，官方客户端也这么做。
    it('显示文字就是网址本身时不算藏链接', 0, () => {
      expect(linkTextHidesUrl('https://telegra.ph/abc', 'https://telegra.ph/abc')).assertFalse();
      // TDLib 的 url 实体原样是正文里那段字，可能不带协议、带 www、结尾斜杠、大小写不同
      expect(linkTextHidesUrl('telegra.ph/abc', 'https://telegra.ph/abc')).assertFalse();
      expect(linkTextHidesUrl('www.Example.com/', 'http://example.com')).assertFalse();
    });

    it('文字和实际网址不一致就算藏链接，要先确认', 0, () => {
      expect(linkTextHidesUrl('点这里领红包', 'https://evil.example/x')).assertTrue();
      expect(linkTextHidesUrl('https://bank.com', 'https://bank.com.evil.example')).assertTrue();
      expect(linkTextHidesUrl('', 'https://example.com')).assertTrue();
    });
  });
}
