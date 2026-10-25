# Plan folders: going from simulated to real

When a group has decided, anyone can tap **Build folder in Google Drive** on a plan. Huddle then:

1. **Researches** every detail with SerpApi (flights, hotels, food, transit, entry rules, car listings, dealer info…).
2. **Writes** it up with Muse Spark as Google Sheets (budget, comparisons) and Google Docs (itinerary, guides).
3. **Files** everything into one new Drive folder named after the plan.
4. **Shares** the folder link back into the group chat (iMessage / WhatsApp) or anywhere else.

By default the app uses `SimulatedWorkspaceService`: same UI and events, realistic data, no network. With `HUDDLE_BACKEND_URL` set it uses `GoogleWorkspaceService`, which talks to the backend in `backend/`. This doc covers running that and going live.

## Architecture

```
iPhone (Huddle)                     Huddle backend                         External
────────────────                    ──────────────                         ────────
Build folder tap ──POST /plans/:id/workspace──▶ Muse chooses searches and files ──▶ live SerpApi
                                                    │                 │
progress UI ◀──SSE /builds/:id/events──── events ◀──┤                 ├─▶ Muse Spark (polishes prose)
                                                    │                 │
                                                    └──────────────── ├─▶ Google Drive / Sheets / Docs APIs
                                                                      └─▶ share folder by link
```

Keys never ship in the app: the **SerpApi key**, the **Muse Spark key**, and the user's **Google refresh token** live on the backend.

## 1. Google Cloud (about 15 minutes)

1. Create a Google Cloud project.
2. Enable the **Google Drive API**, the **Google Sheets API**, and the **Google Docs API**.
3. Configure the OAuth consent screen (External, testing mode is fine for the hackathon; add your teammates as test users).
4. Create OAuth clients:
   - **iOS** client with bundle ID `com.sjalkote.MuseOrganizer`.
   - **Web** client for the backend (used to exchange the server auth code for a refresh token).
5. Scope: request only `https://www.googleapis.com/auth/drive.file`. It lets Huddle create and edit **only the files it creates**, which matches the promise on the Connect screen.

In the app, add the GoogleSignIn-iOS Swift package. Sign in with the iOS client ID and `serverClientID` set to the web client, then send `serverAuthCode` to the backend. The backend exchanges it for a refresh token.

## 2. SerpApi

Get a key at serpapi.com and store it on the backend. Engines used by plan folders:

| File | Engines | Example query |
| --- | --- | --- |
| Budget, Flights and stays | `google_flights`, `google_hotels` | AUS → HND, Mar 26 – Apr 4, 4 adults |
| Food guide, Itinerary | `google_maps` | best ramen and izakaya, Shinjuku |
| Before you go | `google` | Japan entry requirements for US citizens |
| Car: Market prices | `google_shopping` | 2023 Toyota RAV4 XLE, ~37k mi, Austin |
| Car: Dealer visit prep | `google_maps`, `google` | Toyota dealers near Austin |

The blueprints in `MuseOrganizer/Models/Workspace.swift` show the exact calls and files the simulated build produces. Use them as the target output.

## 3. Muse Spark

