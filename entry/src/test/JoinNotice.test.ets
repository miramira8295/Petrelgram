import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  JoinNoticeInput, isRealClientJoinNotice, CLIENT_JOIN_NOTICE_ID, clientJoinNoticeRaw,
  hasRealClientJoinNotice, tagClientJoinNoticeGroup
} from '../main/ets/util/joinNotice';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageEntry, buildMessageEntry } from '../main/ets/store/MessageEntry';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import { resetStrings } from '../main/ets/util/strings';

function msg(
  contentType: string, isOutgoing: boolean, placeholderLabel: string, systemType: string
): JoinNoticeInput {
  return { contentType: contentType, isOutgoing: isOutgoing,
    placeholderLabel: placeholderLabel, systemType: systemType };
}

// 下面三个 helper 与 MediaEntryKind.test.ets / CollapseAlbumsKey.test.ets 同一
// 套路：起一个空的 TdClient + UserStore，让 buildMessageEntry 走真实路径造行，
// 而不是手搓 MessageEntry 字面量（字段一漏，判定就测不到真东西）。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function usersOf(): UserStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  const users: UserStore = new UserStore(client);
  client.start();
  return users;
}

function textEntry(id: number, users: UserStore): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = 'hi';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['date'] = 1000;
  message['content'] = content;
  return buildMessageEntry(message, users);
}

// 服务端下发的那条真的入群系统消息（本地合成行等的就是它）。
function serverJoinEntry(id: number, outgoing: boolean, users: UserStore): MessageEntry {
  const content: TdObject = { '@type': 'messageChatJoinByLink' };
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = outgoing;
  message['date'] = 1700000100;
  message['content'] = content;
  return buildMessageEntry(message, users);
}

