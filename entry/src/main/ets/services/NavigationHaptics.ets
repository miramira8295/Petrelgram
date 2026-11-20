import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { KEY_FOLDER_HAPTIC_ON, KEY_DOCK_HAPTIC_ON, KEY_FOLDER_HAPTIC_STRENGTH,
  KEY_DOCK_HAPTIC_STRENGTH, NAVIGATION_HAPTIC_DEFAULT, normalizeNavigationHapticStrength } from '../util/navigationHapticSettings';
import { logW } from '../util/log';

// One capability query per process. Never await a device query in a tap, queue
// delayed feedback, or substitute long time-based vibration for unsupported effects.
class NavigationHaptics {
  private queried: boolean = false;
  private supported: boolean = false;
  private lastAt: number = -Infinity;
  private warned: boolean = false;

  prepare(): void {
    if (this.queried) { return; }
    this.queried = true;
    try {
      vibrator.isSupportEffect('haptic.effect.soft').then((supported: boolean): void => {
        this.supported = supported;
      }).catch((error: BusinessError): void => { this.failure(error); });
    } catch (error) { this.failure(error as BusinessError); }
  }

  play(category: string): void {
    const folder = category === 'folder';
    if (!folder && category !== 'dock') { return; }
    if (!(AppStorage.get<boolean>(folder ? KEY_FOLDER_HAPTIC_ON : KEY_DOCK_HAPTIC_ON) ?? true)) { return; }
    if (!this.supported) { this.prepare(); return; }
    const now = Date.now();
    if (now >= this.lastAt && now - this.lastAt < 60) { return; }
    this.lastAt = now;
    const intensity = normalizeNavigationHapticStrength(AppStorage.get<number>(
      folder ? KEY_FOLDER_HAPTIC_STRENGTH : KEY_DOCK_HAPTIC_STRENGTH) ?? NAVIGATION_HAPTIC_DEFAULT);
    // Repeat the existing preset in the vibrator service (no JS timers or
    // delayed second tap); preserve the independent intensity controls.
    try {
      vibrator.startVibration({ type: 'preset', effectId: 'haptic.effect.soft', count: 2, intensity },
        { usage: 'touch' }).catch((error: BusinessError): void => { this.failure(error); });
    } catch (error) { this.failure(error as BusinessError); }
  }

  private failure(error: BusinessError): void {
    // Unsupported hardware and platform failures must never interrupt navigation.
    if (this.warned) { return; }
    this.warned = true;
    logW(`NavigationHaptics failed: ${error.code} ${error.message}`);
  }
}

export const navigationHaptics: NavigationHaptics = new NavigationHaptics();
