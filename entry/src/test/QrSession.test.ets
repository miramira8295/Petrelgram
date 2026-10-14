import { describe, expect, it } from '@ohos/hypium';
import { QrLink, QrSession, QrSnapshot } from '../main/ets/util/qrSession';
import { fetchMyUserLink, resolveUserToken } from '../main/ets/util/userLink';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { chatLinkActionOf, inviteLinkOf, isTelegramInternalUrl } from '../main/ets/util/linkNav';

class PendingQr<T> {
  resolve: (value: T) => void = (): void => {};
  reject: (error: Error) => void = (): void => {};
  promise: Promise<T> = new Promise<T>((resolve, reject): void => {
    this.resolve = resolve;
    this.reject = reject;
  });
}
interface QrTask { tick: () => void; delay: number; cancelled: boolean; }
class QrHarness {
  time: number = 1000;
  requests: PendingQr<QrLink>[] = [];
  renders: PendingQr<number>[] = [];
  urls: string[] = [];
  released: number[] = [];
  tasks: QrTask[] = [];
  state: QrSnapshot<number> = { link: '', image: null, failed: false, temporary: false };
  session: QrSession<number> = new QrSession<number>(
    (): Promise<QrLink> => {
      const pending: PendingQr<QrLink> = new PendingQr<QrLink>();
      this.requests.push(pending);
      return pending.promise;
    }, (url: string): Promise<number> => {
      this.urls.push(url);
      const pending: PendingQr<number> = new PendingQr<number>();
      this.renders.push(pending);
      return pending.promise;
    }, (value: number): void => { this.released.push(value); },
    (state: QrSnapshot<number>): void => { this.state = state; },
    (): number => this.time,
    (tick: () => void, delay: number): number => {
      this.tasks.push({ tick, delay, cancelled: false });
      return this.tasks.length - 1;
    }, (id: number): void => { this.tasks[id].cancelled = true; });

  async ready(expiresIn: number = 10): Promise<void> {
    this.session.start();
    this.requests[0].resolve({ url: 'https://t.me/contact/first', expiresIn });
    await flushQr();
    this.renders[0].resolve(1);
    await flushQr();
  }
}
async function flushQr(): Promise<void> {
  for (let i: number = 0; i < 10; i++) { await Promise.resolve(); }
}
class UserLinkBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  sent: TdObject[] = [];
  init(callback: (json: string) => void): void { this.receive = callback; }
  send(json: string): void { this.sent.push(JSON.parse(json) as TdObject); }
  reply(index: number, result: TdObject): void {
    result['@extra'] = this.sent[index]['@extra'];
    this.receive(JSON.stringify(result));
  }
}

