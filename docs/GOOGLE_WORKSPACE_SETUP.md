# Plan folders: going from simulated to real

When a group has decided, anyone can tap **Build folder in Google Drive** on a plan. Huddle then:

1. **Researches** every detail with SerpApi (flights, hotels, food, transit, entry rules, car listings, dealer info…).
2. **Writes** it up with Muse Spark as Google Sheets (budget, comparisons) and Google Docs (itinerary, guides).
3. **Files** everything into one new Drive folder named after the plan.
4. **Shares** the folder link back into the group chat (iMessage / WhatsApp) or anywhere else.

Today the app uses `SimulatedWorkspaceService`: same UI and events, realistic data, no network. This doc covers swapping in the real thing.

## Architecture

```
iPhone (Huddle)                     Huddle backend                         External
────────────────                    ──────────────                         ────────
Build folder tap ──POST /plans/:id/workspace──▶ start build ──▶ Muse Spark (plans research as tool calls)
                                                    │                 │
progress UI ◀──SSE /builds/:id/events──── events ◀──┤                 ├─▶ SerpApi (one call per tool call)
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

Use the Meta Model API (it's OpenAI-compatible, so any OpenAI SDK works by changing the base URL). Check Meta's developer docs for the current base URL and model name. Give it these tools and let it drive the build:

| Tool | Does |
| --- | --- |
| `serp_search(engine, params)` | Calls SerpApi, returns trimmed JSON |
| `create_folder(name)` | Drive `files.create` with `mimeType: application/vnd.google-apps.folder` |
| `create_sheet(folder_id, title, columns, rows)` | Sheets `spreadsheets.create` + `values.update`, then move into the folder |
| `create_doc(folder_id, title, blocks)` | Docs `documents.create` + `batchUpdate` (insertText, heading styles), then move into the folder |
| `share_folder(folder_id)` | Drive `permissions.create` with `type: anyone, role: reader`, returns the link |

System prompt essentials: use only data from tool results; cite the source on every row; mark simulated account data as simulated; one folder per plan; plain, short copy.

## 4. Backend contract

```
POST /plans/{planId}/workspace     body: plan snapshot (members, decisions, chosen options)
  → 202 { "buildId": "…" }

GET  /builds/{buildId}/events      text/event-stream
  event: researching   data: { "id": "…", "engine": "google_flights", "query": "…" }
  event: researched    data: { "id": "…", "result": "14 itineraries", "duration": 2.1 }
  event: writing       data: { "id": "…", "name": "Budget", "kind": "sheet" }
  event: wrote         data: { "id": "…", "summary": "7 rows · totals" }
  event: finished      data: { "folderName": "Japan Trip 2027", "url": "https://drive.google.com/…", "files": [ … ] }
```

These map one-to-one to `BuildEvent` in `MuseOrganizer/Integrations/WorkspaceService.swift`.

## 5. Switch the app over

1. Implement `GoogleWorkspaceService.build(_:)`: POST to start, then read the SSE stream and yield `BuildEvent`s.
2. In `AppModel`, set `workspaceService = GoogleWorkspaceService(baseURL: …)`.
3. Replace the simulated sign-in in `ConnectGoogleSheet` with GoogleSignIn.
4. In `FolderView`, change **Open in Google Drive** to open `workspace.url` instead of showing the demo alert.

## Test checklist

- [ ] Sign-in requests only the `drive.file` scope.
- [ ] A build creates exactly one folder, named after the plan.
- [ ] Every Sheet row and Doc fact has a source.
- [ ] The car plan's files say "Simulated account data".
- [ ] The share link opens for someone without Huddle installed.
- [ ] Cancelling mid-build leaves no half-written files (or cleans them up).
