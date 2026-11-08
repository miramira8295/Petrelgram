// Each invocation owns its detached player and sources. A reused component may
// already have new fields by the time this native job completes.
export async function releaseVideoResources(beginRelease: (() => Promise<boolean>) | null,
  recoverRelease: () => void, closeSources: (() => void)[]): Promise<void> {
  if (beginRelease !== null) {
    try {
      if (!await beginRelease()) {
        throw new Error('Native video release did not complete');
      }
    } catch (error) {
      // Exceptional recovery for failed native work creation/queueing. Never
      // close a data source while its decoder can still be reading from it.
      recoverRelease();
    }
  }
  let failed: boolean = false;
  for (const close of closeSources) {
    try {
      close();
    } catch (error) {
      failed = true;
    }
  }
  if (failed) {
    throw new Error('Video source cleanup failed');
  }
}
