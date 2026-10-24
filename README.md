# HackTX '26: Digital Twin Friend Network

An iOS app. Rank your friends, connect your calendar and email, and let your digital twin quietly tell your closest friends when you could use support, with a concrete way to help.

## Layout

| Path | What |
| --- | --- |
| `ios/` | SwiftUI app (Person C) |
| `server/` | TypeScript Express server: API, database, Google ingest, AI, SerpApi (Persons A and B) |

## Run it locally

Needs a Mac with Xcode and [Homebrew](https://brew.sh). Run `make` to list every command.

```bash
git clone https://github.com/sendtovishnu/hacktx26.git && cd hacktx26
make setup     # node, Postgres, server deps, server/.env, seeded database
```

Add your keys to `server/.env` (`GEMINI_API_KEY`, `META_API_KEY`, `SERPAPI_KEY`). Without them the app still runs, but the twin and places steps return canned fixtures.

```bash
make server    # API on :3000, restarts when you save a file
make sim       # in a second terminal: build and launch on the Simulator
```

Postgres lives in `~/.hacktx26/pgdata`, outside the repo. `make db-reset` puts the demo back to its starting state, and `make db-stop` shuts Postgres down.

### On your iPhone

One-time setup:

1. Xcode > Settings > Accounts: add your Apple ID. A free account works, but installed apps expire after 7 days.
2. Plug the iPhone in, tap **Trust This Computer**, then turn on Settings > Privacy & Security > **Developer Mode** and restart it.
3. `cp local.mk.example local.mk` and fill in `TEAM_ID`, a `BUNDLE_ID` of your own, and `DEVICE` (from `make devices`). `local.mk` is git-ignored.

Then, with `make server` running:

```bash
make phone     # build, install and launch; rerun after every change
```

The app is built to talk to this Mac's Wi-Fi address (`make ip`), so keep the phone on the same Wi-Fi. If the network blocks devices from reaching each other, as many venue networks do, run `make tunnel` and put the `https://…trycloudflare.com` URL in `local.mk` as `SERVER_URL`.

The first launch asks for Local Network access: allow it. To point an installed app somewhere else without rebuilding, use Privacy > Developer in the app.

### Connect Google Calendar and Gmail (optional)

The demo runs without this: seeded data or an `.ics` upload stands in. To turn on **Account > Connect** in the app, someone on the team creates these once at [console.cloud.google.com](https://console.cloud.google.com):

1. Create a project, then enable the **Google Calendar API** and **Gmail API**.
2. Set up the OAuth consent screen as External, leave it in **testing**, add the `calendar.readonly` and `gmail.readonly` scopes, and add each teammate's Google account as a **test user**.
3. Create an OAuth client of type **iOS**, using the bundle ID you build with (`BUNDLE_ID` from `local.mk` for a phone, `com.sendtovishnu.hacktx26.twin` for the Simulator).
4. Create an OAuth client of type **Web application**. It needs no redirect URIs.
5. Put them in `server/.env` (share these privately, never in git):

   ```
   GOOGLE_IOS_CLIENT_ID=…apps.googleusercontent.com
   GOOGLE_WEB_CLIENT_ID=…apps.googleusercontent.com
   GOOGLE_WEB_CLIENT_SECRET=…
   ```

6. Restart `make server`, then rebuild with `make sim` or `make phone`, which copy the client IDs into the app.

Because the app is unverified, Google shows a warning on sign-in: test users tap **Advanced > Continue**.

## Branches

| Branch | Owner | Scope |
| --- | --- | --- |
| `main` | everyone | Always demoable. Person A pushes the server scaffold here first. |
| `a-backend` | Person A | `server/src/routes/`, `server/src/db/`, `server/src/google/`, `server/src/rules/` |
| `b-ai` | Person B | `server/src/ai/`, `server/src/places/`, `server/scripts/` |
| `c-frontend` | Person C | `ios/` (only Person C opens the Xcode project) |

The full plan, shared contract and each person's track are in the team build plan doc. Merge `main` into your branch after the scaffold lands and whenever someone announces a merge. All branches merge into `main` at 4:20pm: B, then A, then C.

Never commit secrets: server keys go in `server/.env`.
