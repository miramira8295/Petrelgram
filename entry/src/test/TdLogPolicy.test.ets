import { describe, expect, it } from '@ohos/hypium';
import { configureTdLogging, TD_LOG_VERBOSITY } from '../main/ets/tdkit/TdLogPolicy';
import { TdObject } from '../main/ets/tdkit/TdTypes';

class LogBridge {
  level: number = 5;
  requests: string[] = [];
  failSet: boolean = false;
  ignoreSet: boolean = false;

  execute(json: string): string {
    const request = JSON.parse(json) as TdObject;
    const type = request['@type'] as string;
    this.requests.push(type);
    if (type === 'getLogVerbosityLevel') {
      return JSON.stringify({ '@type': 'logVerbosityLevel', verbosity_level: this.level });
    }
    if (type === 'setLogVerbosityLevel') {
      if (this.failSet) { return '{"@type":"error","code":400,"message":"rejected"}'; }
      if (!this.ignoreSet) { this.level = request['new_verbosity_level'] as number; }
      return '{"@type":"ok"}';
    }
    throw new Error('unexpected request: ' + type);
  }
}

export default function tdLogPolicyTest() {
  describe('TdLogPolicy', () => {
    it('先读取真实等级再设置并回读验证，保留警告及错误', 0, (): void => {
      const bridge = new LogBridge();
      const result = configureTdLogging((json: string): string => bridge.execute(json));
      expect(result.previousLevel).assertEqual(5);
      expect(result.effectiveLevel).assertEqual(2);
      expect(TD_LOG_VERBOSITY).assertEqual(2);
      expect(result.verified).assertTrue();
      expect(bridge.requests.join(',')).assertEqual(
        'getLogVerbosityLevel,setLogVerbosityLevel,getLogVerbosityLevel');
    });

    it('已经是2时记录真实原值，不虚报从5降低', 0, (): void => {
      const bridge = new LogBridge();
      bridge.level = 2;
      const result = configureTdLogging((json: string): string => bridge.execute(json));
      expect(result.previousLevel).assertEqual(2);
      expect(result.effectiveLevel).assertEqual(2);
      expect(result.verified).assertTrue();
    });

    it('重新初始化恢复默认策略，不保留上个会话临时详细等级', 0, (): void => {
      const bridge = new LogBridge();
      configureTdLogging((json: string): string => bridge.execute(json));
      bridge.level = 4;
      const result = configureTdLogging((json: string): string => bridge.execute(json));
      expect(result.previousLevel).assertEqual(4);
      expect(result.effectiveLevel).assertEqual(2);
      expect(result.verified).assertTrue();
    });

    it('设置失败不能报告成功，也不向调用方抛出异常', 0, (): void => {
      const bridge = new LogBridge();
      bridge.failSet = true;
      const result = configureTdLogging((json: string): string => bridge.execute(json));
      expect(result.effectiveLevel).assertEqual(5);
      expect(result.verified).assertFalse();
    });

    it('设置返回ok但实际等级未改变也必须判为失败', 0, (): void => {
      const bridge = new LogBridge();
      bridge.ignoreSet = true;
      const result = configureTdLogging((json: string): string => bridge.execute(json));
      expect(result.effectiveLevel).assertEqual(5);
      expect(result.verified).assertFalse();
    });

    it('首次读取失败仍尝试设置并以最终回读验证', 0, (): void => {
      const bridge = new LogBridge();
      let first: boolean = true;
      const result = configureTdLogging((json: string): string => {
        if (first) { first = false; throw new Error('query failed'); }
        return bridge.execute(json);
      });
      expect(result.previousLevel === undefined).assertTrue();
      expect(result.effectiveLevel).assertEqual(2);
      expect(result.verified).assertTrue();
    });

    it('空值或畸形响应不能让日志配置阻断启动', 0, (): void => {
      for (const invalid of ['', 'null', '[]', 'false', '{}', '{']) {
        const result = configureTdLogging((_json: string): string => invalid);
        expect(result.verified).assertFalse();
        expect(result.previousLevel === undefined).assertTrue();
        expect(result.effectiveLevel === undefined).assertTrue();
      }
    });

    it('回读等级必须是非负整数，不能误接受字符串或其他对象', 0, (): void => {
      for (const invalid of [
        '{"@type":"logVerbosityLevel","verbosity_level":"2"}',
        '{"@type":"logVerbosityLevel","verbosity_level":-1}',
        '{"@type":"logVerbosityLevel","verbosity_level":2.5}',
        '{"@type":"error","verbosity_level":2}'
      ]) {
        const result = configureTdLogging((json: string): string =>
          json.indexOf('setLogVerbosityLevel') >= 0 ? '{"@type":"ok"}' : invalid);
        expect(result.verified).assertFalse();
        expect(result.effectiveLevel === undefined).assertTrue();
      }
    });
  });
}
