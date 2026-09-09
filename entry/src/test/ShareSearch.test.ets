import { describe, it, expect } from '@ohos/hypium';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import {
  ShareRow, localRows, matchesQuery, mergeRows, pinSavedFirst, rowFromEntry, unknownIds
} from '../main/ets/util/shareSearch';

// 「分享到…」的搜索。这一组存在的理由是一次真实缺陷：候选集原来是
// getChats('main')，而**归档会话在另一个桶里**，于是归档的人永远搜不到。
// 候选集必须来自 allEntries（不分桶、不受翻页影响）再叠远端结果。

function chat(id: number, title: string, date: number, last: string = ''): ChatEntry {
  return {
    id: id, revision: 0, title: title, isMuted: false, usesDefaultMute: true,
    unreadCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: last, lastMessageDate: date, lastMessageId: 0,
    lastSenderName: '', photoFileId: 0, avatarPath: '', initials: title.substring(0, 1),
    autoDeleteTime: 0, kind: 'private', isMarkedUnread: false,
    canDeleteOnlyForSelf: true, canDeleteForAllUsers: false,
    isSavedMessages: false, background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false
  };
}

function row(id: number, title: string, saved: boolean = false): ShareRow {
  return {
    chatId: id, title: title, subtitle: '', avatarPath: '', initials: '',
    isSavedMessages: saved
  };
}

function ids(rows: ShareRow[]): string {
  return rows.map((r: ShareRow): number => r.chatId).join(',');
}

