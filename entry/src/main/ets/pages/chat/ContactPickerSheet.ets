import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';

export interface PickedContact {
  userId: number;
  phone: string;
  firstName: string;
  lastName: string;
}

interface ContactRow {
  userId: number;
  name: string;
  firstName: string;
  lastName: string;
  phone: string;
  initials: string;
}

// 发送名片：TDLib 联系人列表选择一个。
@Component
export struct ContactPickerSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onPick: (contact: PickedContact) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State rows: ContactRow[] = [];
  @State loadState: string = 'loading'; // loading | ready | error

  aboutToAppear(): void {
    const req: TdRequest = { '@type': 'getContacts' };
    getTdClient().send(req).then((res: TdObject): void => {
      const ids: number[] = (res['user_ids'] as number[] | undefined) ?? [];
      return this.loadUsers(ids);
    }).catch((e: TdError): void => {
      logE(`ContactPickerSheet.getContacts failed: ${e.message}`);
      this.loadState = 'error';
    });
  }

  private loadUsers(ids: number[]): void {
    const requests: Promise<TdObject>[] = ids.map((id: number): Promise<TdObject> => {
      const req: TdRequest = { '@type': 'getUser' };
      req['user_id'] = id;
      return getTdClient().send(req);
    });
    Promise.all(requests).then((users: TdObject[]): void => {
      this.rows = users.map((user: TdObject): ContactRow => {
        const first: string = (user['first_name'] as string | undefined) ?? '';
        const last: string = (user['last_name'] as string | undefined) ?? '';
        const name: string = `${first} ${last}`.trim();
        return {
          userId: (user['id'] as number | undefined) ?? 0,
          name: name !== '' ? name : str('tab_contacts'),
          firstName: first,
          lastName: last,
          phone: (user['phone_number'] as string | undefined) ?? '',
          initials: name !== '' ? name.substring(0, 1).toUpperCase() : '?'
        };
      }).filter((row: ContactRow): boolean => row.userId > 0);
      this.loadState = 'ready';
    }).catch((e: TdError): void => {
      logE(`ContactPickerSheet.loadUsers failed: ${e.message}`);
      this.loadState = 'error';
    });
  }

  build() {
    Column() {
      Column().layoutWeight(1).onClick((): void => this.onClose());
      Column({ space: 10 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Text($r('app.string.cp_send_contact')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        if (this.loadState === 'loading') {
          LoadingProgress().width(28).height(28).margin({ top: 30, bottom: 30 });
        } else if (this.loadState === 'error') {
          Text($r('app.string.contacts_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 30, bottom: 30 });
        } else if (this.rows.length === 0) {
          Text($r('app.string.cp_no_contacts')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 30, bottom: 30 });
        } else {
          List() {
            ForEach(this.rows, (row: ContactRow) => {
              ListItem() {
                Row({ space: 12 }) {
                  AvatarView({
                    avatarPath: '', initials: row.initials,
                    colorSeed: row.userId, avatarSize: 40
                  });
                  Column({ space: 2 }) {
                    Text(row.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (row.phone !== '') {
                      Text(`+${row.phone}`).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                }
                .width('100%').padding({ top: 8, bottom: 8 })
                .onClick((): void => {
                  this.onPick({
                    userId: row.userId, phone: row.phone,
                    firstName: row.firstName, lastName: row.lastName
                  });
                });
              }
            }, (row: ContactRow): string => `contact_${row.userId}`);
          }
          .constraintSize({ maxHeight: 360 });
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 24 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 16, topRight: 16 });
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000');
  }
}
