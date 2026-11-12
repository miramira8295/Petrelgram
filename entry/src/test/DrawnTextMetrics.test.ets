import { describe, expect, it } from '@ohos/hypium';
import { DrawnTextMetrics } from '../main/ets/util/drawnTextMetrics';

export default function drawnTextMetricsTest() {
  describe('DrawnTextMetrics', () => {
    it('does not add a log summary before drawing is used', 0, () => {
      expect(new DrawnTextMetrics().summary()).assertEqual('');
    });
    it('distinguishes whole-plan reuse paragraph reuse and a fresh layout', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.request(); metrics.planHit();
      metrics.request(); metrics.paragraphHit();
      metrics.request(); metrics.paragraphMiss(); metrics.paragraphBuilt();
      metrics.layoutCall(); metrics.layoutCall(); metrics.layoutCall();
      metrics.outlineBuilt(); metrics.colorUpdated();
      const snapshot = metrics.snapshot();
      expect(snapshot.requests).assertEqual(3);
      expect(snapshot.planHits).assertEqual(1);
      expect(snapshot.paragraphHits).assertEqual(1);
      expect(snapshot.paragraphMisses).assertEqual(1);
      expect(snapshot.paragraphBuilds).assertEqual(1);
      expect(snapshot.layoutCalls).assertEqual(3);
      expect(snapshot.outlineBuilds).assertEqual(1);
      expect(snapshot.colorUpdates).assertEqual(1);
      expect(metrics.summary().includes('reusePct=66.7')).assertTrue();
    });
    it('samples eight warmup misses then one in sixteen without storing a history', 0, () => {
      const metrics = new DrawnTextMetrics();
      let sampled: number = 0;
      for (let i: number = 1; i <= 40; i++) {
        const timed: boolean = metrics.paragraphMiss();
        expect(timed).assertEqual(i <= 8 || i === 16 || i === 32);
        if (timed) { sampled++; }
      }
      expect(sampled).assertEqual(10);
      expect(metrics.snapshot().paragraphMisses).assertEqual(40);
    });
    it('reports sampled timing separately and discards invalid clock readings', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.sampleBuild(0.5); metrics.sampleBuild(1.5);
      metrics.sampleBuild(Number.NaN); metrics.sampleBuild(-1); metrics.sampleBuild(Number.POSITIVE_INFINITY);
      const snapshot = metrics.snapshot();
      expect(snapshot.timedBuilds).assertEqual(2);
      expect(snapshot.sampledBuildMs).assertEqual(2);
      expect(snapshot.sampledMaxBuildMs).assertEqual(1.5);
    });
    it('reset starts a fresh diagnostic window and sampling sequence', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.request(); metrics.failure(); metrics.sampleBuild(2);
      for (let i: number = 0; i < 8; i++) { metrics.paragraphMiss(); }
      metrics.reset();
      expect(metrics.summary()).assertEqual('');
      expect(metrics.snapshot().failures).assertEqual(0);
      expect(metrics.snapshot().timedBuilds).assertEqual(0);
      expect(metrics.paragraphMiss()).assertTrue();
    });
    it('exported snapshots cannot mutate live counters', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.request();
      const snapshot = metrics.snapshot();
      snapshot.requests = 999;
      expect(metrics.snapshot().requests).assertEqual(1);
    });
    it('failed builds do not look like completed or timed layouts', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.request(); metrics.paragraphMiss(); metrics.layoutCall(); metrics.failure();
      expect(metrics.snapshot().failures).assertEqual(1);
      expect(metrics.snapshot().paragraphBuilds).assertEqual(0);
      expect(metrics.snapshot().timedBuilds).assertEqual(0);
      expect(metrics.summary().includes('reusePct=0.0')).assertTrue();
    });
    it('reading a summary does not reset counts or affect sampling', 0, () => {
      const metrics = new DrawnTextMetrics();
      metrics.request(); metrics.paragraphMiss(); metrics.sampleBuild(0.25);
      const first: string = metrics.summary();
      expect(metrics.summary()).assertEqual(first);
      expect(metrics.snapshot().paragraphMisses).assertEqual(1);
      expect(first.includes('sampling=first8_then_1in16')).assertTrue();
    });
  });
}
