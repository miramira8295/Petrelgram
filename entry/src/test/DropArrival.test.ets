import { describe, expect, it } from '@ohos/hypium';
import { DropArrivalHost, DropArrivalSession } from '../main/ets/util/dropArrival';
import { SharedPayload } from '../main/ets/util/sharedContent';

class DropHost implements DropArrivalHost {
  alive: boolean = true;
  denied: boolean = false;
  text: string = 'draft';
  previews: SharedPayload[] = [];
  active = (): boolean => this.alive;
  check = async (_payload: SharedPayload): Promise<void> => { if (this.denied) { throw new Error('denied'); } };
  draft = (): string => this.text;
  setDraft = (text: string): void => { this.text = text; };
  preview = (payload: SharedPayload): void => { this.previews.push(payload); };
}
function textPayload(): SharedPayload { return { caption: 'incoming', media: [] }; }
function filePayload(): SharedPayload {
  return { caption: 'caption', media: [{ kind: 'file', uri: '/cache/file.pdf', text: '', title: 'file.pdf', sourceUri: '' }] };
}
export default function dropArrivalTest() {
  describe('DropArrival', (): void => {
    it('ignored_source_does_not_check_permissions_modify_draft_or_open_preview', 0, async (): Promise<void> => {
      const host = new DropHost(); host.denied = true;
      const session = new DropArrivalSession();
      expect(await session.receive(async (): Promise<SharedPayload | null> => null, host)).assertFalse();
      expect(host.text).assertEqual('draft');
      expect(host.previews.length).assertEqual(0);
    });
    it('ignored_source_releases_session_for_the_next_external_drop', 0, async (): Promise<void> => {
      const host = new DropHost(); const session = new DropArrivalSession();
      await session.receive(async (): Promise<SharedPayload | null> => null, host);
      expect(await session.receive(async (): Promise<SharedPayload> => filePayload(), host)).assertTrue();
      expect(host.previews.length).assertEqual(1);
    });
    it('text_appends_without_sending', 0, async (): Promise<void> => {
      const host = new DropHost(); const session = new DropArrivalSession();
      expect(await session.receive(async (): Promise<SharedPayload> => textPayload(), host)).assertTrue();
      expect(host.text).assertEqual('draft\nincoming'); expect(host.previews.length).assertEqual(0);
    });
    it('file_only_opens_preview', 0, async (): Promise<void> => {
      const host = new DropHost(); const session = new DropArrivalSession();
      await session.receive(async (): Promise<SharedPayload> => filePayload(), host);
      expect(host.text).assertEqual('draft'); expect(host.previews.length).assertEqual(1);
      expect(host.previews[0].caption).assertEqual('caption');
    });
    it('permission_failure_preserves_draft', 0, async (): Promise<void> => {
      const host = new DropHost(); host.denied = true; let failed = false;
      try { await new DropArrivalSession().receive(async (): Promise<SharedPayload> => filePayload(), host); }
      catch (_) { failed = true; }
      expect(failed).assertTrue(); expect(host.previews.length).assertEqual(0); expect(host.text).assertEqual('draft');
    });
    it('copy_failure_never_stages_partial_batch', 0, async (): Promise<void> => {
      const host = new DropHost(); let failed = false;
      try { await new DropArrivalSession().receive(async (): Promise<SharedPayload> => { throw new Error('copy failed'); }, host); }
      catch (_) { failed = true; }
      expect(failed).assertTrue(); expect(host.previews.length).assertEqual(0); expect(host.text).assertEqual('draft');
    });
    it('cancel_during_load_discards_result', 0, async (): Promise<void> => {
      const host = new DropHost(); const session = new DropArrivalSession();
      await session.receive(async (): Promise<SharedPayload> => { session.cancel(); return textPayload(); }, host);
      expect(host.text).assertEqual('draft');
    });
    it('inactive_target_does_not_load', 0, async (): Promise<void> => {
      const host = new DropHost(); host.alive = false; let loaded = false;
      expect(await new DropArrivalSession().receive(async (): Promise<SharedPayload> => { loaded = true; return textPayload(); }, host)).assertFalse();
      expect(loaded).assertFalse();
    });
    it('target_changes_during_permission_check', 0, async (): Promise<void> => {
      const host = new DropHost();
      host.check = async (): Promise<void> => { host.alive = false; };
      await new DropArrivalSession().receive(async (): Promise<SharedPayload> => filePayload(), host);
      expect(host.previews.length).assertEqual(0);
    });
    it('uses_latest_draft_after_async_work', 0, async (): Promise<void> => {
      const host = new DropHost();
      await new DropArrivalSession().receive(async (): Promise<SharedPayload> => { host.text = 'typed meanwhile'; return textPayload(); }, host);
      expect(host.text).assertEqual('typed meanwhile\nincoming');
    });
    it('empty_drop_rejected', 0, async (): Promise<void> => {
      const host = new DropHost(); let failed = false;
      try { await new DropArrivalSession().receive(async (): Promise<SharedPayload> => ({ caption: '', media: [] }), host); }
      catch (_) { failed = true; }
      expect(failed).assertTrue(); expect(host.text).assertEqual('draft');
    });
    it('concurrent_drop_is_not_loaded', 0, async (): Promise<void> => {
      const host = new DropHost(); const session = new DropArrivalSession(); let secondLoaded = false;
      await session.receive(async (): Promise<SharedPayload> => {
        expect(await session.receive(async (): Promise<SharedPayload> => { secondLoaded = true; return textPayload(); }, host)).assertFalse();
        return textPayload();
      }, host);
      expect(secondLoaded).assertFalse(); expect(host.text).assertEqual('draft\nincoming');
    });
  });
}
