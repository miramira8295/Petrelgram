import { describe, expect, it } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { loadBotCommands } from '../main/ets/store/InputSuggestions';
import { CommandSuggestionState } from '../main/ets/pages/chat/ComposerSuggestionState';
import { MessageStore } from '../main/ets/store/MessageStore';

class CommandBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  sent: TdObject[] = [];
  init(callback: (json: string) => void): void { this.receive = callback; }
  send(json: string): void { this.sent.push(JSON.parse(json) as TdObject); }
  reply(index: number, value: TdObject): void {
    value['@extra'] = this.sent[index]['@extra']; this.receive(JSON.stringify(value));
  }
  update(full: TdObject, id: number = 77): void {
    const update: TdObject = { '@type': 'updateSupergroupFullInfo' };
    update['supergroup_id'] = id; update['supergroup_full_info'] = full;
    this.receive(JSON.stringify(update));
  }
}
function chat(kind: string = 'chatTypeSupergroup', channel: boolean = false): TdObject {
  const type: TdObject = { '@type': kind };
  type['supergroup_id'] = 77; type['basic_group_id'] = 88; type['user_id'] = 10; type['is_channel'] = channel;
  const result: TdObject = { '@type': 'chat' }; result['type'] = type; return result;
}
function full(command: string = 'group'): TdObject {
  const result: TdObject = { '@type': 'supergroupFullInfo' };
  const entry: TdObject = { '@type': 'botCommand' }; entry['command'] = command; entry['description'] = 'Group description';
  const group: TdObject = { '@type': 'botCommands' }; group['bot_user_id'] = 10; group['commands'] = [entry];
  result['bot_commands'] = command === '' ? [] : [group]; return result;
}
function user(name: string = 'group_bot', avatarFileId: number = 42): TdObject {
  const names: TdObject = { '@type': 'usernames' }; names['active_usernames'] = name === '' ? [] : [name];
  const small: TdObject = { '@type': 'file', 'id': avatarFileId };
  const photo: TdObject = { '@type': 'profilePhoto', 'small': small };
  const result: TdObject = { '@type': 'user' };
  result['usernames'] = names;
  if (avatarFileId > 0) {
    result['profile_photo'] = photo;
  }
  return result;
}
async function settle(): Promise<void> { for (let i = 0; i < 20; i++) { await Promise.resolve(); } }
class CommandHarness {
  bridge: CommandBridge = new CommandBridge();
  client: TdClient = new TdClient(this.bridge);
  activeClient: TdClient = this.client;
  state: CommandSuggestionState = new CommandSuggestionState();
  chatId: number = -10077;
  draft: string = '/';
  constructor() {
    this.client.start();
    this.state.bind({ chatId: (): number => this.chatId, store: (): MessageStore | null => null,
      draft: (): string => this.draft, client: (): TdClient => this.activeClient });
  }
  async startGroup(): Promise<void> {
    this.state.ensureCommandsLoaded(); this.bridge.reply(0, chat()); await settle();
  }
  async readyGroup(): Promise<void> {
    await this.startGroup(); this.bridge.reply(1, full()); await settle();
    this.bridge.reply(2, user()); await settle();
  }
  close(): void { this.state.dispose(); this.client.dispose(); }
}
export default function botCommandMenuTest() {
  describe('BotCommandMenu', () => {
    it('群聊读取群目录并附带机器人用户名，不搜索成员或读取私聊指令', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.readyGroup();
      expect(h.bridge.sent.map((r: TdObject): string => r['@type'] as string))
        .assertDeepEquals(['getChat', 'getSupergroupFullInfo', 'getUser']);
      expect(h.state.botMenuAvailable).assertTrue();
      expect(h.state.commandItems[0].command).assertEqual('group');
      expect(h.state.commandItems[0].botUsername).assertEqual('group_bot');
      expect(h.state.commandItems[0].avatarFileId).assertEqual(42); h.close();
    });
    it('基础群使用基础群目录', 0, async (): Promise<void> => {
      const h = new CommandHarness(); const pending = loadBotCommands(h.client, -88, 0);
      h.bridge.reply(0, chat('chatTypeBasicGroup')); await settle();
      expect(h.bridge.sent[1]['@type']).assertEqual('getBasicGroupFullInfo');
      expect(h.bridge.sent[1]['basic_group_id']).assertEqual(88);
      h.bridge.reply(1, full('')); expect((await pending).length).assertEqual(0); h.close();
    });
    it('频道不请求群指令也不显示入口', 0, async (): Promise<void> => {
      const h = new CommandHarness(); h.state.ensureCommandsLoaded(); h.bridge.reply(0, chat('chatTypeSupergroup', true)); await settle();
      expect(h.bridge.sent.length).assertEqual(1); expect(h.state.botMenuAvailable).assertFalse(); h.close();
    });
    it('普通用户私聊没有bot_info时隐藏入口', 0, async (): Promise<void> => {
      const h = new CommandHarness(); h.state.ensureCommandsLoaded(); h.bridge.reply(0, chat('chatTypePrivate')); await settle();
      h.bridge.reply(1, { '@type': 'userFullInfo' }); await settle();
      expect(h.state.commandLoadState).assertEqual('ready'); expect(h.state.botMenuAvailable).assertFalse(); h.close();
    });
    it('机器人私聊保持不附带用户名', 0, async (): Promise<void> => {
      const h = new CommandHarness(); const pending = loadBotCommands(h.client, 10, 10);
      const info: TdObject = { '@type': 'botInfo' };
      const cmd: TdObject = { '@type': 'botCommand' }; cmd['command'] = 'start'; info['commands'] = [cmd];
      const response: TdObject = { '@type': 'userFullInfo' }; response['bot_info'] = info;
      h.bridge.reply(0, response); const items = await pending;
      expect(items[0].command).assertEqual('start'); expect(items[0].botUsername).assertEqual(''); h.close();
    });
    it('推送清空指令后立即隐藏入口', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.readyGroup(); h.bridge.update(full('')); await settle();
      expect(h.state.botMenuAvailable).assertFalse(); expect(h.state.catalogSize()).assertEqual(0); h.close();
    });
    it('其他群推送不影响当前群', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.readyGroup(); h.bridge.update(full(''), 78); await settle();
      expect(h.state.botMenuAvailable).assertTrue(); expect(h.bridge.sent.length).assertEqual(3); h.close();
    });
    it('更新推送优先于旧目录应答', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.startGroup(); h.bridge.update(full('')); await settle();
      h.bridge.reply(1, full('old')); await settle(); h.bridge.reply(2, user()); await settle();
      expect(h.state.botMenuAvailable).assertFalse(); expect(h.state.catalogSize()).assertEqual(0); h.close();
    });
    it('两次更新的用户名查询乱序时只应用最新目录', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.readyGroup(); h.bridge.update(full('old')); h.bridge.update(full('new'));
      h.bridge.reply(4, user()); await settle(); h.bridge.reply(3, user()); await settle();
      expect(h.state.commandItems[0].command).assertEqual('new'); h.close();
    });
    it('重复更新不重复查询机器人资料', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.readyGroup(); h.bridge.update(full('new')); h.bridge.update(full('new'));
      expect(h.bridge.sent.length).assertEqual(4); h.bridge.reply(3, user()); await settle(); h.close();
    });
    it('页面销毁后旧应答与推送均不恢复入口', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.startGroup(); h.state.dispose(); h.bridge.update(full());
      h.bridge.reply(1, full()); await settle(); h.bridge.reply(2, user()); await settle();
      expect(h.state.botMenuAvailable).assertFalse(); expect(h.state.commandLoadState).assertEqual('idle'); h.close();
    });
    it('切账号后旧响应不写入状态', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.startGroup(); h.activeClient = new TdClient(new CommandBridge());
      h.bridge.reply(1, full()); await settle(); h.bridge.reply(2, user()); await settle();
      expect(h.state.botMenuAvailable).assertFalse(); h.close(); h.activeClient.dispose();
    });
    it('群目录取数失败保留错误态供手输斜杠重试', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.startGroup(); const error: TdObject = { '@type': 'error' };
      error['code'] = 500; error['message'] = 'offline'; h.bridge.reply(1, error); await settle();
      expect(h.state.commandLoadState).assertEqual('error'); expect(h.state.botMenuAvailable).assertFalse(); h.close();
    });
    it('没有机器人用户名时不生成可能发错对象的群指令', 0, async (): Promise<void> => {
      const h = new CommandHarness(); await h.startGroup(); h.bridge.reply(1, full()); await settle();
      h.bridge.reply(2, user('')); await settle(); expect(h.state.botMenuAvailable).assertFalse(); h.close();
    });
  });
}