// 宿主单测里 str() 原样返回 key，所以文案比较那两支等价于比对 key 本身。
export default function joinNoticeTest() {
  describe('joinNotice', () => {
    it('必须是自己发出的系统消息', 0, () => {
      // 别人入群的提示不算——否则群里每来一个人都会压掉本地提示。
      expect(isRealClientJoinNotice(msg('system', false, 'cp_joined_group', ''))).assertFalse();
      // 普通文本消息即便文案撞上也不算。
      expect(isRealClientJoinNotice(msg('text', true, 'cp_joined_group', ''))).assertFalse();
    });

    it('systemType 是可靠的那两个判据', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByLink'))).assertTrue();
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByRequest'))).assertTrue();
    });

    it('文案判据：群与频道各一条', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_group', ''))).assertTrue();
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_channel', ''))).assertTrue();
    });

    it('文案对不上且 systemType 也不匹配时为假', 0, () => {
      expect(isRealClientJoinNotice(msg('system', true, '别的系统提示', 'messageChatChangeTitle')))
        .assertFalse();
      expect(isRealClientJoinNotice(msg('system', true, '', ''))).assertFalse();
    });

    it('四个判据是或的关系，任一命中即可', 0, () => {
      // 文案空但 systemType 命中。
      expect(isRealClientJoinNotice(msg('system', true, '', 'messageChatJoinByLink'))).assertTrue();
      // systemType 是别的但文案命中。
      expect(isRealClientJoinNotice(msg('system', true, 'cp_joined_group', 'messageChatAddMembers')))
        .assertTrue();
    });
  });

  // ── B3 下沉的三个纯函数（原 ChatPage.clientJoinNoticeEntry /
  //    groupsWithClientJoinNotice 的构造与打标部分）──────────────────────
  describe('clientJoinNoticeRaw', () => {
    beforeEach((): void => { resetStrings(); });

    it('哨兵 id 是 -1，绝不能改成 0', 0, (): void => {
      const raw: TdObject = clientJoinNoticeRaw(7, 1700000000, false);
      // 0 是"没有消息"的自然默认值，一堆按 id 取默认值的地方会跟这条本地
      // 合成行撞上；负数则不可能等于任何真实 message id，查找与动作匹配都
      // 无从命中。tagClientJoinNoticeGroup 也靠它认出末组。
      expect(raw['id'] as number).assertEqual(CLIENT_JOIN_NOTICE_ID);
      expect((raw['id'] as number) === 0).assertFalse();
      expect((raw['id'] as number) < 0).assertTrue();
    });

    it('必须自己发出、date 是秒', 0, (): void => {
      const raw: TdObject = clientJoinNoticeRaw(7, 1700000000, false);
      // is_outgoing 掉了这条行会画到左边，isRealClientJoinNotice 也认不出
      // 真身来顶替它（那道判据第一件事就是 contentType==='system' && isOutgoing）。
      expect(raw['is_outgoing'] as boolean).assertTrue();
      expect(raw['chat_id'] as number).assertEqual(7);
      // 与 TDLib 的 date 同单位：传毫秒会把日期分隔线扔到几万年后。
      expect(raw['date'] as number).assertEqual(1700000000);
    });

    it('频道与群走不同的 content 分支', 0, (): void => {
      const channel: TdObject = clientJoinNoticeRaw(7, 1700000000, true)['content'] as TdObject;
      expect(channel['@type'] as string).assertEqual('messageCustomServiceAction');
      // 频道分支没有 systemType 可依（messageCustomServiceAction 不在那两个
      // 判据里），全靠这句文案跟 isRealClientJoinNotice 的 cp_joined_channel
      // 对上——改文案 key 要两边一起改。宿主单测里 str() 原样返回 key。
      expect(channel['text'] as string).assertEqual('cp_joined_channel');
      const group: TdObject = clientJoinNoticeRaw(7, 1700000000, false)['content'] as TdObject;
      expect(group['@type'] as string).assertEqual('messageChatJoinByLink');
    });
  });

  describe('tagClientJoinNoticeGroup', () => {
    beforeEach((): void => { resetStrings(); });

    it('末组换成固定 key 并清空 memberIds', 0, (): void => {
      const users: UserStore = usersOf();
      const list: MessageEntry[] = [
        textEntry(900001, users),
        buildMessageEntry(clientJoinNoticeRaw(7, 1700000000, false), users)
      ];
      const groups: AlbumGroup[] = collapseAlbums(list);
      tagClientJoinNoticeGroup(groups, 7, 1700000000);
      const notice: AlbumGroup = groups[groups.length - 1];
      // key 格式逐字：它是这一行的身份。collapseAlbums 给的 key 里带
      // mutableSig，每次快照都会变一次，行会被销毁重建。
      expect(notice.key).assertEqual('client_join_7_1700000000');
      // memberIds 留着 -1 就等于告诉选择/回复/播放位去找一条不存在的消息。
      expect(notice.memberIds.length).assertEqual(0);
    });

    it('只动末组，前面的真消息一行都不许改', 0, (): void => {
      const users: UserStore = usersOf();
      const list: MessageEntry[] = [
        textEntry(900001, users),
        buildMessageEntry(clientJoinNoticeRaw(7, 1700000000, false), users)
      ];
      const groups: AlbumGroup[] = collapseAlbums(list);
      const keyBefore: string = groups[0].key;
      tagClientJoinNoticeGroup(groups, 7, 1700000000);
      expect(groups[0].key).assertEqual(keyBefore);
      expect(groups[0].memberIds.length).assertEqual(1);
      expect(groups[0].memberIds[0]).assertEqual(900001);
    });

    it('末组不是合成行时什么都不做，空数组不抛', 0, (): void => {
      const users: UserStore = usersOf();
      const groups: AlbumGroup[] = collapseAlbums([textEntry(900001, users)]);
      const keyBefore: string = groups[0].key;
      // 本地提示不显示时页面照样会走到这里（groups 直接来自 collapseAlbums）。
      tagClientJoinNoticeGroup(groups, 7, 1700000000);
      expect(groups[0].key).assertEqual(keyBefore);
      expect(groups[0].memberIds[0]).assertEqual(900001);
      const empty: AlbumGroup[] = [];
      tagClientJoinNoticeGroup(empty, 7, 1700000000);
      expect(empty.length).assertEqual(0);
    });
  });

  describe('hasRealClientJoinNotice', () => {
    beforeEach((): void => { resetStrings(); });

    it('服务端把真的入群消息下发下来就该认出', 0, (): void => {
      const users: UserStore = usersOf();
      expect(hasRealClientJoinNotice([
        textEntry(900001, users), serverJoinEntry(900002, true, users)
      ])).assertTrue();
    });

    it('空表、纯文本、别人入群都不算', 0, (): void => {
      const users: UserStore = usersOf();
      expect(hasRealClientJoinNotice([])).assertFalse();
      expect(hasRealClientJoinNotice([textEntry(900001, users)])).assertFalse();
      // 别人通过链接进群：is_outgoing 为假。拿它顶掉"你加入了本群"的话，
      // 群里每来一个人本地提示就消失一次。
      expect(hasRealClientJoinNotice([serverJoinEntry(900002, false, users)])).assertFalse();
    });

    it('本地合成行自己也满足判定——所以只能喂 store 的 list', 0, (): void => {
      const users: UserStore = usersOf();
      const synthetic: MessageEntry =
        buildMessageEntry(clientJoinNoticeRaw(7, 1700000000, false), users);
      // 这条不是"期望的行为"，是把一处既有脆弱记在案：本地合成行与真身形状
      // 一模一样。今天安全只因为判定跑在 store 的 list 上，而合成行只 push
      // 进 displayList 副本；谁哪天把 displayList 传进来，本地提示会自我抵消。
      expect(hasRealClientJoinNotice([synthetic])).assertTrue();
    });
  });
}
