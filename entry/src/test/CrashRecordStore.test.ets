import { describe, expect, it } from '@ohos/hypium';
import { structuralNativeCrashDetails } from '../main/ets/services/crashRecordStore';

export default function crashRecordStoreTest(): void {
  describe('CrashRecordStore', (): void => {
    it('keeps only structural native crash details', 0, (): void => {
      const log: string = [
        'Page switch history:',
        '  /ets/pages/Index:ChatPage',
        'Reason:Signal:SIGTRAP(TRAP_BRKPT)',
        'LastFatalMessage:may double free',
        'Fault thread info:',
        'Tid:39837, Name:petrelgram',
        '#00 pc 123 /system/lib64/librosen_text.z.so(TextPattern)',
        '#01 at aboutToBeDeleted entry (entry/src/main/ets/pages/chat/ChatPage.ets:291:2)',
        'Registers:',
        'x0:secret-register-value',
        'HiLog:',
        'private chat text'
      ].join('\n');
      const details = structuralNativeCrashDetails(log);
      expect(details.message).assertEqual('may double free');
      expect(details.stack.indexOf('ChatPage.ets') >= 0).assertTrue();
      expect(details.stack.indexOf('private chat text') < 0).assertTrue();
      expect(details.stack.indexOf('secret-register-value') < 0).assertTrue();
      expect(details.stack.indexOf('Page switch history') < 0).assertTrue();
    });

    it('falls back to the signal reason', 0, (): void => {
      const details = structuralNativeCrashDetails(
        'Reason:Signal:SIGABRT\nFault thread info:\nTid:1\n#00 pc 1 libentry.so\nOther thread info:'
      );
      expect(details.message).assertEqual('Signal:SIGABRT');
      expect(details.stack.indexOf('#00 pc 1 libentry.so') >= 0).assertTrue();
    });
  });
}
