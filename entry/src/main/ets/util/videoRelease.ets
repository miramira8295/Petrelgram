// Keep native teardown on the JS thread: the plugin's releaseAsync worker was
// present in the reported IjkMediaPlayer_release CppCrash stacks. This avoids
// that worker path; it does not establish a native lifetime guarantee.
let nativeReleaseChain: Promise<void> = Promise.resolve();

// Each job owns detached resources, so reusing the component cannot make an old
// release close a new session. Yield between jobs: Promise chaining alone would
// drain synchronous native releases in one microtask burst and block the UI.
export function enqueueNativeReleaseSync(beginRelease: (() => void) | null,
  closeSources: (() => void)[]): Promise<void> {
  const ownedSources: (() => void)[] = closeSources.slice();
  const run: Promise<void> = nativeReleaseChain.then(async (): Promise<void> => {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
    if (beginRelease !== null) {
      try {
        beginRelease();
      } catch (error) {
        // Never retry an uncertain native release or close a source the decoder
        // may still own. Report the failure; a later independent job may proceed.
        throw new Error(`Native video release failed: ${error}`);
      }
    }
    let firstFailure: string = '';
    let failed: boolean = false;
    for (const close of ownedSources) {
      try {
        close();
      } catch (error) {
        if (!failed) {
          firstFailure = `${error}`;
        }
        failed = true;
      }
    }
    if (failed) {
      throw new Error(`Video source cleanup failed: ${firstFailure}`);
    }
  });
  // Recover only the private queue tail. Return the original promise so callers
  // can log failures and do not report a failed release as a successful one.
  nativeReleaseChain = run.catch((): void => {});
  return run;
}
