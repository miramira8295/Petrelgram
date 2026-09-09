import { describe, it, expect } from '@ohos/hypium';
import { NotificationBody, notificationBody } from '../main/ets/util/notificationText';

// 通知正文的拼装。这一组存在的理由是一次隐私缺陷：分类的「消息预览」开关
// 关掉之后，服务端推送会裁掉内容，而**应用自己拼的本地通知**从来没查过它，
// 锁屏上照样能看到完整正文和发送者名字（2026-09-08 代码扫描发现）。

const TITLE: string = '新消息';
const BODY: string = '你收到一条新消息';

export default function notificationTextTest() {
  describe('notificationText', () => {

    it('允许预览：私聊显示正文本身', 0, (): void => {
      const out: NotificationBody = notificationBody('张三', '', '在吗', true, TITLE, BODY);
      expect(out.title).assertEqual('张三');
      expect(out.text).assertEqual('在吗');
    });

    it('允许预览：群里带发送者前缀', 0, (): void => {
      const out: NotificationBody = notificationBody('某群', '李四', '在吗', true, TITLE, BODY);
      expect(out.text).assertEqual('李四: 在吗');
    });

    it('允许预览但正文为空（贴纸等）时用中性文案兜底', 0, (): void => {
      const out: NotificationBody = notificationBody('张三', '', '', true, TITLE, BODY);
      expect(out.text).assertEqual(BODY);
    });

    it('允许预览、正文为空且在群里：前缀仍然保留', 0, (): void => {
      const out: NotificationBody = notificationBody('某群', '李四', '', true, TITLE, BODY);
      expect(out.text).assertEqual(`李四: ${BODY}`);
    });

    // ---- 关掉预览：正文和标题都不许泄露 ----

    it('关掉预览：正文不含原文', 0, (): void => {
      const out: NotificationBody = notificationBody('张三', '', '银行卡密码是 1234', false, TITLE, BODY);
      expect(out.text).assertEqual(BODY);
      expect(out.text.indexOf('1234') < 0).assertTrue();
    });

    it('关掉预览：发送者名字也要藏', 0, (): void => {
      // 只藏正文、留着"李四:"等于告诉旁人"李四给你发消息了"——用户关这个
      // 开关就是不想让人看见。
      const out: NotificationBody = notificationBody('某群', '李四', '在吗', false, TITLE, BODY);
      expect(out.text.indexOf('李四') < 0).assertTrue();
    });

    it('关掉预览：会话名也要藏（会话名本身就是内容）', 0, (): void => {
      const out: NotificationBody = notificationBody('前女友', '', '在吗', false, TITLE, BODY);
      expect(out.title).assertEqual(TITLE);
      expect(out.title.indexOf('前女友') < 0).assertTrue();
    });

    it('关掉预览：空正文也走同一支，不会漏出别的东西', 0, (): void => {
      const out: NotificationBody = notificationBody('张三', '李四', '', false, TITLE, BODY);
      expect(out.title).assertEqual(TITLE);
      expect(out.text).assertEqual(BODY);
    });
  });
}
