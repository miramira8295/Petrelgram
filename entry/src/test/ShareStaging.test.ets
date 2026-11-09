import { describe, it, expect } from '@ohos/hypium';
import { SharedItem, SharedKind, SharedPayload } from '../main/ets/util/sharedContent';
import {
  SharePlan, captionForDirectSend, hasDirectSend, planShare
} from '../main/ets/util/shareStaging';
import { PENDING_MEDIA_MAX } from '../main/ets/util/pendingMedia';

// 分享落到会话之后每样东西怎么处理。核心判据：**说明文字只能出现在一个地方**
// （否则用户会看到它发两遍），以及**超上限的张数必须能被调用方看见**。

function media(kind: SharedKind, uri: string): SharedItem {
  return { kind: kind, uri: uri, text: '', title: '', sourceUri: uri };
}

function payload(caption: string, items: SharedItem[]): SharedPayload {
  return { caption: caption, media: items };
}

export default function shareStagingTest() {
  describe('shareStaging', () => {

    it('图片进暂存区，说明进草稿', 0, (): void => {
      const plan: SharePlan = planShare(payload('配文', [media('image', '/a.jpg')]));
      expect(plan.staged.length).assertEqual(1);
      expect(plan.staged[0].path).assertEqual('/a.jpg');
      expect(plan.staged[0].isVideo).assertFalse();
      expect(plan.draft).assertEqual('配文');
      expect(hasDirectSend(plan)).assertFalse();
    });

    it('视频也进暂存区，并标记为视频', 0, (): void => {
      const plan: SharePlan = planShare(payload('', [media('video', '/a.mp4')]));
      expect(plan.staged[0].isVideo).assertTrue();
    });

    it('文档直接发，说明不留在草稿里（否则会发两遍）', 0, (): void => {
      const plan: SharePlan = planShare(payload('说明', [media('file', '/a.pdf')]));
      expect(plan.documents.length).assertEqual(1);
      expect(plan.draft).assertEqual('');
      expect(captionForDirectSend(payload('说明', []), plan)).assertEqual('说明');
      expect(hasDirectSend(plan)).assertTrue();
    });

    it('音频走音频通道', 0, (): void => {
      const plan: SharePlan = planShare(payload('', [media('audio', '/a.mp3')]));
      expect(plan.audios.length).assertEqual(1);
      expect(plan.documents.length).assertEqual(0);
    });

    it('图片 + 文档同时来：说明跟图片走，文档不再重复带配文', 0, (): void => {
      const plan: SharePlan = planShare(
        payload('一段话', [media('image', '/a.jpg'), media('file', '/b.pdf')]));
      expect(plan.draft).assertEqual('一段话');
      expect(plan.documents.length).assertEqual(1);
      expect(captionForDirectSend(payload('一段话', []), plan)).assertEqual('');
    });

    it('只有文字时进草稿，什么都不发', 0, (): void => {
      const plan: SharePlan = planShare(payload('只有文字', []));
      expect(plan.draft).assertEqual('只有文字');
      expect(plan.staged.length).assertEqual(0);
      expect(hasDirectSend(plan)).assertFalse();
    });

    it('超过暂存上限的张数被记下来，不是悄悄丢掉', 0, (): void => {
      const items: SharedItem[] = [];
      for (let i = 0; i < PENDING_MEDIA_MAX + 3; i++) {
        items.push(media('image', `/p${i}.jpg`));
      }
      const plan: SharePlan = planShare(payload('', items));
      expect(plan.staged.length).assertEqual(PENDING_MEDIA_MAX);
      expect(plan.dropped).assertEqual(3);
    });

    it('输入框里已经有暂存图时，剩余名额跟着缩小', 0, (): void => {
      const items: SharedItem[] = [media('image', '/a.jpg'), media('image', '/b.jpg')];
      const plan: SharePlan = planShare(payload('', items), PENDING_MEDIA_MAX - 1);
      expect(plan.staged.length).assertEqual(1);
      expect(plan.dropped).assertEqual(1);
    });

    it('暂存区已满时图片全部落空，但文档照发', 0, (): void => {
      const plan: SharePlan = planShare(
        payload('', [media('image', '/a.jpg'), media('file', '/b.pdf')]), PENDING_MEDIA_MAX);
      expect(plan.staged.length).assertEqual(0);
      expect(plan.dropped).assertEqual(1);
      expect(plan.documents.length).assertEqual(1);
    });

    it('空载荷得到空计划', 0, (): void => {
      const plan: SharePlan = planShare(payload('', []));
      expect(plan.staged.length).assertEqual(0);
      expect(plan.draft).assertEqual('');
      expect(plan.dropped).assertEqual(0);
    });
  });
}
