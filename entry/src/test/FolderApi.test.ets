import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  chatIsInChatList, derivedFolderIconName, emptyFolder, folderDataFromTd,
  parseOptionInteger, toTdFolder
} from '../main/ets/store/FolderApi';

export default function folderApiTest() {
  describe('FolderApi', () => {
    it('td_folder_roundtrip_preserves_rules', 0, () => {
      const folder = emptyFolder();
      folder.name = '工作';
      folder.iconName = 'Work';
      folder.colorId = 2;
      folder.includedChatIds = [10, 20];
      folder.excludedChatIds = [30];
      folder.includeGroups = true;
      folder.excludeMuted = true;
      const td: TdObject = toTdFolder(folder);
      const parsed = folderDataFromTd(td, 9);
      expect(parsed.id).assertEqual(9);
      expect(parsed.name).assertEqual('工作');
      expect(parsed.iconName).assertEqual('Work');
      expect(parsed.colorId).assertEqual(2);
      expect(parsed.includedChatIds.join(',')).assertEqual('10,20');
      expect(parsed.excludedChatIds.join(',')).assertEqual('30');
      expect(parsed.includeGroups).assertTrue();
      expect(parsed.excludeMuted).assertTrue();
    });
    it('preserves_custom_emoji_name_metadata', 0, () => {
      const folder = emptyFolder();
      folder.name = '朋友';
      const entity: TdObject = { '@type': 'textEntity' };
      entity['offset'] = 0; entity['length'] = 1;
      entity['type'] = { '@type': 'textEntityTypeCustomEmoji', 'custom_emoji_id': '123' } as TdObject;
      folder.nameEntities = [entity];
      folder.animateCustomEmoji = true;
      const parsed = folderDataFromTd(toTdFolder(folder));
      expect(parsed.nameEntities.length).assertEqual(1);
      expect(parsed.animateCustomEmoji).assertTrue();
    });
    it('accepts_only_chats_with_a_chat_list_position', 0, () => {
      const listed: TdObject = { '@type': 'chat' };
      listed['positions'] = [{ '@type': 'chatPosition' } as TdObject];
      expect(chatIsInChatList(listed)).assertTrue();
      const unlisted: TdObject = { '@type': 'chat' };
      unlisted['positions'] = [];
      expect(chatIsInChatList(unlisted)).assertFalse();
      const missing: TdObject = { '@type': 'chat' };
      expect(chatIsInChatList(missing)).assertFalse();
    });

    // TDLib 把 int64 编码成 JSON 字符串。以前直接当 number 用，
    // Number.isFinite("10") 恒为 false，于是永远退回兜底值 —— 表现是
    // 文件夹上限被写死成 10，Premium 账号的 20 从未生效。
    it('parses_int64_option_delivered_as_string', 0, () => {
      expect(parseOptionInteger('20', 10)).assertEqual(20);
      expect(parseOptionInteger(' 20 ', 10)).assertEqual(20);
    });

    it('accepts_plain_number_option', 0, () => {
      expect(parseOptionInteger(200, 10)).assertEqual(200);
    });

    it('falls_back_on_missing_or_invalid_option', 0, () => {
      expect(parseOptionInteger(undefined, 10)).assertEqual(10);
      expect(parseOptionInteger('', 10)).assertEqual(10);
      expect(parseOptionInteger('abc', 10)).assertEqual(10);
      expect(parseOptionInteger(0, 10)).assertEqual(10);
      expect(parseOptionInteger(-5, 10)).assertEqual(10);
    });

    // 默认图标的推导规则照搬 TDLib DialogFilter::get_default_icon_name。
    // 之前这 10 个官方图标名没进映射表（Cat/Crown/Flower/Mask/Light/Like/
    // Note/All/Setup/Airplane），用到它们的文件夹在列表里全部掉成通用方框。
    it('keeps_explicit_icon_name', 0, () => {
      const folder = emptyFolder();
      folder.iconName = 'Crown';
      expect(derivedFolderIconName(folder)).assertEqual('Crown');
    });

    it('derives_custom_when_specific_chats_are_listed', 0, () => {
      const folder = emptyFolder();
      folder.includeGroups = true;
      folder.includedChatIds = [123];
      expect(derivedFolderIconName(folder)).assertEqual('Custom');
    });

    it('derives_by_included_chat_types', 0, () => {
      const priv = emptyFolder();
      priv.includeContacts = true;
      expect(derivedFolderIconName(priv)).assertEqual('Private');
      const groups = emptyFolder();
      groups.includeGroups = true;
      expect(derivedFolderIconName(groups)).assertEqual('Groups');
      const channels = emptyFolder();
      channels.includeChannels = true;
      expect(derivedFolderIconName(channels)).assertEqual('Channels');
      const bots = emptyFolder();
      bots.includeBots = true;
      expect(derivedFolderIconName(bots)).assertEqual('Bots');
    });

    it('derives_by_exclusions_when_types_are_mixed', 0, () => {
      const unread = emptyFolder();
      unread.includeGroups = true;
      unread.includeChannels = true;
      unread.excludeRead = true;
      expect(derivedFolderIconName(unread)).assertEqual('Unread');
      const unmuted = emptyFolder();
      unmuted.includeGroups = true;
      unmuted.includeChannels = true;
      unmuted.excludeMuted = true;
      expect(derivedFolderIconName(unmuted)).assertEqual('Unmuted');
    });

    it('falls_back_to_custom_for_empty_folder', 0, () => {
      expect(derivedFolderIconName(emptyFolder())).assertEqual('Custom');
    });
  });
}
