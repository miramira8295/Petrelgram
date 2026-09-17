import { TdObject, TdRequest } from '../tdkit/TdTypes';

// 动态头像（chatPhoto 里的 MP4）相关的纯判据。顶栏和群聊气泡左侧共用。
//
// TDLib 的形状（td_api.tl）：
// - chatPhoto.animation：animatedChatPhoto，最大 1280×1280，可空；
// - chatPhoto.small_animation：160×160，可空，「即使 animation 存在」；
// - 会话列表/消息发送者手里的 chatPhotoInfo / profilePhoto 只带 has_animation 标志，
//   真正的文件要再取一次完整资料（getUserFullInfo 等）。
// 真机实测同一个头像大份 1.9MB、小份 72KB。38vp 的头像只该用小份。

function animationFileId(anim: TdObject | null | undefined): number {
  if (anim === undefined || anim === null) {
    return 0;
  }
  const file = anim['file'] as TdObject | null | undefined;
  if (file === undefined || file === null) {
    return 0;
  }
  return (file['id'] as number | undefined) ?? 0;
}

// 取哪一份的文件 id；0 = 没有动画。preferSmall 时小份缺席就退回大份。
export function pickPhotoAnimationFileId(photo: TdObject | null | undefined, preferSmall: boolean): number {
  if (photo === undefined || photo === null) {
    return 0;
  }
  const big: number = animationFileId(photo['animation'] as TdObject | null | undefined);
  if (!preferSmall) {
    return big;
  }
  const small: number = animationFileId(photo['small_animation'] as TdObject | null | undefined);
  return small > 0 ? small : big;
}

// userFullInfo 有三处头像：photo、personal_photo（我给联系人设的）、public_photo（主头像
// 被隐私设置挡住时对外的那张），非空的那张就是 user.profile_photo 对应的头像。顺序沿用原顶栏。
// 群/超级群的完整资料只有 photo。
export function photoFromFullInfo(full: TdObject): TdObject | undefined {
  const photo = full['photo'] as TdObject | null | undefined;
  if (photo !== undefined && photo !== null) {
    return photo;
  }
  const personal = full['personal_photo'] as TdObject | null | undefined;
  if (personal !== undefined && personal !== null) {
    return personal;
  }
  const publicPhoto = full['public_photo'] as TdObject | null | undefined;
  return publicPhoto !== undefined && publicPhoto !== null ? publicPhoto : undefined;
}

// 按会话类型拼完整资料请求；密聊等没有独立头像的类型返回 null。
export function fullInfoRequestForChatType(type: TdObject | null | undefined): TdRequest | null {
  if (type === undefined || type === null) {
    return null;
  }
  const typeName: string = (type['@type'] as string | undefined) ?? '';
  if (typeName === 'chatTypePrivate') {
    const req: TdRequest = { '@type': 'getUserFullInfo' };
    req['user_id'] = (type['user_id'] as number | undefined) ?? 0;
    return req;
  }
  if (typeName === 'chatTypeSupergroup') {
    const req: TdRequest = { '@type': 'getSupergroupFullInfo' };
    req['supergroup_id'] = (type['supergroup_id'] as number | undefined) ?? 0;
    return req;
  }
  if (typeName === 'chatTypeBasicGroup') {
    const req: TdRequest = { '@type': 'getBasicGroupFullInfo' };
    req['basic_group_id'] = (type['basic_group_id'] as number | undefined) ?? 0;
    return req;
  }
  return null;
}

// profilePhoto / chatPhotoInfo 上的标志。
export function photoHasAnimation(photo: TdObject | null | undefined): boolean {
  if (photo === undefined || photo === null) {
    return false;
  }
  return (photo['has_animation'] as boolean | undefined) === true;
}
