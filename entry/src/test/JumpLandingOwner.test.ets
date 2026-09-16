import { describe, it, expect } from '@ohos/hypium';
import {
  JUMP_LANDING_SETTLE_MS, NO_JUMP_LANDING, chunkPrependAllowed, jumpLandingDeadline,
  jumpLandingHolds
} from '../main/ets/util/jumpLandingOwner';
import { JUMP_LANDING_GRACE_MS } from '../main/ets/util/chatPageTuning';

export default function jumpLandingOwnerTest() {
  describe('jumpLandingOwner', () => {
    // 落地的那一刻起，位置归这次跳转所有：贴底、追加补位、再取一页历史、裁剪
    // 都得让路。用户报的"第一次像是过去了又被抓去别的地方"就是这几位在抢。
    it('holds_the_viewport_right_after_the_landing', 0, () => {
      const deadline: number = jumpLandingDeadline(1000);
      expect(jumpLandingHolds(deadline, 1000)).assertTrue();
      expect(jumpLandingHolds(deadline, 1000 + JUMP_LANDING_SETTLE_MS - 1)).assertTrue();
    });

    // 到点必须真的放手：这道闸只保护落地，不是"跳转之后永远不跟随新消息"。
    it('lets_go_at_the_deadline', 0, () => {
      const deadline: number = jumpLandingDeadline(1000);
      expect(jumpLandingHolds(deadline, 1000 + JUMP_LANDING_SETTLE_MS)).assertFalse();
      expect(jumpLandingHolds(deadline, 5000)).assertFalse();
    });

    // 没跳过就不该有人让路（字段初值 0），否则进会话首屏的落点全被挡掉。
    it('never_holds_without_a_landing', 0, () => {
      expect(jumpLandingHolds(NO_JUMP_LANDING, 0)).assertFalse();
      expect(jumpLandingHolds(NO_JUMP_LANDING, 1000)).assertFalse();
    });

    // 窗口要盖住 landPendingJump 自己的两次动作：80ms 的补发滚动、150ms 的
    // 落地闪烁取矩形。盖不住就等于没修。
    it('covers_the_landing_reissue_and_the_flash', 0, () => {
      expect(JUMP_LANDING_SETTLE_MS >= 150).assertTrue();
    });

    // ── 头插分批：落地期间必须整份发布 ──────────────────────────────
    // 真机 [JumpLand] 证实的真因：目标行还扣在没发布的头部里（idx=-1），
    // 按完整快照算出的下标滚过去就是另一条消息。
    it('does_not_chunk_while_a_jump_is_pending_or_landing', 0, () => {
      expect(chunkPrependAllowed(true, true, false)).assertFalse();
      expect(chunkPrependAllowed(true, false, true)).assertFalse();
    });

    // 平时照常分批（翻历史时每批不超过 cachedCount，少重建节点）。
    it('chunks_as_usual_outside_a_landing', 0, () => {
      expect(chunkPrependAllowed(true, false, false)).assertTrue();
    });

    // 宿主自己就不允许时（页面不可见 / 首屏分级揭示期），跳转不能把它打开。
    it('never_overrides_the_hosts_own_veto', 0, () => {
      expect(chunkPrependAllowed(false, false, false)).assertFalse();
    });

    // 但要比返回栈那道 900ms 宽限短：那道管的是"用户算不算自己滑回来了"，
    // 这道管的是"谁能动列表"。把定位按住 900ms 会把新消息跟随也拖住。
    it('is_shorter_than_the_return_stack_grace', 0, () => {
      expect(JUMP_LANDING_SETTLE_MS < JUMP_LANDING_GRACE_MS).assertTrue();
    });
  });
}
