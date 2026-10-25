# Turn Muse Spark back on for plan folders

Folder builds do not call Muse. A local chooser picks the SerpAPI searches and the files, and the Daily intro and decision summary stay as the facts-only draft. SerpAPI is still required. Google Drive stays optional: without it, the same files show up in the app.

Do this when a `MODEL_API_KEY` exists. Do not commit `backend/.env` or paste the key into chat.

## 1. Key

1. Sign in at [dev.meta.ai](https://dev.meta.ai). The Model API is US-only.
2. Create a key on the API keys tab. Keys look like `LLM_…`.
3. In `backend/.env` set `MODEL_API_KEY` and `MUSE_ENABLED=1`. Leave `MUSE_SPARK_MODEL=muse-spark-1.3`.
4. Credits, if a program granted them, show on that dashboard under Billing and Usage. The in-app “25 credits this week” meter is a local counter, not that balance.
5. Confirm the key with one request before a Simulator build:

```
curl https://api.meta.ai/v1/chat/completions \
  -H "Authorization: Bearer $MODEL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"muse-spark-1.3","messages":[{"role":"user","content":"Reply with the word ready."}]}'
```

A short reply means the key is usable. Restart the backend after editing `.env`. The client in `backend/huddle/muse.py` is created at import (`muse = Muse(KEY) if KEY else MockMuse()`), so a key added to a running process is ignored.

```
cd backend
uv run --env-file .env uvicorn huddle.api:app --host 127.0.0.1 --port 8000
```

## 2. What is already wired

`builds_use_muse()` in `backend/huddle/workspace.py` is the switch. It is true only when both `MUSE_ENABLED=1` and `MODEL_API_KEY` are set.

- `choose_outputs` then calls `muse.select_outputs` instead of `heuristic_outputs`.
- `polish` then calls `muse.explain` for the Daily intro and the decision summary. On any error it keeps the draft.

`Muse.select_outputs` in `backend/huddle/muse.py` posts to `https://api.meta.ai/v1/chat/completions` with tool `select_outputs` (`SELECT_SYSTEM`, `SELECT_TOOL`). The model must return that tool call. `Muse.explain` rewrites a draft and may use only numbers present in the facts.

No new file list is required. Keep the validation in `choose_outputs`:

- Drop unknown engines and roles. Engines: `google`, `google_flights`, `google_hotels`, `google_maps`, `google_shopping`. Roles are the keys of `ROLES`.
- `_keep_role` drops a sheet the plan cannot fill. A plain `google` search is not enough for a budget. `daily` needs a flight or hotel search. If nothing usable remains, the build fails with “Muse did not choose any files this plan can fill”. Do not substitute `heuristic_outputs` on that failure.
- Muse does not invent prices. Numbers written into a file come from SerpAPI or from the plan.
- A body that already includes `calls` and `files` skips `choose_outputs`. Leave that path so the trip and car fixtures stay valid.

`heuristic_outputs` is the behavior to match: movie night gets Showtimes and Evening plan, a car gets comparison, market, and decision (plus dealer when the plan mentions a dealer), a trip gets Budget Tracker, Daily, and Places, an outing gets a Plan doc, a shopping list gets one sheet, anything else gets an Overview doc.

## 3. Checks

Pytest stays offline. `backend/tests/conftest.py` sets `HUDDLE_OFFLINE=1` and removes `MODEL_API_KEY` before import. Do not point pytest at the live key.

```
cd backend
uv run pytest -q
```

`test_muse_cannot_invent_a_budget_or_itinerary` sets `MUSE_ENABLED=1` and stubs `select_outputs`. It must still fail the build when Muse asks for a budget and a daily doc on a notes-only plan.

With the backend restarted and both flags set, build Japan, the car, and Friday movie night from the app. The first SSE event is `planned`, and its calls and files should be ones Muse chose, not a crash from a missing key. Prices must not be labeled “(mock)”. That means SerpAPI ran. Delete the matching files under `backend/fixtures/serpapi/` first if a previous live response should not be replayed.

`POST /plans/{id}/workspace` returns 503 only when `SERPAPI_API_KEY` is missing. Do not put `MODEL_API_KEY` back on that check. A missing Muse key with `MUSE_ENABLED` unset keeps the local chooser.

## 4. Other Muse call sites

`backend/huddle/engine.py` calls `muse.explain` (`safe_explain`) and `muse.extract` for the private-constraints session. Those follow the import-time client, not `MUSE_ENABLED`. Once `MODEL_API_KEY` is present at startup, those calls are live even if folder builds stay on the local chooser. Gate them with `builds_use_muse()` if they should wait too.

With `MUSE_ENABLED=1` and `MODEL_API_KEY`, three more calls go live:

- `POST /plans/setup` asks Muse for the tabs (`record_setup`). Unknown tabs are dropped, money is dropped when the plan has no budget, and chips that are not in the plan text are dropped. The app falls back to `tabs.infer` if Muse declines.
- `POST /plans/{id}/ask` asks Muse which module to run (`choose_module`: places, price, flights, or web), SerpAPI runs that search, then Muse writes the reply from those results only.
- Questions about prices already being watched still answer from the watches.

With no backend URL, the replies in `PlanStore.runPlanner` stay scripted, and tabs fall back to `PlanSetup.infer`.

The build sheet copy (“Choosing the searches…”, “Writing …”) does not name Muse. Put that wording back only if the live call is actually on.
