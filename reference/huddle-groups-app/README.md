# Huddle Groups prototype (reference only)

Sopan's SwiftUI prototype: private per-person budgets, join-by-code groups, and car
cards driven by `backend/huddle/api.py`. It isn't compiled into the app target
(type names like `Plan`, `Message`, and `HomeView` clash with the main app).

Ideas worth porting into the main app as features:
- Private budget thread with Muse, so nobody says their number out loud
- Join a decision with a short code
- Car cards with cash / finance / lease breakdown (`backend/huddle/finance.py`)
