// One observation target per physical image slot; never a component per image.
// Publishing a slot cannot dirty sibling placeholders or the row's layout plan.
@ObservedV2
export class DrawnImageRevision {
  @Trace revision: number = 0;
  publish(): void { this.revision++; }
}
