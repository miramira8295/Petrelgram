import { describe, it, expect } from '@ohos/hypium';
import {
  PENDING_TRANSLATION_MAX, PendingTranslation, TRANSLATION_STAGGER_CAP_MS,
  TRANSLATION_STAGGER_MS, queueTranslation, translationLandDelay, trimPendingTranslations
} from '../main/ets/util/deferredTranslation';

// 滑动期间攒下的译文。用户 2026-09-09 实测：「现在边滑动，列表边跳」——
// 译文让气泡变高就是改布局，滑动中改必然跳。

function t(id: number, text: string = 'x'): PendingTranslation {
  return { messageId: id, lang: 'zh', text: text };
}

function ids(list: PendingTranslation[]): string {
  return list.map((p: PendingTranslation): number => p.messageId).join(',');
}

export default function deferredTranslationTest() {
  describe('deferredTranslation', () => {

    it('按到达顺序排队', 0, (): void => {
      expect(ids(queueTranslation(queueTranslation([], t(1)), t(2)))).assertEqual('1,2');
    });

    it('同一条消息只留最后一份——否则停稳那刻会连着改两次布局', 0, (): void => {
      const q: PendingTranslation[] = queueTranslation(queueTranslation([], t(1, '旧')), t(1, '新'));
      expect(q.length).assertEqual(1);
      expect(q[0].text).assertEqual('新');
    });

    it('覆盖时挪到队尾，不占用原来的位置', 0, (): void => {
      let q: PendingTranslation[] = queueTranslation([], t(1));
      q = queueTranslation(q, t(2));
      q = queueTranslation(q, t(1, '新'));
      expect(ids(q)).assertEqual('2,1');
    });

    it('不修改入参数组', 0, (): void => {
      const before: PendingTranslation[] = [t(1)];
      queueTranslation(before, t(2));
      expect(before.length).assertEqual(1);
    });

    it('超过上限丢最旧的——最旧那条多半已经滑出视野', 0, (): void => {
      const q: PendingTranslation[] = [t(1), t(2), t(3), t(4)];
      expect(ids(trimPendingTranslations(q, 2))).assertEqual('3,4');
    });

    it('没超上限时原样返回', 0, (): void => {
      expect(trimPendingTranslations([t(1)], 5).length).assertEqual(1);
    });

    it('上限为 0 时清空', 0, (): void => {
      expect(trimPendingTranslations([t(1)], 0).length).assertEqual(0);
    });

    it('默认上限是个正数', 0, (): void => {
      expect(PENDING_TRANSLATION_MAX > 0).assertTrue();
    });

    // ---- 落地节奏 ----
    //
    // 一次全落 = 所有气泡同一帧一起变高，观感和"一起闪"没区别（用户实测）。

    it('第一条立刻落', 0, (): void => {
      expect(translationLandDelay(0)).assertEqual(0);
    });

    it('后面的依次错开', 0, (): void => {
      expect(translationLandDelay(1)).assertEqual(TRANSLATION_STAGGER_MS);
      expect(translationLandDelay(3)).assertEqual(TRANSLATION_STAGGER_MS * 3);
    });

    it('超过总时长上限的一起落——它们几乎必然在视野之外', 0, (): void => {
      const far: number = translationLandDelay(999);
      expect(far).assertEqual(TRANSLATION_STAGGER_CAP_MS);
    });

    it('上限那一档是连续的，不会先超再回落', 0, (): void => {
      const n: number = Math.ceil(TRANSLATION_STAGGER_CAP_MS / TRANSLATION_STAGGER_MS);
      expect(translationLandDelay(n) <= TRANSLATION_STAGGER_CAP_MS).assertTrue();
      expect(translationLandDelay(n + 1)).assertEqual(TRANSLATION_STAGGER_CAP_MS);
    });

    it('负下标当成第一条', 0, (): void => {
      expect(translationLandDelay(-1)).assertEqual(0);
    });
  });
}
