# HackTX '26: Digital Twin Friend Network

An iOS app. Rank your friends, connect your calendar and email, and let your digital twin quietly tell your closest friends when you could use support, with a concrete way to help.

## Layout

| Path | What |
| --- | --- |
| `ios/` | SwiftUI app (Person C) |
| `server/` | TypeScript Express server: API, database, Google ingest, AI, SerpApi (Persons A and B) |

## Branches

| Branch | Owner | Scope |
| --- | --- | --- |
| `main` | everyone | Always demoable. Person A pushes the server scaffold here first. |
| `a-backend` | Person A | `server/src/routes/`, `server/src/db/`, `server/src/google/`, `server/src/rules/` |
| `b-ai` | Person B | `server/src/ai/`, `server/src/places/`, `server/scripts/` |
| `c-frontend` | Person C | `ios/` (only Person C opens the Xcode project) |

The full plan, shared contract and each person's track are in the team build plan doc. Merge `main` into your branch after the scaffold lands and whenever someone announces a merge. All branches merge into `main` at 4:20pm: B, then A, then C.

Never commit secrets: server keys go in `server/.env`.
