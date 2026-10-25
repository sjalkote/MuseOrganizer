# NxT

*what's next?*

NxT is the decision layer for a group that already has a chat. The thread stays in iMessage, WhatsApp, or Instagram. NxT keeps the shared plan: the options, the votes, the budget, and the one thing the group should do next.

## A plan

Someone starts a plan from a sentence. “Japan in late March, four of us, under $2,000.” “Should we buy out the RAV4 lease?” “Friday dinner, six people, one vegan.”

Muse reads that request and lays out the tabs that fit it, up to five:

| The plan is… | The tabs |
| --- | --- |
| A flight trip | Overview · Flights · Stays · Do · Money |
| A road trip | Overview · Route · Stays · Do · Money |
| A train or bus trip | Overview · Getting there · Stays · Do · Money |
| Dinner | Overview · Places · Who's in |
| An event | Overview · Places · Who's in · Do · Money |
| A big purchase | Overview · Options · Numbers · Prices |

Money shows up once the plan has a budget. Overview is the answer screen: **What's next**, one button to the vote that is waiting, the budget meter, where things stand, and the chips Muse understood (“6 people”, “Vegan option”, “Step-free only”).

You see who voted after you vote. Before that, you see the count.

## Muse

Muse Spark searches live prices through SerpApi (flights, hotels, maps, shopping) and writes a one-line trade-off on each option. In the thread, `@Muse` answers from those results and adds what it finds to the right tab.

Muse also watches the prices a plan might pay. On a schedule it re-checks each one. When a price moves, Muse calls **Book now**, **Wait**, or **Keep watching**, with a reason drawn from the history, the typical range, and how close the date is. A **Book now** call becomes a notification. Tap it and the plan opens. The Budget Tracker sheet picks up the new number.

## Where the group already talks

- **iMessage.** An iMessage app sends the plan as a card. Friends vote on the card, and the same bubble updates.
- **Instagram and WhatsApp.** The share extension takes a reel, a post, a link, or a message and files it on the plan. Shared items live under Messages, next to the chats. Posting an update opens WhatsApp with a summary ready to send.
- **Home, Plans, Messages.** Home shows the next plan, Muse’s latest price call, and who the plan needs. Plans is one card per plan. Messages is every group’s thread, with search and unread dots.

## The folder

When the group has decided, **Build folder in Google Drive** researches the plan, writes Sheets and Docs, and puts them in one folder named after the plan. A trip gets a budget, a day-by-day, and places to stay and eat. A car gets market prices, dealer prep, and a decision summary. The folder link goes back into the group chat.

NxT asks Google only for `drive.file`: it creates and edits the files it makes, and the group chooses who receives the link.

## Run

The app is an iOS project (Xcode 26+). From `MuseOrganizer`:

```
xcodegen generate
```

Open `MuseOrganizer.xcodeproj`. Schemes: `MuseOrganizer` (the app), `HuddleMessages` (the iMessage app), `HuddleShare` (the share extension).

The backend serves live search, Muse, price watches, and Drive:

```
cd backend
uv run --env-file .env uvicorn huddle.api:app --host 127.0.0.1 --port 8000
```

Copy `backend/.env.example` to `backend/.env` and add the keys. The Simulator reaches the backend at `http://127.0.0.1:8000`. Connect Drive once at `http://localhost:8000/auth/google/start`. Details are in `docs/GOOGLE_WORKSPACE_SETUP.md` and `docs/RESTORE_MUSE.md`.
