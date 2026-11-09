import { describe, it, expect } from '@ohos/hypium';
import { colorModeChanged, crashSummaryLines } from '../main/ets/util/configChange';
import { CrashRecord } from '../main/ets/services/crashRecordStore';

// #194：onConfigurationUpdate 只在颜色模式真变了时才走深浅色重算；诊断导出附最近的崩溃。
function rec(time: number, type: string, name: string, msg: string, fg: boolean, life: number): CrashRecord {
  return {
    time, crashType: type, appVersion: '1.4.7', foreground: fg, lifeTimeSec: life,
    exceptionName: name, exceptionMessage: msg, stack: '', uploaded: false
  };
}

export default function configChangeTest(): void {
  describe('configChange', (): void => {
    it('colorModeChanged：首次（prev 未知）算变化；同值不算；undefined 当未设置', 0, (): void => {
      expect(colorModeChanged(-2, 0)).assertTrue();
      expect(colorModeChanged(0, 0)).assertFalse();
      expect(colorModeChanged(1, 0)).assertTrue();
      expect(colorModeChanged(-1, undefined)).assertFalse();
      expect(colorModeChanged(0, undefined)).assertTrue();
    });
    it('crashSummaryLines：最新在前、最多 limit 条、只取异常首行', 0, (): void => {
      const lines: string[] = crashSummaryLines([
        rec(1000, 'JsError', 'TypeError', 'a is undefined\n    at foo', true, 12),
        rec(3000, 'NativeCrash', 'SIGSEGV', '', false, 3600),
        rec(2000, 'JsError', 'RangeError', 'oops', true, 5)
      ], 2);
      expect(lines.length).assertEqual(2);
      expect(lines[0].indexOf('NativeCrash') >= 0).assertTrue();
      expect(lines[0].indexOf('SIGSEGV') >= 0).assertTrue();
      expect(lines[0].indexOf('bg') >= 0).assertTrue();
      expect(lines[1].indexOf('RangeError: oops') >= 0).assertTrue();
      expect(lines[1].indexOf('\n') < 0).assertTrue();
    });
    it('crashSummaryLines：没有记录返回空数组', 0, (): void => {
      expect(crashSummaryLines([], 5).length).assertEqual(0);
    });
  });
}
