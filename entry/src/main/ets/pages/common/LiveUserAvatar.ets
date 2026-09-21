import { AvatarView } from '../chatlist/AvatarView';
import { getFileService } from '../../tdkit/Globals';
import {
  senderAvatarFor, senderChannelKey, subscribeSenderAvatar
} from '../../util/senderAvatarChannel';
import {
  avatarFilePathFor, subscribeAvatarFile
} from '../../util/avatarFileChannel';

// 「给一个用户 id，把他的真头像画出来」的最小组件（issue #211 第 2 条：
// 会话详情 @ 弹窗不显示真实头像）。
//
// 【为什么需要它】@ 候选人来自 searchChatMembers，**未必在当前会话里发过言**，
// 所以 senderAvatarChannel 里不一定有他——那条通道只由 MessageStore 为消息
// 发送者和评论者填充。原来 SuggestionPanel 索性写死 `avatarPath: ''`，于是
// 永远只画首字母。
//
// 【为什么不复用 MessageBubble 里的 LiveSenderAvatar】那个是文件内私有 struct，
// 而且绑着消息行的复用钩子（aboutToRecycle/aboutToReuse）与动态头像分支。
// 这里要的只是"订阅 + 缺就取"，把那套搬过来等于把气泡的复杂度带进一个弹窗。
//
// 【为什么订两条通道】两边各管一段，缺一不可：
//   senderAvatarChannel（按 userId）—— MessageStore 下发送者/评论者头像时发，
//     这个人在本会话发过言就走这条。
//   avatarFileChannel（按 file id）—— FileService 下完任意头像文件时发，
//     我们自己 prefetchAvatar 拉来的那张只有这条。
// 【三级取值】通道现值 → FileService 已下完的路径 → 触发一次预取后等推送。
// 前两级是同步的，所以已经看过的人第一帧就有图，不闪。
//
// 【必须退订】不退订会让箭头函数一直持有本组件实例（官方状态管理 FAQ 点过这个
// 泄漏），而这个面板每敲一个字符就可能整列重建。
@ComponentV2
export struct LiveUserAvatar {
  @Require @Param userId: number;
  @Param initials: string = '?';
  @Param avatarSize: number = 32;
  // 头像文件 id。0 表示这个人没有头像或还不知道，此时只画首字母、不发请求。
  @Param avatarFileId: number = 0;

  @Local private path: string = '';
  private unsubSender: (() => void) | null = null;
  private unsubFile: (() => void) | null = null;

  private channelKey(): string {
    return senderChannelKey(this.userId, true);
  }

  aboutToAppear(): void {
    const key: string = this.channelKey();
    this.path = senderAvatarFor(key);
    if (this.path === '' && this.avatarFileId > 0) {
      this.path = avatarFilePathFor(this.avatarFileId);
    }
    if (this.path === '' && this.avatarFileId > 0) {
      // 已经下完过就直接拿；都没有才真正发请求（prefetchAvatar 自己去重）。
      const files = getFileService();
      this.path = files.avatarPathOf(this.avatarFileId);
      if (this.path === '') {
        files.prefetchAvatar(this.avatarFileId);
      }
    }
    this.unsubSender = subscribeSenderAvatar(key, (next: string): void => {
      this.path = next;
    });
    if (this.avatarFileId > 0) {
      this.unsubFile = subscribeAvatarFile(this.avatarFileId, (next: string): void => {
        this.path = next;
      });
    }
  }

  aboutToDisappear(): void {
    if (this.unsubSender !== null) {
      this.unsubSender();
      this.unsubSender = null;
    }
    if (this.unsubFile !== null) {
      this.unsubFile();
      this.unsubFile = null;
    }
  }

  build() {
    AvatarView({
      avatarPath: this.path,
      initials: this.initials,
      colorSeed: this.userId,
      avatarSize: this.avatarSize
    });
  }
}
