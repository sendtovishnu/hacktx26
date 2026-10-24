# iOS app (Person C, branch `c-frontend`)

## Run it

1. Open `ios/Twin.xcodeproj` in Xcode 16 or later.
2. Pick an iPhone simulator and press Run. The app starts in **mock mode**: the whole flow runs on the JSON in `Twin/Mocks/`, no server needed.
3. To run on a real iPhone: select the Twin target > Signing & Capabilities > choose your Team. Change the bundle ID if Xcode says it is taken.

## Try the demo flow in mock mode

First launch shows Welcome, then Sign in (tap a demo account chip, or use Apple or Google, which sign in as Maya), then a short setup.

1. As **Maya**: Twin tab > **Refresh my twin**. The twin reads a midterm week. It never says whether it nudged anyone, so the surprise stays a surprise.
2. Tap your photo (top right) > **Demo: switch account** > **Jay**. A notification arrives; the Nudges tab shows Maya. Open it and tap **Do this**.
3. Switch back to **Maya**. The surprise screen appears.
4. **Priya** never gets a nudge about Maya, because Maya keeps her in the Friends circle.

Circles are set when you add someone (Add friends tab) and changed only from a friend's profile on Home. Mock state lives in memory, so relaunching resets it. To see the welcome and sign-in screens again, sign out from Account (or delete the app from the simulator).

## Switch to the real server

Privacy tab > Developer: turn off **Use mock data**, set the server URL, tap **Apply**.

- Simulator: `http://localhost:3000`
- Physical phone: the tunnel URL from Person A (`cloudflared tunnel --url http://localhost:3000`)

## Turn on Google sign-in (Account > Connected accounts)

Do **not** hand-edit `Twin-Info.plist`. Person A pastes three values into `server/.env`, then you rebuild with Make so the IDs are baked into the app:

```bash
# in server/.env (never commit):
GOOGLE_IOS_CLIENT_ID=….apps.googleusercontent.com
GOOGLE_WEB_CLIENT_ID=….apps.googleusercontent.com
GOOGLE_WEB_CLIENT_SECRET=…

make google-check   # fails with a clear message if any are empty
make server         # restart after editing .env
make sim            # or make phone
```

Full Google Cloud console steps are in the root README under **Connect Google Calendar and Gmail**. The GoogleSignIn package is already pinned in the Xcode project.

## Files

| File | What |
| --- | --- |
| `Twin/Models.swift` | Codable models mirroring `server/src/types.ts` |
| `Twin/API.swift` | `TwinAPI` protocol and the real `APIClient` (sends `X-Demo-User`) |
| `Twin/MockAPI.swift` | In-memory implementation of the full flow |
| `Twin/AppState.swift` | Current user, API choice, 5-second polling, local notifications |
| `Twin/Views/` | Welcome, sign-in and setup; Home (orbits and circles); Add friends; Twin; Nudges and suggestions; Surprise; Privacy; Account |

The app's display name is set by `INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings; change it there once the team picks a name.
