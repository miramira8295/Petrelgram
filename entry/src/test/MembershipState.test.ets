import { describe, expect, it } from '@ohos/hypium';
import {
  MEMBERSHIP_BLOCKED, MEMBERSHIP_CHECKING, MEMBERSHIP_JOINABLE, MEMBERSHIP_READONLY,
  MEMBERSHIP_WRITABLE, MemberStatusInput,
  membershipLosesComposer, membershipStateOf
} from '../main/ets/util/membershipState';

function input(
  statusType: string, isMember: boolean, isChannel: boolean, canPost: boolean
): MemberStatusInput {
  return { statusType: statusType, isMember: isMember,
    isChannel: isChannel, canPostMessages: canPost,
    // 两个新入参默认放行，老用例的语义因此一个字都不变。
    chatCanSendBasic: true, restrictedCanSendBasic: true };
}

// 带权限的入参：锁群、以及被禁言的成员。
function withPerm(
  statusType: string, isMember: boolean, chatCanSend: boolean, selfCanSend: boolean
): MemberStatusInput {
  return { statusType: statusType, isMember: isMember, isChannel: false,
    canPostMessages: false,
    chatCanSendBasic: chatCanSend, restrictedCanSendBasic: selfCanSend };
}

export default function membershipStateTest() {
  describe('membershipState', () => {
    it('离开了就显示加入', 0, () => {
      expect(membershipStateOf(input('chatMemberStatusLeft', false, false, false)))
        .assertEqual(MEMBERSHIP_JOINABLE);
      // 频道也一样。
      expect(membershipStateOf(input('chatMemberStatusLeft', false, true, false)))
        .assertEqual(MEMBERSHIP_JOINABLE);
    });

    it('被限制但仍在群里 → 照样能发言', 0, () => {
      // 限制的是权限细项，不是在场与否。判反的话，一个只是被禁发图片的人
      // 会看到"加入"按钮。
      expect(membershipStateOf(input('chatMemberStatusRestricted', true, false, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
      // 被限制且已经不在群里，才是加入。
      expect(membershipStateOf(input('chatMemberStatusRestricted', false, false, false)))
        .assertEqual(MEMBERSHIP_JOINABLE);
    });

    it('被封禁 → 挡住', 0, () => {
      expect(membershipStateOf(input('chatMemberStatusBanned', false, false, false)))
        .assertEqual(MEMBERSHIP_BLOCKED);
      // 封禁压过一切，即便 isMember 为真。
      expect(membershipStateOf(input('chatMemberStatusBanned', true, true, true)))
        .assertEqual(MEMBERSHIP_BLOCKED);
    });

    it('频道订阅者只读，超级群普通成员照常发言', 0, () => {
      expect(membershipStateOf(input('chatMemberStatusMember', true, true, false)))
        .assertEqual(MEMBERSHIP_READONLY);
      // 同一个 status，非频道就是可写——这条差别只由 isChannel 决定。
      expect(membershipStateOf(input('chatMemberStatusMember', true, false, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    it('频道管理员要看有没有发帖权', 0, () => {
      expect(membershipStateOf(input('chatMemberStatusAdministrator', true, true, true)))
        .assertEqual(MEMBERSHIP_WRITABLE);
      // 是管理员不等于能发帖。
      expect(membershipStateOf(input('chatMemberStatusAdministrator', true, true, false)))
        .assertEqual(MEMBERSHIP_READONLY);
      // 群里的管理员不受这条约束。
      expect(membershipStateOf(input('chatMemberStatusAdministrator', true, false, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    it('创建者、私聊、拿不到状态一律放行', 0, () => {
      expect(membershipStateOf(input('chatMemberStatusCreator', true, true, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
      expect(membershipStateOf(input('', false, false, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
      // 兜底选 writable 而不是 blocked：状态查不到时藏起输入框，用户就没救了。
      expect(membershipStateOf(input('chatMemberStatusSomethingNew', false, true, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    it('只有 writable 保留输入区', 0, () => {
      expect(membershipLosesComposer(MEMBERSHIP_WRITABLE)).assertFalse();
      expect(membershipLosesComposer(MEMBERSHIP_JOINABLE)).assertTrue();
      expect(membershipLosesComposer(MEMBERSHIP_BLOCKED)).assertTrue();
      expect(membershipLosesComposer(MEMBERSHIP_READONLY)).assertTrue();
    });

    // 「不能聊天但是显示聊天输入框」（用户 2026-09-09，从首页进的会话）。
    //
    // 判据原来只看 ChatMemberStatus，**从来没看过 chat.permissions**——于是
    // "只有管理员能发言"的锁群里，普通成员状态就是 chatMemberStatusMember，
    // 一路判成 writable，输入框照出，打完字发送才被 TDLib 驳回
    // （真机日志：Need administrator rights in the channel chat）。
    it('锁群里的普通成员是只读', 0, () => {
      expect(membershipStateOf(withPerm('chatMemberStatusMember', true, false, true)))
        .assertEqual(MEMBERSHIP_READONLY);
    });

    it('普通群的普通成员照旧能发言', 0, () => {
      expect(membershipStateOf(withPerm('chatMemberStatusMember', true, true, true)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    // 创建者和管理员不受群默认权限约束——锁群本来就是给他们用的。
    it('锁群不挡创建者和管理员', 0, () => {
      expect(membershipStateOf(withPerm('chatMemberStatusCreator', true, false, true)))
        .assertEqual(MEMBERSHIP_WRITABLE);
      expect(membershipStateOf(withPerm('chatMemberStatusAdministrator', true, false, true)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    // 被禁言的成员看自己那份 permissions，不看群默认的：群里别人能说话，
    // 不代表他能。原来这一支无条件返回 writable。
    it('被禁言的成员是只读', 0, () => {
      expect(membershipStateOf(withPerm('chatMemberStatusRestricted', true, true, false)))
        .assertEqual(MEMBERSHIP_READONLY);
    });

    it('只被限制了别的项、仍能发文字的成员照旧能发言', 0, () => {
      expect(membershipStateOf(withPerm('chatMemberStatusRestricted', true, true, true)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });

    // 兜底方向不变：权限字段缺失时按放行处理（调用方传 true），
    // 状态查不到时把输入框藏起来用户就彻底没救了。
    it('拿不到状态时仍然放行', 0, () => {
      expect(membershipStateOf(withPerm('', false, false, false)))
        .assertEqual(MEMBERSHIP_WRITABLE);
    });
  });
}
