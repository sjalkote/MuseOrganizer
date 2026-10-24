# Huddle — design direction (v3)

Huddle is the decision layer for group chats you already have. It does **not** replace WhatsApp, iMessage, or Instagram. The chat stays messy and fun (that's the point of a friend chat). Huddle keeps the clean, shared Plan that everyone votes on.

## Structure (bottom tab bar)
- **Home**: greeting, "Up next" hero (countdown + progress), **Needs you** (to-dos across plans), **Start a plan** templates, latest Planner replies from your chats.
- **Plans**: one card per plan, each linked to a chat. Inside: **Plan** (decisions → color-banded options → itinerary → Calendar / Post update) and **Thread** (mirror of the real chat).
- **Shared**: reels, posts, links, and messages people shared into Huddle. One tap adds them to a plan as a votable option.
- **Apps**: how each integration works, what the Planner can see, and one action each.

## How the integrations work
| App | How Huddle connects | Status |
| --- | --- | --- |
| iMessage | `HuddleMessages` iMessage app. Sends a plan as an interactive card; friends tap to vote and the **same bubble updates** (MSSession). Vote counts travel in the message URL. | Built |
| Instagram | `HuddleShare` share extension. Share any reel/post → pick plan + category → lands in **Shared**. Instagram's API has no group chats, and sharing is how people use it anyway. | Built |
| WhatsApp | Same share extension for messages/links/exported chats. **Post update** opens WhatsApp with a ready summary (`whatsapp://send`), falling back to the share sheet. | Built |
| WhatsApp (next) | Planner as a WhatsApp Business contact via the Cloud API groups endpoints (small groups, users join by invite link). Needs a server + webhook. | Planned |
| Muse | Muse Spark (Model API) reasons over the thread; Huddle can be exposed to Muse as an MCP connector. | Planned |
| Google Drive | **Plan folders**: a manual "Build folder in Google Drive" button on each plan. SerpApi researches, Muse writes Sheets and Docs into one folder, and the link is shared to the chat. Simulated today; see `docs/GOOGLE_WORKSPACE_SETUP.md`. | UI built, API next |

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

## Visual rules
- **Canvas + panels**: screens sit on a gray `Palette.canvas`; every area is a white `Panel` with a colored `PanelHeader`. Areas never blend.
- **Category colors** (`Tint`): Flights blue, Stays amber, Things to do green, Money violet, Dates pink, Car orange. Each option category is a full color band. Indigo stays reserved for the Planner and the one primary action.
- **App colors** without logos: WhatsApp green, iMessage blue, Instagram pink, always with the app's name in words (`AppPill`).
- **Type**: 4 sizes (34 / 20 / 17 / 13), 2 weights. Values beat labels. Monospaced digits for numbers.
- **Spacing**: 8-pt grid. 16 between panels, 16–24 inside.
- **People**: photo when available, otherwise a colored monogram in the person's own tint.
- **Accessibility**: 44-pt targets, labels on icon-only buttons, color always paired with words or icons, light + dark defined in `Palette`.

## Build
Requires Xcode 26+. Generate the project from `project.yml`:
```
xcodegen generate
```
Schemes: `MuseOrganizer` (app), `HuddleMessages` (run it from Xcode to get Messages with a test conversation), `HuddleShare`.
For simulator builds from the command line with the App Group working: add `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`.
