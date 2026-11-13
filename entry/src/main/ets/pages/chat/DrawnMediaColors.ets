import { common2D } from '@kit.ArkGraphics2D';
import { drawnColor } from './DrawnTextLine';

// Per-layout owner, with immutable resource/color inputs. Resource resolution
// is environment-dependent; never reuse a resolved color across theme epochs.
// At most 16 entries even when custom outgoing colors change repeatedly.
export class DrawnMediaColors {
  private environment: string = '';
  private colors: Map<ResourceColor, common2D.Color> = new Map();

  resolve(color: ResourceColor, environment: string): common2D.Color {
    if (this.environment !== environment) {
      this.colors.clear(); this.environment = environment;
    }
    const cached = this.colors.get(color);
    if (cached !== undefined) { return cached; }
    const resolved = drawnColor(color);
    if (this.colors.size >= 16) {
      const oldest: ResourceColor | undefined = this.colors.keys().next().value;
      if (oldest !== undefined) { this.colors.delete(oldest); }
    }
    this.colors.set(color, resolved);
    return resolved;
  }
}
