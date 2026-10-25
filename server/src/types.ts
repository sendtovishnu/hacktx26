export type Tier = 'friend' | 'close' | 'closest';
export type SupportLevel = 'doing_fine' | 'could_use_support' | 'struggling';
export type GestureType = 'drop_off' | 'hangout' | 'message';
export interface User {
  id: string; name: string; email: string; homeLocation: string;
  preferences: { coffeeOrder?: string; likes: 'company' | 'space' };
  surpriseOptIn: boolean; paused: boolean;
  // openToSupport: the twin may tell friends you could use support (same column as surpriseOptIn).
  // surprisesOn: a friend's gesture stays hidden until they mark it delivered.
  openToSupport?: boolean; surprisesOn?: boolean; phone?: string; photoUrl?: string;
  // Picked at sign-up (and editable): what suggestions are built around.
  interests?: string[];
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
// lastReaction: how the user said this friend's last gesture landed ('space' means prefer a note).
export interface TwinFriendInput {
  friend: User; tier: Tier; sharedFreeMinutes: number; showedUpForThem?: string; lastReaction?: 'helped' | 'space';
}
// reason: one sentence for the user's privacy log on why this friend was nudged.
export interface TwinDecision { friendId: string; message: string; gestureType: GestureType; surpriseNote: string; reason?: string }
// lat/lng from SerpApi, so the app can show the place on a map.
export interface Place { name: string; address: string; rating?: number; openNow?: boolean; mapsUrl?: string; lat?: number; lng?: number }
// item: what a drop-off brings, so the fallback note can name it.
export interface Suggestion { gestureType: GestureType; title: string; detail: string; place?: Place; item?: string }
export interface Nudge {
  id: string; fromUser: User; toFriendId: string; message: string;
  contextLevel: 'closest' | 'close'; status: 'sent' | 'seen' | 'acted';
  createdAt: string;
  // Muse's starter note the friend edits; when and where the friend's twin says they can show up;
  // why the twin nudged (shown to the sender only, in the privacy log).
  draftNote?: string; moment?: string; reason?: string;
  // What the friend did, so they can mark a surprise delivered.
  gesture?: { id: string; surprise: boolean; revealed: boolean };
}
// reaction: how the person helped said it landed; their twin reads it next time.
// surprise: the person had surprises on, so they only see this once the friend marks it delivered.
export interface Gesture { id: string; nudgeId: string; fromFriend: User; type: GestureType; place?: Place; note: string; deliveredAt: string; reaction?: 'helped' | 'space'; surprise?: boolean }
