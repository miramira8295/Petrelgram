import { describe, it, expect } from '@ohos/hypium';
import {
  addContactRequest, importContactsRequest, importedContact, searchUserByPhoneNumberRequest
} from '../main/ets/util/contactAddRequest';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 回归：2026-10-30「无法添加联系人」的根因是请求形状对不上随包的 TDLib 1.8.65
// （addContact 少顶层 user_id、contact 还是旧的 contact 类型、search 少 only_local）。
// 这里逐字段钉住，形状再漂就本地炸。
export default function contactAddRequestTest() {
  describe('contactAddRequest', () => {
    it('importedContact：号码/名/姓 + 必填的 note，没有 user_id 和 vcard', 0, (): void => {
      const contact = importedContact('8613800000000', 'Ada', 'Lovelace');
      expect(contact['@type'] as string).assertEqual('importedContact');
      expect(contact['phone_number'] as string).assertEqual('8613800000000');
      expect(contact['first_name'] as string).assertEqual('Ada');
      expect(contact['last_name'] as string).assertEqual('Lovelace');
      expect(contact['user_id'] === undefined).assertTrue();
      expect(contact['vcard'] === undefined).assertTrue();
      const note = contact['note'] as TdObject;
      expect(note['@type'] as string).assertEqual('formattedText');
      expect(note['text'] as string).assertEqual('');
    });

    it('importedContact：姓可以空，note 必须在', 0, (): void => {
      const contact = importedContact('8613800000000', 'Ada', '');
      expect(contact['last_name'] as string).assertEqual('');
      expect(contact['note'] !== undefined).assertTrue();
    });

    it('searchUserByPhoneNumber：必须带 only_local，且不是只查本地', 0, (): void => {
      const req = searchUserByPhoneNumberRequest('8613800000000');
      expect(req['@type']).assertEqual('searchUserByPhoneNumber');
      expect(req['phone_number'] as string).assertEqual('8613800000000');
      expect(req['only_local'] as boolean).assertFalse();
    });

    it('addContact：user_id 在顶层，contact 是 importedContact', 0, (): void => {
      const req = addContactRequest(42, '8613800000000', 'Ada', 'Lovelace');
      expect(req['@type']).assertEqual('addContact');
      expect(req['user_id'] as number).assertEqual(42);
      const contact = req['contact'] as TdObject;
      expect(contact['@type'] as string).assertEqual('importedContact');
      expect(contact['user_id'] === undefined).assertTrue();
      expect(req['share_phone_number'] as boolean).assertFalse();
    });

    it('importContacts：contacts 里是 importedContact，不是旧的 contact', 0, (): void => {
      const req = importContactsRequest('8613800000000', 'Ada', '');
      expect(req['@type']).assertEqual('importContacts');
      const contacts = req['contacts'] as TdObject[];
      expect(contacts.length).assertEqual(1);
      expect(contacts[0]['@type'] as string).assertEqual('importedContact');
      expect(contacts[0]['phone_number'] as string).assertEqual('8613800000000');
    });

    it('序列化后不出现旧字段 vcard', 0, (): void => {
      const json = JSON.stringify(addContactRequest(42, '8613800000000', 'Ada', ''));
      expect(json.includes('vcard')).assertFalse();
      expect(json.includes('user_id')).assertTrue();
    });
  });
}
