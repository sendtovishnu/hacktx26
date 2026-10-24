# HackTX '26: Digital Twin Friend Network

Rank your friends, connect your calendar and email, and let your digital twin quietly tell your closest friends when you could use support, with a concrete way to help.

## Branches

| Branch | Owner | Scope |
| --- | --- | --- |
| `main` | everyone | Always demoable. Person A pushes the Next.js scaffold here first. |
| `a-backend` | Person A | Database, API routes, Google ingest, rules (`app/api/`, `lib/db/`, `lib/google/`, `lib/rules/`) |
| `b-ai` | Person B | Gemini, Muse Spark and SerpApi (`lib/ai/`, `lib/places/`, `scripts/`) |
| `c-frontend` | Person C | All screens and the demo (`app/` pages and components) |

The full plan, shared contract and each person's track are in the team build plan doc. Pull `main` into your branch after the scaffold lands and whenever someone announces a merge. All branches merge into `main` at 4:20pm: B, then A, then C.

Never commit secrets: keys go in `.env.local`.
