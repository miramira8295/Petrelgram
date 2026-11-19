import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { locationCardFor } from './DrawnLocationCardLayout';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { LocationBubble } from './LocationBubble';

@ComponentV2
export struct DrawnLocationMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param boxWidth: number = 262;
  @Param widget: DrawnDocumentWidget | undefined = undefined;
  @Param chatId: number = 0;
  @Param nowSec: number = 0;
  @Param sharing: boolean = false;
  @Event onClaim: () => boolean = (): boolean => false;

  private openLocation(): void {
    if (!this.onClaim()) { return; }
    const title = this.msg.venueTitle.trim(), address = this.msg.venueAddress.trim();
    const label = title !== '' && address !== '' ? `${title}，${address}` : title || address;
    this.actions.onLocationOpen(this.msg.locationLatitude, this.msg.locationLongitude, label, this.msg.locationValid);
  }
  private stopSharing(): void {
    if (this.sharing && this.onClaim()) { this.actions.onStopLiveLocation(); }
  }
  build() {
    LocationBubble({ preparedCard: locationCardFor(this.widget), latitude: this.msg.locationLatitude, longitude: this.msg.locationLongitude,
      accuracy: this.msg.locationAccuracy, valid: this.msg.locationValid,
      livePeriod: this.msg.locationLivePeriod, expiresIn: this.msg.locationExpiresIn,
      messageDate: this.msg.date, nowSec: this.nowSec, venueTitle: this.msg.venueTitle,
      venueAddress: this.msg.venueAddress, venueProvider: this.msg.venueProvider,
      proximityRadius: this.msg.locationProximityRadius, maxWidth: this.boxWidth,
      sharing: this.sharing, fitAvailableWidth: true, realMap: true, chatId: this.chatId,
      onOpen: (): void => this.openLocation(), onStopLive: (): void => this.stopSharing() });
  }
}
