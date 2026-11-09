import { describe, it, expect } from '@ohos/hypium';
import { listKeyOf, chatListOf } from '../main/ets/store/ListKey';
import { TdObject } from '../main/ets/tdkit/TdTypes';

export default function listKeyTest() {
  describe('ListKey', () => {
    it('main', 0, () => {
      const cl: TdObject = { '@type': 'chatListMain' };
      expect(listKeyOf(cl)).assertEqual('main');
    });
    it('archive', 0, () => {
      const cl: TdObject = { '@type': 'chatListArchive' };
      expect(listKeyOf(cl)).assertEqual('archive');
    });
    it('folder', 0, () => {
      const cl: TdObject = { '@type': 'chatListFolder' }; cl['chat_folder_id'] = 7;
      expect(listKeyOf(cl)).assertEqual('folder:7');
    });
    it('unknown_empty', 0, () => {
      const cl: TdObject = { '@type': 'chatListWhatever' };
      expect(listKeyOf(cl)).assertEqual('');
    });
    it('roundtrip_folder', 0, () => {
      const cl = chatListOf('folder:9');
      expect(cl['@type']).assertEqual('chatListFolder');
      expect(cl['chat_folder_id'] as number).assertEqual(9);
    });
    it('build_archive', 0, () => {
      expect(chatListOf('archive')['@type']).assertEqual('chatListArchive');
    });
    it('build_main_default', 0, () => {
      expect(chatListOf('main')['@type']).assertEqual('chatListMain');
    });
  });
}
