import { COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

@ComponentV2
export struct ChecklistComposeSheet {
  @Param onSubmit: (title: string, tasks: string[], allowAdd: boolean, allowMark: boolean) => Promise<void> =
    (): Promise<void> => Promise.resolve();
  @Event onClose: () => void = (): void => {};
  @Local private title: string = '';
  @Local private tasks: string = '';
  @Local private allowAdd: boolean = false;
  @Local private allowMark: boolean = true;
  @Local private sending: boolean = false;
  @Local private error: string = '';
  private generation: number = 0;
  aboutToDisappear(): void { this.generation++; }
  private submit(): void {
    if (this.sending) { return; }
    const title = this.title.trim(), tasks: string[] = [];
    for (const line of this.tasks.split(/\r?\n/)) { const task = line.trim(); if (task !== '') { tasks.push(task); } }
    if (title === '' || tasks.length === 0) { this.error = str('checklist_draft_required'); return; }
    this.error = ''; this.sending = true;
    const generation = this.generation;
    const allowAdd = this.allowAdd, allowMark = this.allowMark;
    Promise.resolve().then((): Promise<void> => this.onSubmit(title, tasks, allowAdd, allowMark)).then((): void => {
      if (generation === this.generation) { this.sending = false; }
    }, (error: Error): void => {
      if (generation !== this.generation) { return; }
      this.sending = false; this.error = error.message;
    });
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row().width('100%').height('100%').backgroundColor('#66000000')
        .onClick((): void => { if (!this.sending) { this.onClose(); } });
      Column({ space: 12 }) {
        Row() {
          Text(str('checklist_title')).fontSize(20).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          Button(str('cancel')).enabled(!this.sending).onClick((): void => { if (!this.sending) { this.onClose(); } });
        }.width('100%');
        TextInput({ text: this.title, placeholder: str('checklist_name') }).enabled(!this.sending)
          .onChange((value: string): void => { this.title = value; });
        TextArea({ text: this.tasks, placeholder: str('checklist_tasks_hint') }).height(180).enabled(!this.sending)
          .onChange((value: string): void => { this.tasks = value; });
        Row() {
          Text(str('checklist_allow_add')).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.allowAdd }).enabled(!this.sending)
            .onChange((value: boolean): void => { this.allowAdd = value; });
        }.width('100%');
        Row() {
          Text(str('checklist_allow_mark')).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.allowMark }).enabled(!this.sending)
            .onChange((value: boolean): void => { this.allowMark = value; });
        }.width('100%');
        Text(str('checklist_premium_hint')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        if (this.error !== '') { Text(this.error).fontColor('#D9514E').fontSize(13).width('100%'); }
        Button(str('send')).width('100%').backgroundColor(COLOR_PRIMARY).enabled(!this.sending)
          .onClick((): void => this.submit());
      }.width('100%').padding(20).backgroundColor(COLOR_SURFACE)
        .borderRadius({ topLeft: 20, topRight: 20 });
    }.width('100%').height('100%');
  }
}
