import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest, TdError } from '../main/ets/tdkit/TdTypes';
import { allPermissions, permissionsToTd, GroupPermissions } from '../main/ets/util/chatPermissions';
import { effectiveSendPermissions, anySendPermission, sendPermissionForType,
  canAttach, firstDeniedPermission, sharedSendPermissions } from '../main/ets/util/sendPermissions';
import { readSendPermissions, requireSendPermissions, requireForwardPermissions,
  SendPermissionError } from '../main/ets/store/SendPermissionApi';

const MEMBER: TdObject = { '@type': 'chatMemberStatusMember' };
function status(type: string, member: boolean = true): TdObject {
  return { '@type': type, 'is_member': member };
}
function restricted(value: GroupPermissions): TdObject {
  return { '@type': 'chatMemberStatusRestricted', 'is_member': true, 'permissions': permissionsToTd(value) };
}
class PermissionPort {
  value: GroupPermissions = allPermissions(true);
  member: TdObject = MEMBER;
  channel: boolean = false;
  groupType: string = 'chatTypeSupergroup';
  fail: boolean = false;
  types: string[] = ['messagePhoto', 'messageAnimation'];
  requests: TdRequest[] = [];
  send = async (request: TdRequest): Promise<TdObject> => {
    this.requests.push(request);
    if (this.fail) { throw new TdError(-1, 'request timeout'); }
    if (request['@type'] === 'getChat') {
      return { '@type': 'chat', 'permissions': permissionsToTd(this.value), 'type': {
        '@type': this.groupType, 'is_channel': this.channel, 'supergroup_id': 5, 'basic_group_id': 6 } as TdObject };
    }
    if (request['@type'] === 'getMessages') {
      return { '@type': 'messages', 'messages': this.types.map((type: string): TdObject =>
        ({ '@type': 'message', 'content': { '@type': type } as TdObject })) };
    }
    return { '@type': 'supergroup', 'status': this.member };
  };
}
async function denied(action: () => Promise<void>): Promise<boolean> {
  try { await action(); return false; } catch (error) { return error instanceof SendPermissionError; }
}

