import { TdObject, TdRequest } from '../tdkit/TdTypes';

// 「加联系人」三个请求的请求体，按随包的 TDLib 1.8.65 schema 拼。
//
// 【为什么要单独一个文件】2026-10-30 之前发的是旧形状，三条路一条都对不上：
//
//   · addContact —— 把 user_id 塞在 contact 里，contact 还带 @type:'contact'
//     和 vcard。1.8.65 的声明是：
//         addContact user_id:int53 contact:importedContact share_phone_number:Bool
//     ——user_id 是**顶层**参数，contact 换成了 importedContact（没有 user_id，
//     也没有 vcard）。
//   · importContacts —— contacts 同样从 vector<contact> 换成了
//     vector<importedContact>。
//   · searchUserByPhoneNumber —— 少传 only_local，声明里它是必填。
//
// 随包的 libtdjson.so 里直接读得到 "1.8.65" 和 "importedContact"，so 不会接受
// 旧形状。用户看到的是「无法添加联系人，请重试」，而错误其实出在请求本身——
// 这一步根本发不出去。
//
// 请求体集中在这里，单测逐字段钉住形状：改 TDLib 版本时，形状漂了会在本地
// 测试里立刻炸，而不是等用户再报一次「加不上」。

// importedContact：号码 + 名 + 姓 + 备注。
//
// note 是 formattedText，声明里没有默认值，所以必须给（空文本即可）。保留
// @type 与全代码库其它嵌套对象一致——TDLib 自己的 to_json 也会带上它。
export function importedContact(phoneNumber: string, firstName: string, lastName: string): TdObject {
  const note: TdObject = { '@type': 'formattedText' };
  note['text'] = '';
  const contact: TdObject = { '@type': 'importedContact' };
  contact['phone_number'] = phoneNumber;
  contact['first_name'] = firstName;
  contact['last_name'] = lastName;
  contact['note'] = note;
  return contact;
}

// 按号码查人。only_local=false 表示连服务器一起查——只要我们只查本地库，
// 没聊过的人一律查不到，这三步兜底的第一步就废了。
export function searchUserByPhoneNumberRequest(phoneNumber: string): TdRequest {
  const request: TdRequest = { '@type': 'searchUserByPhoneNumber' };
  request['phone_number'] = phoneNumber;
  request['only_local'] = false;
  return request;
}

// 拿着已知的 user_id 把人加成联系人。
export function addContactRequest(userId: number, phoneNumber: string, firstName: string,
  lastName: string): TdRequest {
  const request: TdRequest = { '@type': 'addContact' };
  request['user_id'] = userId;
  request['contact'] = importedContact(phoneNumber, firstName, lastName);
  request['share_phone_number'] = false;
  return request;
}

// 把号码交给服务器导入（官方客户端分享名片走的同一条路）。
export function importContactsRequest(phoneNumber: string, firstName: string,
  lastName: string): TdRequest {
  const request: TdRequest = { '@type': 'importContacts' };
  request['contacts'] = [importedContact(phoneNumber, firstName, lastName)];
  return request;
}