export default function shareSearchTest() {
  describe('shareSearch', () => {

    it('匹配大小写不敏感', 0, (): void => {
      expect(matchesQuery('Linux DO', 'linux')).assertTrue();
      expect(matchesQuery('Linux DO', 'DO')).assertTrue();
    });

    it('匹配可以命中标题中段', 0, (): void => {
      expect(matchesQuery('北京快递站', '快递')).assertTrue();
    });

    it('空查询匹配一切', 0, (): void => {
      expect(matchesQuery('任意', '   ')).assertTrue();
    });

    it('不匹配就是不匹配', 0, (): void => {
      expect(matchesQuery('abc', 'xyz')).assertFalse();
    });

    it('本机结果按最后消息时间从新到旧', 0, (): void => {
      const entries: ChatEntry[] = [chat(1, 'a群', 100), chat(2, 'a频道', 999)];
      expect(ids(localRows(entries, 'a', 10))).assertEqual('2,1');
    });

    it('本机结果不改动传入数组的顺序', 0, (): void => {
      const entries: ChatEntry[] = [chat(1, 'a', 100), chat(2, 'a', 999)];
      localRows(entries, 'a', 10);
      expect(entries[0].id).assertEqual(1);
    });

    it('本机结果封顶', 0, (): void => {
      const entries: ChatEntry[] = [chat(1, 'a', 3), chat(2, 'a', 2), chat(3, 'a', 1)];
      expect(localRows(entries, 'a', 2).length).assertEqual(2);
    });

    it('占位条目不进结果', 0, (): void => {
      expect(localRows([chat(0, 'a', 9), chat(1, 'a', 1)], 'a', 10)).assertDeepEquals(
        [rowFromEntry(chat(1, 'a', 1))]);
    });

    it('副标题取最后一条消息', 0, (): void => {
      expect(rowFromEntry(chat(1, 'x', 1, '在吗')).subtitle).assertEqual('在吗');
    });

    it('收藏标记跟着带过来——界面靠它把标题换成"我的收藏"', 0, (): void => {
      const saved: ChatEntry = chat(9, '我自己的昵称', 1);
      saved.isSavedMessages = true;
      expect(rowFromEntry(saved).isSavedMessages).assertTrue();
      expect(rowFromEntry(chat(1, '别人', 1)).isSavedMessages).assertFalse();
    });

    it('合并：本机在前，远端补后', 0, (): void => {
      expect(ids(mergeRows([row(1, 'a')], [row(2, 'b')], 10))).assertEqual('1,2');
    });

    it('合并：同一个会话不出现两次', 0, (): void => {
      expect(ids(mergeRows([row(1, 'a')], [row(1, 'a'), row(2, 'b')], 10))).assertEqual('1,2');
    });

    it('合并：总数封顶', 0, (): void => {
      expect(mergeRows([row(1, 'a'), row(2, 'b')], [row(3, 'c')], 2).length).assertEqual(2);
    });

    it('合并：id 为 0 的行丢掉', 0, (): void => {
      expect(ids(mergeRows([row(0, 'x'), row(1, 'a')], [], 10))).assertEqual('1');
    });

    it('远端 id：本机已有的不再查详情', 0, (): void => {
      const known = (id: number): boolean => id === 1;
      expect(unknownIds([1, 2, 3], known).join(',')).assertEqual('2,3');
    });

    it('远端 id：保持服务器给的相关性顺序并去重', 0, (): void => {
      expect(unknownIds([5, 3, 5, 7], (): boolean => false).join(',')).assertEqual('5,3,7');
    });

    // ---- 收藏置顶 ----

    it('收藏被提到最前，其余顺序不变', 0, (): void => {
      const rows: ShareRow[] = [row(1, 'a'), row(2, 'b'), row(9, '我', true), row(3, 'c')];
      expect(ids(pinSavedFirst(rows))).assertEqual('9,1,2,3');
    });

    it('收藏已经在第一位时原样返回', 0, (): void => {
      const rows: ShareRow[] = [row(9, '我', true), row(1, 'a')];
      expect(ids(pinSavedFirst(rows))).assertEqual('9,1');
    });

    it('没有收藏时原样返回', 0, (): void => {
      expect(ids(pinSavedFirst([row(1, 'a'), row(2, 'b')]))).assertEqual('1,2');
    });

    it('空列表不炸', 0, (): void => {
      expect(pinSavedFirst([]).length).assertEqual(0);
    });

    it('置顶不复制——收藏只出现一次', 0, (): void => {
      const rows: ShareRow[] = [row(1, 'a'), row(9, '我', true)];
      expect(pinSavedFirst(rows).length).assertEqual(2);
    });

    it('不修改入参数组', 0, (): void => {
      const rows: ShareRow[] = [row(1, 'a'), row(9, '我', true)];
      pinSavedFirst(rows);
      expect(rows[0].chatId).assertEqual(1);
    });

    it('远端 id：0 不查', 0, (): void => {
      expect(unknownIds([0, 4], (): boolean => false).join(',')).assertEqual('4');
    });

    // ---- 候选集的闸（用户定的规则）----
    //
    // 「在任何文件夹里的都该搜得到；只躺在归档里、不属于任何文件夹的不该出现」。
    // 真实判据是 ChatStore.inNonArchiveList，这里用假的谓词把规则本身钉住。

    it('只在归档里的会话不出现在结果里', 0, (): void => {
      const entries: ChatEntry[] = [chat(1, '主列表的', 100), chat(2, '只在归档的', 200)];
      const eligible = (id: number): boolean => id !== 2;
      expect(ids(localRows(entries, '', 10, eligible))).assertEqual('1');
    });

    it('归档但同时在某个文件夹里的会话仍然出现', 0, (): void => {
      // 判据是"在非归档列表里"，不是"没被归档"——文件夹可以收录归档会话
      const entries: ChatEntry[] = [chat(7, '归档但在文件夹里', 100)];
      const eligible = (): boolean => true;
      expect(ids(localRows(entries, '', 10, eligible))).assertEqual('7');
    });

    it('闸在标题匹配之前生效——被排除的不会因为标题命中而漏进来', 0, (): void => {
      const entries: ChatEntry[] = [chat(1, '同名', 100), chat(2, '同名', 200)];
      expect(ids(localRows(entries, '同名', 10, (id: number): boolean => id === 1)))
        .assertEqual('1');
    });

    it('不传闸时全放行（默认参数）', 0, (): void => {
      expect(localRows([chat(1, 'a', 1), chat(2, 'a', 2)], 'a', 10).length).assertEqual(2);
    });
  });
}
