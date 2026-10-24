export type Tier = 'friend' | 'close' | 'closest';
export type SupportLevel = 'doing_fine' | 'could_use_support' | 'struggling';
export type GestureType = 'drop_off' | 'hangout' | 'message';
export interface User {
  id: string; name: string; email: string; homeLocation: string;
  preferences: { coffeeOrder?: string; likes: 'company' | 'space' };
  surpriseOptIn: boolean; paused: boolean;
}
export interface FriendEntry { friend: User; tier: Tier }
export interface CalendarEvent { title: string; start: string; end: string; location?: string }
export interface EmailSnippet { from: string; subject: string; snippet: string; date: string }
export interface Signals {
  supportLevel: SupportLevel;
  stressors: { what: string; when: string }[];
  busyHoursNext3Days: number;
  likelyLocation?: string;
  summaryForClosest: string;
  summaryForClose: string;
}
// showedUpForThem: what the user recently did for this friend, e.g. "an oat latte drop-off" (pay it forward).
export interface TwinFriendInput { friend: User; tier: Tier; sharedFreeMinutes: number; showedUpForThem?: string }
// reason: one sentence for the user's privacy log on why this friend was nudged.
export interface TwinDecision { friendId: string; message: string; gestureType: GestureType; surpriseNote: string; reason?: string }
export interface Place { name: string; address: string; rating?: number; openNow?: boolean; mapsUrl?: string }
export interface Suggestion { gestureType: GestureType; title: string; detail: string; place?: Place }
export interface Nudge {
  id: string; fromUser: User; toFriendId: string; message: string;
  contextLevel: 'closest' | 'close'; status: 'sent' | 'seen' | 'acted';
  createdAt: string;
  // Muse's starter note the friend edits; when and where the friend's twin says they can show up;
  // why the twin nudged (shown to the sender only, in the privacy log).
  draftNote?: string; moment?: string; reason?: string;
}
export interface Gesture { id: string; nudgeId: string; fromFriend: User; type: GestureType; place?: Place; note: string; deliveredAt: string }
