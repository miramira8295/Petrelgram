import { describe, expect, it } from '@ohos/hypium';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { messageDeletableFromProperties } from '../main/ets/util/messageModeration';
import {
  clearDeletableCache, deletableCached, ensureDeletable, seedDeletableForTest
} from '../main/ets/util/messageDeletable';

function properties(self: boolean, all: boolean): TdObject {
  return {
    '@type': 'messageProperties',
    'can_be_deleted_only_for_self': self,
    'can_be_deleted_for_all_users': all
  };
}

// 只实现 getMessageProperties 的桩：这层要验的是"问一次、缓存、回调"，
// 不是 TDLib 语义（那部分在 MessageModeration.test 里）。
class DeletableBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  requests: TdObject[] = [];
  answer: TdObject = properties(false, false);
  failWith: string = '';
  // 为 true 时不立刻回，由测试手动 deliver，用来验在途去重。
  hold: boolean = false;
  private held: TdObject[] = [];
  init(cb: (json: string) => void): void { this.receive = cb; }
  send(json: string): void {
    const req: TdObject = JSON.parse(json) as TdObject;
    this.requests.push(req);
    if (this.hold) {
      this.held.push(req);
      return;
    }
    this.answerOne(req);
  }
  deliverHeld(): void {
    const held: TdObject[] = this.held;
    this.held = [];
    this.hold = false;
    for (const req of held) { this.answerOne(req); }
  }
  private answerOne(req: TdObject): void {
    const result: TdObject = this.failWith !== ''
      ? { '@type': 'error', 'code': 400, 'message': this.failWith }
      : (JSON.parse(JSON.stringify(this.answer)) as TdObject);
    result['@extra'] = req['@extra'];
    this.receive(JSON.stringify(result));
  }
}

function clientFor(bridge: DeletableBridge): TdClient {
  const client: TdClient = new TdClient(bridge);
  client.start();
  return client;
}

// ensureDeletable 的回调**只在拿到确定答案时**触发——不确定和失败那两档本来
// 就不回调。所以测试不能等回调，只能等一轮宏任务（它排在整条 promise 链之后），
// 再直接读缓存断言。
function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => { resolve(); }, 0);
  });
}

export default function messageDeletableTest() {
  describe('MessageDeletable', () => {
    it('either_scope_being_available_makes_the_delete_item_show', 0, () => {
      expect(messageDeletableFromProperties(properties(true, true))).assertTrue();
      expect(messageDeletableFromProperties(properties(true, false))).assertTrue();
      expect(messageDeletableFromProperties(properties(false, true))).assertTrue();
    });

    it('only_both_scopes_being_false_hides_the_delete_item', 0, () => {
      expect(messageDeletableFromProperties(properties(false, false))).assertFalse();
    });

    it('missing_flags_stay_undecided_instead_of_hiding_delete_for_everyone', 0, () => {
      // 老 schema / 异常返回：认不出来就维持现状，绝不能当成"不能删"。
      const unknown: TdObject[] = [
        { '@type': 'messageProperties' } as TdObject,
        { '@type': 'ok' } as TdObject,
        { '@type': 'messageProperties', 'can_be_deleted_only_for_self': false } as TdObject,
        { '@type': 'messageProperties', 'can_be_deleted_for_all_users': false } as TdObject,
        { '@type': 'messageProperties', 'can_be_deleted_only_for_self': 'false' } as TdObject
      ];
      for (const props of unknown) {
        expect(messageDeletableFromProperties(props) === undefined).assertTrue();
      }
    });

    it('one_flag_alone_decides_when_the_other_is_absent', 0, () => {
      const onlySelf: TdObject = { '@type': 'messageProperties', 'can_be_deleted_only_for_self': true } as TdObject;
      const onlyAll: TdObject = { '@type': 'messageProperties', 'can_be_deleted_for_all_users': true } as TdObject;
      expect(messageDeletableFromProperties(onlySelf)).assertTrue();
      expect(messageDeletableFromProperties(onlyAll)).assertTrue();
    });

    it('undecided_answers_are_not_cached_so_the_next_menu_asks_again', 0, async () => {
      clearDeletableCache();
      const bridge = new DeletableBridge();
      bridge.answer = { '@type': 'messageProperties' } as TdObject;
      const client: TdClient = clientFor(bridge);
      let called: boolean = false;
      ensureDeletable(client, 77, 900, (): void => { called = true; });
      await settle();
      expect(called).assertFalse();
      expect(deletableCached(900) === undefined).assertTrue();
    });

    it('a_definite_answer_is_cached_and_only_asked_once', 0, async () => {
      clearDeletableCache();
      const bridge = new DeletableBridge();
      bridge.answer = properties(false, false);
      const client: TdClient = clientFor(bridge);
      let answered: boolean | undefined = undefined;
      ensureDeletable(client, 77, 901, (deletable: boolean): void => { answered = deletable; });
      await settle();
      expect(answered).assertFalse();
      expect(deletableCached(901)).assertFalse();
      // 第二次不再发请求，也不再回调——菜单已经知道答案了。
      let called: boolean = false;
      ensureDeletable(client, 77, 901, (): void => { called = true; });
      expect(called).assertFalse();
      expect(bridge.requests.length).assertEqual(1);
      const req: TdObject = bridge.requests[0];
      expect(req['@type']).assertEqual('getMessageProperties');
      expect(req['chat_id'] as number).assertEqual(77);
      expect(req['message_id'] as number).assertEqual(901);
    });

    it('a_failed_read_leaves_the_answer_unknown_instead_of_caching_false', 0, async () => {
      clearDeletableCache();
      const bridge = new DeletableBridge();
      bridge.failWith = 'denied';
      const client: TdClient = clientFor(bridge);
      let called: boolean = false;
      ensureDeletable(client, 77, 902, (): void => { called = true; });
      await settle();
      expect(called).assertFalse();
      expect(deletableCached(902) === undefined).assertTrue();
    });

    it('concurrent_menu_rebuilds_share_one_in_flight_read', 0, async () => {
      clearDeletableCache();
      const bridge = new DeletableBridge();
      bridge.hold = true;
      const client: TdClient = clientFor(bridge);
      ensureDeletable(client, 77, 903, (): void => {});
      ensureDeletable(client, 77, 903, (): void => {});
      expect(bridge.requests.length).assertEqual(1);
      bridge.deliverHeld();
      await settle();
      expect(deletableCached(903)).assertFalse();
    });

    it('local_and_unknown_ids_never_hit_the_bridge', 0, () => {
      clearDeletableCache();
      const bridge = new DeletableBridge();
      const client: TdClient = clientFor(bridge);
      seedDeletableForTest(904, true);
      ensureDeletable(client, 77, 904, (): void => {});
      ensureDeletable(client, 0, 905, (): void => {});
      ensureDeletable(client, 77, 0, (): void => {});
      expect(bridge.requests.length).assertEqual(0);
    });

    it('switching_chat_drops_answers_that_belong_to_the_previous_chat', 0, () => {
      clearDeletableCache();
      seedDeletableForTest(906, false);
      expect(deletableCached(906)).assertFalse();
      clearDeletableCache();
      expect(deletableCached(906) === undefined).assertTrue();
    });
  });
}