Sign in at [dev.meta.ai](https://dev.meta.ai) (the Model API is US-only), create a key on the API keys tab, and set `MODEL_API_KEY` in `backend/.env`. Keys look like `LLM_…`. Leave `MUSE_SPARK_MODEL=muse-spark-1.3`. Credits from a program show on that dashboard under Billing and Usage. The in-app “25 credits this week” meter is a local demo counter, not that balance.

Folder builds currently use the local chooser in `heuristic_outputs`, not Muse. Turn Muse back on with [RESTORE_MUSE.md](RESTORE_MUSE.md). When that is on, Muse calls `select_outputs` to choose the searches and files, then `explain` to polish the Daily intro and the decision summary. It does not invent prices. SerpAPI supplies the numbers. A build from the app returns 503 if `SERPAPI_API_KEY` is missing. Pytest sets `HUDDLE_OFFLINE=1`.

What the backend researches and writes:

| Plan | File | From |
| --- | --- | --- |
| Trip | Budget Tracker (Sheet) | Flights price, each hotel search's own nights × rooms, fares found in Google results, food from Maps price levels |
| Trip | Daily (Doc) | Flight arrival, hotel check-ins, Maps places near where you're staying; days with nothing get "Free day" |
| Trip | Places to stay + food (Doc) | Picked hotels and the food searches |
| Car | Market prices (Sheet) | Google Shopping listings and their average |
| Car | Dealer visit prep (Doc) | Maps dealers, an APR found in Google results, lease offers |
| Car | Decision summary (Doc) | Market average vs. buyout price, the group's votes |
| Movie night | Showtimes (Sheet), Evening plan (Doc) | Theater and showtime search, food nearby |
| Outing | Plan (Doc), Budget only when prices come back | Maps places and food |
| Shopping | Shopping list (Sheet) | Item, price, and source |
| Anything else | Overview (Doc), a Sheet only when results have prices | One web search |

A file list the app already sent is written as sent. “Simulated account data” appears only on the lease demo, when the plan carries a buyout price. Prices in every other file come from SerpAPI or from the plan.

## 4. Backend contract

```
POST   /plans/{planId}/workspace   body: the plan snapshot (see below)  → 202 { "buildId": "…", "mode": "google" }
GET    /builds/{buildId}/events    text/event-stream (replays from the start, then follows)
  event: planned       data: { "folderName", "calls": [{ "id", "engine", "query" }], "files": [{ "id", "name", "kind" }] }
  event: researching   data: { "id": "<call id>", "engine": "google_flights", "query": "…" }
  event: researched    data: { "id": "<call id>", "result": "14 itineraries", "duration": 2.1 }
  event: writing       data: { "id": "<file id>", "name": "Budget Tracker", "kind": "sheet" }
  event: wrote         data: { "id": "<file id>", "summary": "5 line items · per person and group totals" }
  event: finished      data: { "folderName": "…", "url": "https://drive.google.com/…", "files": [ … with content ], "calls": [ … ] }
  event: failed        data: { "message": "…" }        (anything already written is deleted)
  event: cancelled     data: {}
DELETE /builds/{buildId}           cancel; anything already written is deleted

GET  /auth/google/status            { "mode", "configured", "connected" }
GET  /auth/google/start             browser sign-in (redirects to Google, back to /auth/google/callback)
POST /auth/google/code              { "serverAuthCode": "…" } from GoogleSignIn-iOS
```

Snapshot body: `name` (or `folderName`), `kind`, `members`, `decisions`, `options`, `itinerary`, `notes`, `messages`, and `context` (`year`, `budgetPerPerson`, `buyoutPrice`, `decision`, `votes`, `vehicle`, `location`). Muse chooses `calls` and `files`. A body that already includes both is still accepted, so the trip and car fixtures keep working. Ids on the `planned` event are UUIDs; later events echo them. Flight queries look like `AUS → HND, Mar 26 – Apr 4, 4 adults` and hotel queries like `Shinjuku, Mar 26 – 30, 2 rooms`.

`finished` includes the folder URL (`https://drive.google.com/drive/folders/…`) and each file's `webViewLink`. The app opens that URL. A mock URL uses a `huddle-` prefix and stays in the app.

The refresh token is stored in the backend's SQLite database (`google_tokens`, one account per backend for now).

## 5. Run it

**App (live keys required):**

```
cd backend
uv run --env-file .env uvicorn huddle.api:app --host 127.0.0.1 --port 8000
```

The iOS build setting `HUDDLE_BACKEND_URL` is `http://127.0.0.1:8000`, which the Simulator can reach. A build returns 503 until `SERPAPI_API_KEY` is set. It does not need a Muse key. Without a connected Drive account the same files are written locally and shown in the app.

**Live:**

1. Do section 1 and put the web client's id and secret in `backend/.env` (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`). Add `http://localhost:8000/auth/google/callback` as an authorized redirect URI.
2. Add `SERPAPI_API_KEY`. Muse is off; follow [RESTORE_MUSE.md](RESTORE_MUSE.md) before setting `MODEL_API_KEY`.
3. Restart the backend and open `http://localhost:8000/auth/google/start` once to connect Drive. `GET /auth/google/status` should say `"connected": true`.
4. Build a folder from the app. The finished event's `url` is the real, link-shared Drive folder. **Open in Google Drive** opens that URL.

The in-app Connect sheet still records a local display name. The refresh token comes from the browser flow above. Do not commit `.env`.

## Test checklist

- [ ] Sign-in requests only the `drive.file` scope.
- [ ] A build creates exactly one folder, named after the plan.
- [ ] Every Sheet row and Doc fact has a source.
- [ ] The car plan's files say "Simulated account data".
- [ ] The share link opens for someone without Huddle installed.
- [ ] Cancelling mid-build leaves no half-written files (or cleans them up).