export default function sendPermissionsTest() {
  describe('SendPermissions', () => {
    it('禁图片不影响视频和基本消息', 0, () => {
      const p = allPermissions(true); p.sendPhotos = false;
      const result = effectiveSendPermissions(permissionsToTd(p), MEMBER, false);
      expect(result.sendPhotos).assertFalse(); expect(result.sendVideos).assertTrue(); expect(result.sendMessages).assertTrue();
    });
    it('个人限制与群默认权限取交集', 0, () => {
      const group = allPermissions(true); group.sendPhotos = false;
      const own = allPermissions(true); own.sendVoiceNotes = false;
      const result = effectiveSendPermissions(permissionsToTd(group), restricted(own), false);
      expect(result.sendPhotos).assertFalse(); expect(result.sendVoiceNotes).assertFalse(); expect(result.sendVideos).assertTrue();
    });
    it('群管理员不受默认禁发媒体限制', 0, () => {
      const result = effectiveSendPermissions(permissionsToTd(allPermissions(false)),
        status('chatMemberStatusAdministrator'), false);
      expect(result.sendPhotos).assertTrue();
    });
    it('频道管理员仍需发帖权限', 0, () => {
      const admin = status('chatMemberStatusAdministrator');
      expect(anySendPermission(effectiveSendPermissions(undefined, admin, true))).assertFalse();
      admin['rights'] = { 'can_post_messages': true } as TdObject;
      expect(effectiveSendPermissions(undefined, admin, true).sendVideos).assertTrue();
    });
    it('群主不受默认权限限制', 0, () => {
      expect(effectiveSendPermissions(permissionsToTd(allPermissions(false)),
        status('chatMemberStatusCreator'), true).sendPhotos).assertTrue();
    });
    it('封禁与不在群内的受限身份不能发送', 0, () => {
      expect(anySendPermission(effectiveSendPermissions(undefined, status('chatMemberStatusBanned'), false))).assertFalse();
      expect(anySendPermission(effectiveSendPermissions(undefined, status('chatMemberStatusRestricted', false), false))).assertFalse();
    });
    it('频道订阅者不能发送媒体', 0, () => {
      expect(anySendPermission(effectiveSendPermissions(undefined, MEMBER, true))).assertFalse();
    });
    it('只允许媒体时仍有可发送能力', 0, () => {
      const value = allPermissions(false); value.sendPhotos = true;
      expect(anySendPermission(effectiveSendPermissions(permissionsToTd(value), MEMBER, false))).assertTrue();
    });
    it('每类媒体按自身权限映射而非一把总开关', 0, () => {
      expect(sendPermissionForType('inputMessagePhoto')).assertEqual('sendPhotos');
      expect(sendPermissionForType('messageVideo')).assertEqual('sendVideos');
      expect(sendPermissionForType('inlineQueryResultAudio')).assertEqual('sendAudios');
      expect(sendPermissionForType('inputMessageDocument')).assertEqual('sendDocuments');
      expect(sendPermissionForType('inputMessageVoiceNote')).assertEqual('sendVoiceNotes');
      expect(sendPermissionForType('inputMessageVideoNote')).assertEqual('sendVideoNotes');
      expect(sendPermissionForType('inputMessagePoll')).assertEqual('sendPolls');
    });
    it('贴纸GIF骰子同属其他消息而普通表情属于文本', 0, () => {
      expect(sendPermissionForType('inputMessageSticker')).assertEqual('sendOtherMessages');
      expect(sendPermissionForType('inlineQueryResultAnimation')).assertEqual('sendOtherMessages');
      expect(sendPermissionForType('inputMessageDice')).assertEqual('sendOtherMessages');
      expect(sendPermissionForType('inputMessageText')).assertEqual('sendMessages');
      expect(sendPermissionForType('inputMessageContact')).assertEqual('sendMessages');
    });
    it('图片视频至少允许一个时才开放相册入口', 0, () => {
      const value = allPermissions(false);
      expect(canAttach(value, 'media')).assertFalse(); value.sendVideos = true;
      expect(canAttach(value, 'media')).assertTrue(); expect(canAttach(value, 'file')).assertFalse();
    });
    it('混选发现任意禁止项即整体拒绝', 0, () => {
      const value = allPermissions(true); value.sendPhotos = false;
      expect(firstDeniedPermission(value, ['sendOtherMessages', 'sendPhotos'])).assertEqual('sendPhotos');
    });
    it('外部分享按实际类型区分GIF与图片', 0, () => {
      expect(sharedSendPermissions({ caption: '配文', media: [
        { kind: 'image', uri: '/a.gif', text: '', title: '', sourceUri: '' }, { kind: 'video', uri: '/b.mp4', text: '', title: '', sourceUri: '' },
        { kind: 'audio', uri: '/c.mp3', text: '', title: '', sourceUri: '' }, { kind: 'file', uri: '/d.pdf', text: '', title: '', sourceUri: '' }
      ] }).join(',')).assertEqual('sendOtherMessages,sendVideos,sendAudios,sendDocuments');
    });
    it('提交时重新读取撤销后的权限', 0, async () => {
      const port = new PermissionPort();
      await requireSendPermissions(port.send, 10, ['sendPhotos']);
      port.value.sendPhotos = false;
      expect(await denied(() => requireSendPermissions(port.send, 10, ['sendPhotos']))).assertTrue();
      await requireSendPermissions(port.send, 10, ['sendVideos']);
    });
    it('基本群与超级群读取正确身份接口', 0, async () => {
      const port = new PermissionPort(); await readSendPermissions(port.send, 10);
      expect(port.requests[1]['supergroup_id']).assertEqual(5);
      port.groupType = 'chatTypeBasicGroup'; await readSendPermissions(port.send, 10);
      expect(port.requests[3]['@type']).assertEqual('getBasicGroup'); expect(port.requests[3]['basic_group_id']).assertEqual(6);
    });
    it('私聊不套用群默认媒体权限', 0, async () => {
      const port = new PermissionPort(); port.groupType = 'chatTypePrivate'; port.value = allPermissions(false);
      expect((await readSendPermissions(port.send, 10)).sendPhotos).assertTrue(); expect(port.requests.length).assertEqual(1);
    });
    it('预检失败不误报为消息发送结果未知', 0, async () => {
      const port = new PermissionPort(); port.fail = true;
      try { await requireSendPermissions(port.send, 10, ['sendPhotos']); expect(false).assertTrue(); }
      catch (error) { expect((error as TdError).code).assertEqual(403); }
    });
    it('转发混合内容先检查源消息类型', 0, async () => {
      const port = new PermissionPort(); port.value.sendOtherMessages = false;
      expect(await denied(() => requireForwardPermissions(port.send, 10, 20, [1, 2]))).assertTrue();
      expect(port.requests[0]['chat_id']).assertEqual(20);
    });
    it('源消息缺失不能把不完整转发预检当作通过', 0, async () => {
      const port = new PermissionPort(); port.types = [];
      expect(await denied(() => requireForwardPermissions(port.send, 10, 20, [1]))).assertTrue();
    });
  });
}
