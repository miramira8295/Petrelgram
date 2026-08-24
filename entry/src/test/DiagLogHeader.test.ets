import { describe, expect, it } from '@ohos/hypium';
import { DiagEnvironment, diagLogHeader } from '../main/ets/util/diagLogHeader';

export default function diagLogHeaderTest() {
  describe('diagLogHeader', () => {
    const full: DiagEnvironment = {
      appVersion: '1.4.1', apiVersion: 20,
      deviceModel: 'HBN-AL00', osFullName: 'OpenHarmony-5.0.0.100'
    };

    it('四项齐全时逐项落到抬头里', 0, (): void => {
      const text = diagLogHeader(full);
      expect(text.indexOf('1.4.1') >= 0).assertTrue();
      expect(text.indexOf('api: 20') >= 0).assertTrue();
      expect(text.indexOf('HBN-AL00') >= 0).assertTrue();
      expect(text.indexOf('OpenHarmony-5.0.0.100') >= 0).assertTrue();
    });

    it('抬头末尾留空行，与日志正文隔开', 0, (): void => {
      // 用户往往只贴日志开头几屏，抬头糊在第一条日志上会让两者都难读。
      expect(diagLogHeader(full).endsWith('\n\n')).assertTrue();
    });

    it('取不到的项写 unknown，不写空白', 0, (): void => {
      // 空白会被读的人当成"这一项没有意义"，而实际含义是"没取到"——
      // 后者要继续追，前者不用。
      const text = diagLogHeader({
        appVersion: '', apiVersion: 0, deviceModel: '', osFullName: ''
      });
      expect(text.indexOf('app: unknown') >= 0).assertTrue();
      expect(text.indexOf('api: unknown') >= 0).assertTrue();
      expect(text.indexOf('model: unknown') >= 0).assertTrue();
      expect(text.indexOf('os: unknown') >= 0).assertTrue();
    });

    it('不含任何身份信息字段名', 0, (): void => {
      // 这份文件是用户自己导出去发给别人的。钉死抬头里没有序列号/账号一类的
      // 东西——将来往里加字段时这条会先红。
      const text = diagLogHeader(full).toLowerCase();
      expect(text.indexOf('serial') < 0).assertTrue();
      expect(text.indexOf('udid') < 0).assertTrue();
      expect(text.indexOf('phone') < 0).assertTrue();
      expect(text.indexOf('手机号') < 0).assertTrue();
    });
  });
}