export default function qrSessionTest() {
  describe('QrSession', () => {
    it('public_link_never_schedules_expiry_and_closes_resource', 0, async () => {
      const h: QrHarness = new QrHarness();
      await h.ready(0);
      expect(h.state.image).assertEqual(1);
      expect(h.state.temporary).assertFalse();
      expect(h.tasks.length).assertEqual(0);
      h.session.close();
      h.session.close();
      expect(h.released.length).assertEqual(1);
      expect(h.state.link).assertEqual('');
    });
    it('expiry_clears_both_old_image_and_link_before_refresh', 0, async () => {
      const h: QrHarness = new QrHarness();
      await h.ready();
      expect(h.state.temporary).assertTrue();
      h.time += 10000;
      h.tasks[0].tick();
      expect(h.state.image).assertNull();
      expect(h.state.link).assertEqual('');
      expect(h.released[0]).assertEqual(1);
      expect(h.requests.length).assertEqual(2);
      h.requests[1].resolve({ url: 'https://t.me/contact/second', expiresIn: 20 });
      await flushQr();
      expect(h.state.link).assertEqual('');
      h.renders[1].resolve(2);
      await flushQr();
      expect(h.state.link).assertEqual(h.urls[1]);
      expect(h.state.image).assertEqual(2);
      h.session.close();
    });
    it('request_time_is_deducted_from_validity', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.time += 3000;
      h.requests[0].resolve({ url: 'test', expiresIn: 10 });
      await flushQr();
      expect(h.tasks[0].delay).assertEqual(7000);
      h.session.close();
    });
    it('already_expired_response_fails_without_refresh_loop', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.time += 10000;
      h.requests[0].resolve({ url: 'test', expiresIn: 5 });
      await flushQr();
      expect(h.state.failed).assertTrue();
      expect(h.renders.length).assertEqual(0);
      expect(h.requests.length).assertEqual(1);
      h.session.close();
    });
    it('repeated_start_and_retry_do_not_duplicate_inflight_request', 0, () => {
      const h: QrHarness = new QrHarness();
      h.session.start(); h.session.start(); h.session.retry();
      expect(h.requests.length).assertEqual(1);
      h.session.close();
    });
    it('network_failure_can_be_retried', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].reject(new Error('offline'));
      await flushQr();
      expect(h.state.failed).assertTrue();
      h.session.retry();
      expect(h.requests.length).assertEqual(2);
      expect(h.state.failed).assertFalse();
      h.session.close();
    });
    it('refresh_failure_does_not_restore_expired_code', 0, async () => {
      const h: QrHarness = new QrHarness();
      await h.ready();
      h.tasks[0].tick();
      h.requests[1].reject(new Error('offline'));
      await flushQr();
      expect(h.state.failed).assertTrue();
      expect(h.state.link).assertEqual('');
      expect(h.state.image).assertNull();
      h.session.close();
    });
    it('close_rejects_late_link_and_does_not_render', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start(); h.session.close();
      h.requests[0].resolve({ url: 'late', expiresIn: 10 });
      await flushQr();
      expect(h.renders.length).assertEqual(0);
      expect(h.tasks.length).assertEqual(0);
    });
    it('close_releases_late_bitmap_without_publishing_it', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].resolve({ url: 'test', expiresIn: 10 });
      await flushQr();
      h.session.close();
      h.renders[0].resolve(9);
      await flushQr();
      expect(h.released[0]).assertEqual(9);
      expect(h.state.image).assertNull();
      expect(h.tasks[0].cancelled).assertTrue();
    });
    it('old_render_after_expiry_cannot_replace_new_code', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].resolve({ url: 'old', expiresIn: 10 });
      await flushQr();
      h.tasks[0].tick();
      h.requests[1].resolve({ url: 'new', expiresIn: 10 });
      await flushQr();
      h.renders[1].resolve(2);
      await flushQr();
      h.renders[0].resolve(1);
      await flushQr();
      expect(h.state.link).assertEqual('new');
      expect(h.state.image).assertEqual(2);
      expect(h.released[0]).assertEqual(1);
      h.session.close();
    });
    it('old_failure_cannot_poison_reopened_session', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start(); h.session.close(); h.session.start();
      h.requests[0].reject(new Error('late'));
      await flushQr();
      expect(h.state.failed).assertFalse();
      expect(h.requests.length).assertEqual(2);
      h.session.close();
    });
    it('cancelled_timer_cannot_refresh_reopened_session', 0, async () => {
      const h: QrHarness = new QrHarness();
      await h.ready();
      h.session.close(); h.session.start();
      h.tasks[0].tick();
      expect(h.requests.length).assertEqual(2);
      h.session.close();
    });
    it('render_finishing_after_deadline_is_discarded_even_if_timer_is_delayed', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].resolve({ url: 'old', expiresIn: 1 });
      await flushQr();
      h.time += 1500;
      h.renders[0].resolve(1);
      await flushQr();
      expect(h.state.image).assertNull();
      expect(h.released[0]).assertEqual(1);
      expect(h.requests.length).assertEqual(2);
      h.session.close();
    });
    it('render_failure_cancels_expiry_and_allows_retry', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].resolve({ url: 'test', expiresIn: 1 });
      await flushQr();
      h.renders[0].reject(new Error('native failure'));
      await flushQr();
      expect(h.state.failed).assertTrue();
      expect(h.tasks[0].cancelled).assertTrue();
      h.tasks[0].tick();
      expect(h.requests.length).assertEqual(1);
      h.session.retry();
      expect(h.requests.length).assertEqual(2);
      h.session.close();
    });
    it('invalid_expiry_never_creates_a_permanent_code', 0, async () => {
      const h: QrHarness = new QrHarness();
      h.session.start();
      h.requests[0].resolve({ url: 'test', expiresIn: -1 });
      await flushQr();
      expect(h.state.failed).assertTrue();
      expect(h.renders.length).assertEqual(0);
      h.session.close();
    });
  });
  describe('UserLink', () => {
    it('get_user_link_requests_current_user_without_username_or_phone', 0, async () => {
      const bridge: UserLinkBridge = new UserLinkBridge();
      const client: TdClient = new TdClient(bridge); client.start();
      const pending: Promise<QrLink> = fetchMyUserLink(client);
      expect(bridge.sent[0]['@type']).assertEqual('getUserLink');
      expect(Object.keys(bridge.sent[0]).length).assertEqual(2);
      bridge.reply(0, { '@type': 'userLink', 'url': 'https://t.me/contact/token', 'expires_in': 30 });
      const result: QrLink = await pending;
      expect(result.expiresIn).assertEqual(30);
      expect(result.url).assertEqual('https://t.me/contact/token');
    });
    it('token_lookup_creates_chat_but_does_not_send_a_message', 0, async () => {
      const bridge: UserLinkBridge = new UserLinkBridge();
      const client: TdClient = new TdClient(bridge); client.start();
      const pending: Promise<number> = resolveUserToken(client, 'test-token');
      expect(bridge.sent[0]['@type']).assertEqual('searchUserByToken');
      expect(bridge.sent[0]['token']).assertEqual('test-token');
      bridge.reply(0, { '@type': 'user', 'id': 42 });
      await flushQr();
      expect(bridge.sent[1]['@type']).assertEqual('createPrivateChat');
      expect(bridge.sent[1]['user_id']).assertEqual(42);
      expect(bridge.sent[1]['force']).assertFalse();
      bridge.reply(1, { '@type': 'chat', 'id': 42 });
      expect(await pending).assertEqual(42);
      expect(bridge.sent.length).assertEqual(2);
    });
    it('expired_token_does_not_attempt_to_create_chat', 0, async () => {
      const bridge: UserLinkBridge = new UserLinkBridge();
      const client: TdClient = new TdClient(bridge); client.start();
      const pending: Promise<number> = resolveUserToken(client, 'expired').catch((): number => -1);
      bridge.reply(0, { '@type': 'error', 'code': 400, 'message': 'USER_TOKEN_EXPIRED' });
      expect(await pending).assertEqual(-1);
      expect(bridge.sent.length).assertEqual(1);
    });
    it('empty_token_does_not_send_any_request', 0, async () => {
      const bridge: UserLinkBridge = new UserLinkBridge();
      const client: TdClient = new TdClient(bridge); client.start();
      const result: number = await resolveUserToken(client, '').catch((): number => -1);
      expect(result).assertEqual(-1);
      expect(bridge.sent.length).assertEqual(0);
    });
    it('invalid_chat_reply_is_not_a_navigation_target', 0, async () => {
      const bridge: UserLinkBridge = new UserLinkBridge();
      const client: TdClient = new TdClient(bridge); client.start();
      const pending: Promise<number> = resolveUserToken(client, 'test').catch((): number => -1);
      bridge.reply(0, { '@type': 'user', 'id': 42 });
      await flushQr();
      bridge.reply(1, { '@type': 'ok' });
      expect(await pending).assertEqual(-1);
    });
    it('contact_links_reach_tdlib_instead_of_invite_or_bot_routes', 0, () => {
      const urls: string[] = ['https://t.me/contact/test-token', 'tg://contact?token=test-token'];
      urls.forEach((url: string): void => {
        expect(isTelegramInternalUrl(url)).assertTrue();
        expect(inviteLinkOf(url)).assertEqual('');
        expect(chatLinkActionOf(url)).assertNull();
      });
    });
  });
}
