import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import { dispatchScannedQr, QrScanHost } from '../main/ets/util/qrScanFlow';
import { fetchChatQrLink, validInviteQr, ChatQrClient } from '../main/ets/util/chatQrLink';

class ScanHost implements QrScanHost {
  alive: boolean = true;
  approve: boolean = false;
  kind: string = 'internalLinkTypePublicChat';
  requests: TdRequest[] = [];
  opened: string = '';
  invited: string = '';
  confirmations: number = 0;
  duringRequest: () => void = (): void => {};
  duringConfirm: () => void = (): void => {};
  current = (): boolean => this.alive;
  send = async (request: TdRequest): Promise<TdObject> => {
    this.requests.push(request);
    this.duringRequest();
    return { '@type': request['@type'] === 'getInternalLinkType' ? this.kind : 'session' };
  };
  confirmLogin = async (): Promise<boolean> => {
    this.confirmations++;
    this.duringConfirm();
    return this.approve;
  };
  openLink = (link: string): void => { this.opened = link; };
  openInvite = (link: string): void => { this.invited = link; };
}
class ChatQrFake implements ChatQrClient {
  requests: TdRequest[] = [];
  isSuper: boolean = true;
  publicName: string = '';
  status: string = 'chatMemberStatusCreator';
  canInvite: boolean = false;
  hasPrimary: boolean = true;
  invite: TdObject = { '@type': 'chatInviteLink' };
  duringRequest: () => void = (): void => {};
  constructor() { this.invite['invite_link'] = 'https://t.me/+valid'; }
  send = async (request: TdRequest, timeout?: number): Promise<TdObject> => {
    expect(timeout).assertEqual(15000);
    this.requests.push(request);
    this.duringRequest();
    if (request['@type'] === 'getChat') {
      const type: TdObject = { '@type': this.isSuper ? 'chatTypeSupergroup' : 'chatTypeBasicGroup' };
      type[this.isSuper ? 'supergroup_id' : 'basic_group_id'] = 99;
      const chat: TdObject = { '@type': 'chat' }; chat['type'] = type; return chat;
    }
    if (request['@type'] === 'getSupergroup' || request['@type'] === 'getBasicGroup') {
      const usernames: TdObject = { '@type': 'usernames' };
      usernames['active_usernames'] = this.publicName !== '' ? [this.publicName] : [];
      const rights: TdObject = { '@type': 'chatAdministratorRights' }; rights['can_invite_users'] = this.canInvite;
      const status: TdObject = { '@type': this.status }; status['rights'] = rights;
      const group: TdObject = { '@type': this.isSuper ? 'supergroup' : 'basicGroup' };
      group['usernames'] = usernames; group['status'] = status; return group;
    }
    if (request['@type'] === 'getChatInviteLink') { return this.invite; }
    const info: TdObject = { '@type': this.isSuper ? 'supergroupFullInfo' : 'basicGroupFullInfo' };
    if (this.hasPrimary) { info['invite_link'] = this.invite; }
    return info;
  };
}
async function qrRejected(operation: () => Promise<Object>): Promise<boolean> {
  try { await operation(); return false; } catch (_) { return true; }
}
export default function qrWorkflowTest() {
  describe('QrWorkflow', () => {
    it('普通网页与空二维码不发TD请求', 0, async (): Promise<void> => {
      const host = new ScanHost();
      expect(await dispatchScannedQr('  ', host)).assertEqual('empty');
      expect(await dispatchScannedQr('https://example.com/login', host)).assertEqual('unsupported');
      expect(host.requests.length).assertEqual(0);
    });
    it('联系人二维码只打开链接，不调用登录接口', 0, async (): Promise<void> => {
      const host = new ScanHost();
      expect(await dispatchScannedQr(' https://t.me/person ', host)).assertEqual('opened');
      expect(host.opened).assertEqual('https://t.me/person');
      expect(host.confirmations).assertEqual(0);
      expect(host.requests.length).assertEqual(1);
    });
    it('无用户名的用户token交给已有联系人路由', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeUserToken';
      expect(await dispatchScannedQr('tg://contact?token=test', host)).assertEqual('opened');
      expect(host.opened).assertEqual('tg://contact?token=test');
    });
    it('群邀请码先展示资料预览，不发送加入或登录请求', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeChatInvite';
      expect(await dispatchScannedQr('https://t.me/+invite', host)).assertEqual('opened');
      expect(host.invited).assertEqual('https://t.me/+invite');
      expect(host.opened).assertEqual('');
      expect(host.requests.length).assertEqual(1);
    });
    it('登录二维码拒绝授权不调用confirm', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeQrCodeAuthentication';
      expect(await dispatchScannedQr('tg://login?token=test', host)).assertEqual('cancelled');
      expect(host.confirmations).assertEqual(1);
      expect(host.requests.length).assertEqual(1);
    });
    it('登录二维码明确批准才确认，使用原始token链接', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeQrCodeAuthentication'; host.approve = true;
      expect(await dispatchScannedQr('tg://login?token=test', host)).assertEqual('loggedIn');
      expect(host.requests.length).assertEqual(2);
      expect(host.requests[1]['@type']).assertEqual('confirmQrCodeAuthentication');
      expect(host.requests[1]['link']).assertEqual('tg://login?token=test');
    });
    it('分类请求回来时页面已销毁或账号已换，不能弹确认', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeQrCodeAuthentication';
      host.duringRequest = (): void => { host.alive = false; };
      expect(await dispatchScannedQr('tg://login?token=test', host)).assertEqual('cancelled');
      expect(host.confirmations).assertEqual(0);
    });
    it('确认期间换账号，即使点批准也不提交', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeQrCodeAuthentication'; host.approve = true;
      host.duringConfirm = (): void => { host.alive = false; };
      expect(await dispatchScannedQr('tg://login?token=test', host)).assertEqual('cancelled');
      expect(host.requests.length).assertEqual(1);
    });
    it('取消流程不会启动新的分类请求', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.alive = false;
      expect(await dispatchScannedQr('https://t.me/person', host)).assertEqual('cancelled');
      expect(host.requests.length).assertEqual(0);
    });
    it('未知深链及验证码不被当登录授权', 0, async (): Promise<void> => {
      const host = new ScanHost(); host.kind = 'internalLinkTypeAuthenticationCode';
      expect(await dispatchScannedQr('tg://login?code=123', host)).assertEqual('unsupported');
      host.kind = 'internalLinkTypeUnknownDeepLink';
      expect(await dispatchScannedQr('tg://unknown', host)).assertEqual('unsupported');
      expect(host.confirmations).assertEqual(0);
    });
    it('公开群无需管理权限即可生成公开用户名码', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.publicName = 'public_group'; client.status = 'chatMemberStatusMember';
      const link = await fetchChatQrLink(client, -99);
      expect(link.url).assertEqual('https://telegram.me/public_group');
      expect(link.expiresIn).assertEqual(0);
      expect(client.requests.length).assertEqual(2);
    });
    it('私密群普通成员无权限时不获取或创建邀请链接', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.status = 'chatMemberStatusMember';
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
      expect(client.requests.length).assertEqual(2);
    });
    it('管理员需要can_invite_users，不能仅凭管理员身份', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.status = 'chatMemberStatusAdministrator';
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
      client.canInvite = true;
      expect((await fetchChatQrLink(client, -99)).url).assertEqual('https://t.me/+valid');
    });
    it('基础群走基础群接口，群主取得并复查已有邀请', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.isSuper = false;
      expect((await fetchChatQrLink(client, -99)).url).assertEqual('https://t.me/+valid');
      expect(client.requests[1]['@type']).assertEqual('getBasicGroup');
      expect(client.requests[2]['@type']).assertEqual('getBasicGroupFullInfo');
      expect(client.requests[3]['@type']).assertEqual('getChatInviteLink');
      expect(client.requests[3]['chat_id']).assertEqual(-99);
    });
    it('无现成邀请时不隐式创建新邀请', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.hasPrimary = false;
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
      expect(client.requests.length).assertEqual(3);
    });
    it('撤销的邀请不能生成二维码', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.invite['is_revoked'] = true;
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
    });
    it('过期邀请不能生成二维码', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.invite['expiration_date'] = 1;
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
    });
    it('人数限制已用尽的邀请不能生成二维码', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); client.invite['member_limit'] = 3; client.invite['member_count'] = 3;
      expect(await qrRejected(() => fetchChatQrLink(client, -99))).assertTrue();
    });
    it('限时与审核邀请保留原链接和有效期', 0, (): void => {
      const invite: TdObject = { '@type': 'chatInviteLink' };
      invite['invite_link'] = 'https://t.me/+approval'; invite['expiration_date'] = 110;
      invite['creates_join_request'] = true;
      const result = validInviteQr(invite, 100);
      expect(result.url).assertEqual('https://t.me/+approval'); expect(result.expiresIn).assertEqual(10);
    });
    it('关闭群二维码期间旧应答停止后续请求', 0, async (): Promise<void> => {
      const client = new ChatQrFake(); let active = true;
      client.duringRequest = (): void => { active = false; };
      expect(await qrRejected(() => fetchChatQrLink(client, -99, (): boolean => active))).assertTrue();
      expect(client.requests.length).assertEqual(1);
    });
  });
}
