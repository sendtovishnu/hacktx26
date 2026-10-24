# iOS app (Person C, branch `c-frontend`)

## Run it

1. Open `ios/Twin.xcodeproj` in Xcode 16 or later.
2. Pick an iPhone simulator and press Run. The app starts in **mock mode**: the whole flow runs on the JSON in `Twin/Mocks/`, no server needed.
3. To run on a real iPhone: select the Twin target > Signing & Capabilities > choose your Team. Change the bundle ID if Xcode says it is taken.

## Try the demo flow in mock mode

1. Pick **Maya** in the top-right user menu. Twin tab > **Refresh my twin**. The twin reads a midterm week and nudges 1 friend.
2. Switch to **Jay**. A notification arrives within 5 seconds; the Nudges tab shows Maya. Open it and tap **Do this** on a suggestion.
3. Switch back to **Maya**. The surprise screen appears.
4. **Priya** never gets a nudge about Maya, because Maya ranks her as Friend.

Mock state lives in memory, so relaunching resets it.

## Switch to the real server

Privacy tab > Developer: turn off **Use mock data**, set the server URL, tap **Apply**.

- Simulator: `http://localhost:3000`
- Physical phone: the tunnel URL from Person A (`cloudflared tunnel --url http://localhost:3000`)

## Turn on Google sign-in (Connect tab)

1. File > Add Package Dependencies > `https://github.com/google/GoogleSignIn-iOS`, add the **GoogleSignIn** product to the Twin target. The sign-in code switches on automatically once the package is present.
2. In `Twin-Info.plist`, fill in:
   - `GIDClientID`: the **iOS** OAuth client ID from Person A
   - `GIDServerClientID`: the **Web** OAuth client ID (so sign-in returns a `serverAuthCode` for the server)
   - the URL scheme: the iOS client ID reversed (`com.googleusercontent.apps.…`)

## Files

| File | What |
| --- | --- |
| `Twin/Models.swift` | Codable models mirroring `server/src/types.ts` |
| `Twin/API.swift` | `TwinAPI` protocol and the real `APIClient` (sends `X-Demo-User`) |
| `Twin/MockAPI.swift` | In-memory implementation of the full flow |
| `Twin/AppState.swift` | Current user, API choice, 5-second polling, local notifications |
| `Twin/Views/` | Friends, Connect, Twin, Nudges and suggestions, Surprise, Privacy |

The app's display name is set by `INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings; change it there once the team picks a name.
