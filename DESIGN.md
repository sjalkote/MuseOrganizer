# NxT (formerly Huddle) — design direction

Tagline: *what's next?*

Huddle is the decision layer for group chats you already have. It does **not** replace WhatsApp, iMessage, or Instagram. The chat stays messy and fun (that's the point of a friend chat). Huddle keeps the clean, shared Plan that everyone votes on.

## Brand and intro
- **Logo** (`DesignSystem/Logo.swift`): "NxT" in New York serif (italic, lighter x) on the dusk mesh gradient shared with plan covers and Muse. The app icon is rendered from this same view by `scripts/render-icon.swift` (standard, dark, tinted).
- **Intro** (`Features/Intro/IntroView.swift`, ~2 s, tap to skip): the mark blurs in and springs into place, a soft shine crosses it, *what's next?* fades up, then it lifts away while Home fades up from 97% scale. The launch screen uses the same paper color (`LaunchBackground`), so launch → intro → Home never flashes. Reduce Motion gets a plain fade.

## Structure (bottom tab bar: Home · Plans · Messages)
- **Home**: greeting, the next plan as a cover, Muse's most important price call, **Needs you**, **Start a plan**.
- **Plans**: one card per plan. A plan is one screen (`PlanScreen`): compact cover → one-line Muse price strip → **tabs Muse picks from the request** (`PlanTabs.swift`), one at a time, pinned while scrolling. The chat is never a tab; the toolbar's bubble button jumps to it.
- **Messages** (like Instagram's DMs): every group's chat with unread dots and search; a **Chats | Shared** switch holds what people shared in from Instagram/WhatsApp.

### Tabs adapt to the request (`PlanSetup.infer`, max 5)
| Request looks like | Tabs |
| --- | --- |
| Flight trip | Overview · Flights · Stays · Do · Money |
| Road trip ("driving") | Overview · Route · Stays · Do · Money |
| Train / bus | Overview · Getting there · Stays · Do · Money |
| Dinner | Overview · Places · Who's in |
| Event (birthday, bachelorette) | Overview · Places · Who's in · Do · Money |
| Big purchase (car) | Overview · Options · Numbers · Prices |
Money appears only once there's a budget. Overview is the answer screen: **What's next** with one button to the tab that needs a vote, the budget meter, where things stand, and the chips Muse understood ("6 people", "Vegan option", "Step-free only").
Based on a market scan (Wanderlog, Troupe, Airbnb, Instagram, Partiful, Polarsteps) and six persona reviews (teen, college, bachelorette planner, busy parent, retired couple, nonbinary international student). No competitor swaps tabs by plan type.

## How the integrations work
| App | How Huddle connects | Status |
| --- | --- | --- |
| iMessage | `HuddleMessages` iMessage app. Sends a plan as an interactive card; friends tap to vote and the **same bubble updates** (MSSession). Vote counts travel in the message URL. | Built |
| Instagram | `HuddleShare` share extension. Share any reel/post → pick plan + category → lands in **Shared**. Instagram's API has no group chats, and sharing is how people use it anyway. | Built |
| WhatsApp | Same share extension for messages/links/exported chats. **Post update** opens WhatsApp with a ready summary (`whatsapp://send`), falling back to the share sheet. | Built |
| WhatsApp (next) | Planner as a WhatsApp Business contact via the Cloud API groups endpoints (small groups, users join by invite link). Needs a server + webhook. | Planned |
| Muse | Muse Spark (Model API) writes each option's trade-off, answers @Planner in the thread from live prices, and runs the **price watch** (below). Without `MODEL_API_KEY` the backend uses a labeled rule-of-thumb stand-in. | Built |
| Google Drive | **Plan folders**: a manual "Build folder in Google Drive" button on each plan. SerpApi researches, Muse writes Sheets and Docs into one folder, and the link is shared to the chat. Simulated today; see `docs/GOOGLE_WORKSPACE_SETUP.md`. | UI built, API next |

## Muse price watch (backend/huddle/watch.py)
Like Honey for group bookings. Everything a plan might pay for (flight routes, hotels, used-car listings) becomes a watch:
1. **SerpApi** re-checks the price on a schedule (`HUDDLE_WATCH_INTERVAL`, default 6 h; fresh searches, never cached). Flights start with Google Flights' own 60-day price history.
2. When a price moves at least 3% and $5, **Muse Spark** decides *book now*, *wait*, or *keep watching* and writes a one-line reason from the history, typical range, and days until the trip.
3. The plan's **Budget Tracker** sheet in Drive is rewritten with the new number and total.
4. The app polls for new calls (and re-checks on background refresh) and sends a **notification** only for *book now*, grouped per plan. Tapping it opens the plan.
Endpoints: `POST /plans/{id}/board` (live options + watches), `GET|POST /plans/{id}/watches`, `POST /plans/{id}/watches/check`, `GET /alerts?since=`, `POST /plans/{id}/ask`, `GET /status`. With no backend URL the app shows demo watches labeled "Demo data".

Shared state between the app and extensions lives in the App Group `group.com.sjalkote.MuseOrganizer` (`Shared/SharedStore.swift`). Deep links: `huddle://plan/<id>` and `https://huddle.app/p/<id>`.

## Chat psychology we follow
- **Jakob's law**: the Thread looks like every chat app (theirs left, yours right, box at the bottom). Return sends, single-line composer, no formatting bar, so it reads as casual chat.
- **Read receipts go both ways**: you see *who* voted only after you vote. Before that, just the count. Nobody can lurk with an advantage.
- **No surveillance**: no "last seen", no "Sam hasn't opened the plan". Votes are the only signal.
- **Planner speaks only when asked**: it posts only when @mentioned or when you tap Post. One card per request, never a stream (like WhatsApp's forwarding limits).
- **One-tap answers** (Uber's thumbs-up idea): votes happen inside the iMessage bubble without opening Huddle.
- **Sharing machine** (Instagram's idea): the share sheet is a first-class way to add options.
- **Typing indicator**: humans don't get one in the mirror. The Planner shows what it's *doing* ("Searching Google Hotels…"), not that it's typing.
- **Chat is the stream, the Plan is the vault** (Discord vs Slack): replies stay in the chat; decisions are saved and searchable in the Plan.

## Visual rules (v4: after Airbnb, Apple Invites, Partiful, Hopper)
- **Warm paper, ink first** (Airbnb): `Palette.canvas` is warm off-white, text is near-black, primary buttons are ink. One vermilion accent (`Palette.accent`) marks selection and progress, nothing else.
- **Covers, not dashboards** (Apple Invites / Partiful): each plan has a mesh-gradient cover (`PlanCover`, `Plan.cover`) with its name in the serif display face and frosted `GlassChip`s. Glass is tinted dark so white text always reads.
- **Muse has its own identity**: the amber-to-rose `MuseMark` and gradient appear only where Muse acts (price watch, its replies, its calls on Home). No sparkles.
- **One clear verdict** (Hopper): price watch leads with "Book now" / "Wait" / "Keep watching", then the headline, then a full-width price line with low · now · high.
- **Fewer boxes**: cards float on the paper with big soft corners (`Radius.l` 26, covers 32) and one warm shadow (`cardShadow()`), gone in dark mode. Section titles sit on the canvas in serif.
- **Airbnb-style tabs** for Flights / Stays / To do: glyph over name, a sliding ink underline, and each tab's decided / voting / open status.
- **Type**: New York (serif) for names and section titles (`.display`, `.title`), SF Rounded for big numbers, SF for everything else. Uppercase tracked eyebrows (`eyebrowStyle()`).
- **Icons**: hierarchical SF Symbols in soft circles (`TintTile`), never loud colored squares. Category colors stay muted so covers and Muse carry the color.
- **Motion**: springs (`Motion`), cards sink slightly on press, numbers roll (`numericText`), tab glyphs bounce on select.
- **Accessibility**: 44-pt targets, labels on icon-only buttons, color always paired with words or icons, light + dark defined in `Palette`.

## Build
Requires Xcode 26+. Generate the project from `project.yml`:
```
xcodegen generate
```
Schemes: `MuseOrganizer` (app), `HuddleMessages` (run it from Xcode to get Messages with a test conversation), `HuddleShare`.
For simulator builds from the command line with the App Group working: add `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`.
