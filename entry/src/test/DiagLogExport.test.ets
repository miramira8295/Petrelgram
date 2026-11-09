import { describe, it, expect } from '@ohos/hypium';
import { diagLogFileName, diagLogStamp } from '../main/ets/util/diagLogExport';

export default function diagLogExportTest() {
  describe('diagLogExport', () => {
    // 月/日/时/分/秒都要补零，否则 8 月 2 日 9 点会排在 8 月 12 日 10 点后面，
    // 用户导出多份时按名字排序就乱了。
    it('pads_every_field_to_two_digits', 0, () => {
      expect(diagLogStamp(new Date(2026, 0, 2, 3, 4, 5))).assertEqual('20260102-030405');
    });

    // 月份是 0 基的，少加 1 就会把 8 月写成 7 月——这种错在日志里最难发现。
    it('month_is_one_based_in_the_output', 0, () => {
      expect(diagLogStamp(new Date(2026, 7, 22, 13, 5, 9))).assertEqual('20260822-130509');
    });

    // 不用冒号和空格：部分文件系统和分享目标处理不好。
    it('stamp_has_no_colon_or_space', 0, () => {
      const s: string = diagLogStamp(new Date(2026, 7, 22, 13, 5, 9));
      expect(s.indexOf(':')).assertEqual(-1);
      expect(s.indexOf(' ')).assertEqual(-1);
    });

    it('file_name_carries_the_stamp_and_txt_suffix', 0, () => {
      expect(diagLogFileName('20260822-130509')).assertEqual('petrelgram-log-20260822-130509.txt');
    });
  });
}
