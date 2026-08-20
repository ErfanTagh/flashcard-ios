# Recall Cards — iOS

A native SwiftUI client for the RecallCards flashcard app: study by flipping
cards, test yourself by typing answers, and track what you actually know.

It talks to the same Flask API as [the website](https://recallcards.net) — same
account, same cards, same progress — but it is a peer of the web client rather
than a wrapper around it. No web view, no shared code, no third-party
dependencies at all: Auth0 login, multipart uploads and the study logic are
written against the platform directly.

| | |
| --- | --- |
| **Backend** | [`flashcard-backend`](https://github.com/ErfanTagh/flashcard-backend) — Flask + MongoDB |
| **Web client** | [`flashcard-frontend`](https://github.com/ErfanTagh/flashcard-frontend) — React + Vite |
| **This** | SwiftUI, iOS 17+, no packages |

**Study** a collection one card at a time, flip to check, and mark each answer —
which feeds the same review history the website uses. **Test yourself** with a
typed quiz that is graded on the server, so a paraphrase counts the same
wherever you study. Cards can carry **pictures** as well as text.

- [Requirements](#requirements) · [Running it](#running-it) ·
  [Logging in](#logging-in--auth0) · [Servers](#servers)
- [What's in it](#whats-in-it) · [Design](#design) · [Layout](#layout)

## Requirements

- Xcode 16 or newer (the project uses a synchronized file group, so files added
  to `Flashcards/` are picked up without editing the project file)
- iOS 17.0 or newer on the device/simulator
- The backend running and reachable from the device

## Running it

1. Start the backend. From `flashcard-backend/`:

   ```
   docker compose -f docker-compose.dev.yml -f ../docker-compose.local.yml up -d --build
   ```

   That publishes the API on port **5055** on your Mac.

2. Open `Flashcards.xcodeproj`, pick a simulator, and run.

3. Tap **Log in**. The server defaults to **https://recallcards.net** — the
   deployed backend the website itself uses, where nginx proxies `/api/` to
   Flask. Nothing to configure for the normal case.

## Logging in — Auth0

Same identity provider, same tenant, same flow as the website: **Auth0
Universal Login, Authorization Code + PKCE**. The web client gets this from
`@auth0/auth0-react`; here it's `ASWebAuthenticationSession` driving Auth0's
`/authorize` and `/oauth/token` endpoints directly, so the project stays
dependency-free. Tokens live in the Keychain and are refreshed automatically;
the email from the ID token is what identifies your cards, exactly as the web
client uses `user.email`.

### One-time Auth0 dashboard setup

Two workable options. Both need the same two redirect URLs registered, on the
`dev-43bumhcy.us.auth0.com` tenant.

**Option A — reuse the existing SPA application** (fastest; nothing to change in
Xcode, since the Client ID prefilled in `Info.plist` is already that app). In
**Applications → your SPA app → Settings**, append to the existing
comma-separated lists:

- Allowed Callback URLs: `com.recallcards.flashcards://callback`
- Allowed Logout URLs: `com.recallcards.flashcards://logout`

A SPA app is a public client using Authorization Code + PKCE, which is exactly
what this app runs, so the flow itself is unchanged. The cost is that web and
iOS then share one `client_id`: Auth0 logs and Actions can't tell them apart,
and token lifetimes, rotation policy, connections and MFA are one shared
setting for two very different clients. If the SPA already has Refresh Token
Rotation on, that's fine — `AuthService` stores a rotated refresh token
whenever Auth0 returns one.

**Option B — a separate Native application.** **Applications → Create
Application → Native**, register the same two URLs on it, then copy its
**Client ID** into `Flashcards/Info.plist` under `Auth0ClientID`. Worth doing
once you want mobile sign-ins separated in the logs, or different token
lifetimes from the website.

Either way: **APIs → recallcards → Settings** → enable **Allow Offline
Access**, so Auth0 issues refresh tokens and you aren't sent back to the login
page every day.

`Auth0Domain` and `Auth0Audience` are already correct and match `AUTH0_DOMAIN`
and `API_AUDIENCE` in `main.py`. If you change `PRODUCT_BUNDLE_IDENTIFIER`,
update `Auth0Scheme` and `CFBundleURLSchemes` to match, and re-register the two
URLs above.

Auth0 [recommends claimed HTTPS URIs](https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation)
(Universal Links) over custom schemes for native apps, because another app can
register the same scheme. `ASWebAuthenticationSession` largely closes that hole
— the system hands the callback back to the session that opened it — so a
custom scheme is used here for setup simplicity. Switching to a Universal Link
later means changing `redirectURI` in `AuthConfiguration` plus an associated
domain entitlement.

### What the token is worth today

Every API call carries `Authorization: Bearer <access_token>`, and the audience
is set so Auth0 mints a real RS256 JWT for `recallcards` rather than an opaque
token. **The backend currently ignores it** — only `/api/token` sits behind
`@requires_auth`; `/api/cards`, `/api/review` and the rest trust the email in
the request. So Auth0 gates the app, not the data.

Closing that gap is a backend change: put `@requires_auth` on the card routes
and read the email from the verified token instead of the request body. The
client already sends everything that needs. Until then, treat the email as the
real credential.

### Developer sign-in

The login screen has a **Developer sign-in** link that skips Auth0 and
identifies you by an email you type — the counterpart to the web client's
`VITE_BYPASS_AUTH` dev mode. Handy before the Native app exists in Auth0. It
works only because the card endpoints don't check tokens.

## Servers

Both the sign-in screen and Settings have a **Known servers** menu, so
switching is one tap rather than typing a URL on a phone keyboard:

| Preset | URL | Works on |
| --- | --- | --- |
| Production | `https://recallcards.net` | Simulator and real iPhone |
| Local Docker | `http://localhost:5055` | Simulator only |

The web client can't tell you an address, incidentally: it calls bare
`/api/...` and lets Vite (dev) or nginx (prod) proxy to `http://backend:5000`,
a hostname that only resolves inside the Docker network. The phone has no
proxy, so it needs a real host.

For the local option, start the backend from `flashcard-backend/`:

```
docker network create web 2>/dev/null
docker compose -f docker-compose.dev.yml -f ../docker-compose.local.yml up -d --build
```

The override file is required, not optional — the plain dev compose publishes
5000 (taken by macOS Control Center) and 3001 (taken by the rush-website
container). The override moves them to 5055 and 3010. On a real iPhone use your
Mac's LAN address with the same port, on the same Wi-Fi; the app declares
`NSAllowsLocalNetworking` so plain HTTP to a local address is allowed.

Settings has a **Save and test connection** button that reports the real error
rather than failing silently.

## What's in it

Three tabs, following the shape of the data: a collection holds cards, so cards
live *inside* a collection rather than beside it, and progress sits one level
deeper still — inside the card list it describes.

| Tab | What it does |
| --- | --- |
| **Study** | One card at a time, tap to flip, swipe left/right to move. Mark **Got it** or **Needs review** — both post to `/api/review`. The collection you're in shows above the progress bar and doubles as a switcher. A segmented control in the header switches between **All**, **Review** and **New** with live counts, so studying just the flagged cards is one tap. Optionally shuffle. Finishing the last card shows a round summary. |
| **Collections** | Create (via the floating **New Collection** button), rename, delete, set the default. Tap one to open its cards. |
| **Profile** | Who you are, and log out. The server address sits one row deeper, with a connection test. |

Inside a collection:

- **Cards** — browse and search; tap to edit; swipe to delete or to flag/unflag
  for review. **Add Card** is a gradient button floating over the list, and the
  empty state offers the same action rather than pointing at a toolbar icon.
- **Progress** — a summary row at the top of the card list opens the full
  breakdown: accuracy, studied/unseen, known, flagged, and the flagged cards
  themselves.
- **Test yourself** — the typed-answer quiz, the counterpart of the website's
  `/quiz`. You're shown a term and type its definition. Answers post to
  `/api/review` exactly as flashcard answers do, so a quiz moves your progress
  and clears or sets review flags the same way a study round does.

  **Grading happens on the server**, at `POST /api/quiz/grade` — it decides
  what gets written to a card's review history, so having each client grade
  its own way would make one accuracy figure mean different things depending
  on where you studied. The web client calls the same endpoint. The rule
  (`grade_answer` in `main.py`):

  - punctuation, case, extra spacing and a leading article are ignored
  - short answers get a typo allowance in edits, using optimal string
    alignment so a transposition costs one edit rather than two
  - long answers are scored on word overlap (F1, so neither padding nor
    omitting half the answer scores well)
  - ≥ 0.9 is correct, ≥ 0.55 comes back as "close", below that is wrong

  Whatever it decides, one tap overrules it — in self-study the only judge who
  matters is the person studying. The answer is recorded when you move to the
  next question, not when you check, so an override changes the outcome rather
  than adding a second one (`/api/review` increments `seen` per call).

  `Models/QuizGrader.swift` is a line-for-line twin of the Python and is used
  only as a fallback when the server can't be reached, or is older than this
  endpoint. Grading offline beats not grading at all.

### Importing a deck from JSON

The Collections tab can build a deck from a JSON document, which is mostly a
way to have an AI write one. `POST /api/collections/import` does the work and
is deliberately forgiving about shape — `front`/`back` and `question`/`answer`
are accepted alongside `term`/`definition`, as is a bare list with no wrapper —
because the point is that whatever a model returned should work.

The screen shows the prompt rather than only offering to copy it: the prompt is
the only thing that explains what `TOPIC` means, and the card count is in there
to change before sending. JSON arrives by paste, by file, or typed. A ```` ```json ````
fence is stripped on the way in, since a model adds one occasionally however
firmly it was asked not to.

The prompt is word for word the one the web client shows, so a deck built on
one and pasted into the other behaves identically.

### Pictures on cards

A card's answer can be text, a picture, or both. Pictures are stored in
**GridFS**, not inside the user document — every card of every collection lives
in that one document, so embedding image bytes would make `/api/cards` drag
megabytes down the wire on every call and would hit MongoDB's 16MB ceiling soon
after. GridFS ships with pymongo, so this needed no new dependency and no
filesystem volume.

- `POST /api/images` — multipart upload, returns an id. Type whitelist, 5MB cap.
- `GET /api/images/<id>?email=` — serves the bytes, scoped to the uploader and
  cached hard, since the bytes behind an id never change.
- A card's `image` field holds the id, or null.

The app re-encodes what the photo picker returns
([`ImagePreparation`](Flashcards/Support/ImagePreparation.swift)): iPhone photos
are HEIC, which browsers cannot display, so a picture added on the phone would
be a broken image on the website. Downscaling to a 1600px JPEG fixes that and
keeps uploads well inside the limit.

Two details that matter:

- **`image` is only touched when the caller sends the key.** A client that knows
  nothing about pictures cannot wipe one by editing a card's text. In Swift this
  is a double optional: `.none` leaves it alone, `.some(nil)` clears it.
- **Replacing or deleting cleans up.** Overwriting a picture, deleting a card,
  or deleting a collection removes the GridFS files behind them, so nothing is
  orphaned.

A picture-only card has nothing to type, so the quiz leaves it out and
`/api/quiz/grade` refuses it rather than grading against an empty string.

### Studying and browsing are separate

A study session owns the collection it is running over. Opening a different
collection in the Collections tab changes what you're *browsing* and nothing
else — a run in progress is untouched. To study something else, use the
collection pill above the progress bar inside Study; the checkmark in the
Collections list marks what you're browsing.

The session follows your account's default collection until you pick one
explicitly, after which it stays put.

This is why `LibraryStore` caches cards per collection (`cardsByCollection`)
rather than holding one "current" set: two screens legitimately want different
collections at once. It also means switching shows the previous contents
instead of blanking while a fetch runs.

### End of a round

Answering the last card (or tapping **Finish**) ends the session and shows how
it went: accuracy for that round, and how many were answered, right, and
missed. `StudySession` keys outcomes by term, so going back and re-answering
corrects the tally instead of double-counting.

Two ways onward:

- **Review the flagged cards** — everything currently flagged in the
  collection, not merely what was missed this round, since that is what "needs
  review" means to the backend. Disabled when nothing is flagged.
- **Study the whole collection again** — a fresh pass over everything.

Round statistics are deliberately separate from the per-card counters shown in
Progress: those are lifetime figures from the server, this is "how did I just
do".

## Design

Ported from the web app rather than reinvented, so the two look like one
product.

**Palette.** [`Support/Theme.swift`](Flashcards/Support/Theme.swift) carries the
same tokens as `flashcard-frontend/src/index.css` — `:root` for light, `.dark`
for dark — written with the identical HSL numbers rather than hand-converted
hex, via a `Color.hsl` helper (SwiftUI's own initialiser is HSB, a different
model). Verified against a browser's conversion: `primary` resolves to
`#7C3BED`, `accent` to `#EF5D8D`, and so on for every token. If a colour
changes on the web, change the matching line here.

The one addition is `Theme.success` for a correct answer — the web palette has
no token for that — and it's marked as such in the file.

**Logo.** It leads the intro and the sign-in screen, and sits in the navigation
bar of every signed-in screen — the same place the website's navbar keeps it.
[`Support/RecallCardsLogo.swift`](Flashcards/Support/RecallCardsLogo.swift)
redraws `public/recallcards-icon.svg` as SwiftUI shapes in the SVG's own 120×120
coordinate space, so it stays checkable against the original: the gradient
rounded square (#8B5CF6 → #EC4899) with the white open-book mark. Being paths
rather than an image, the two pages can be trimmed and swung independently,
which is what the intro animates.

**Intro.** [`Views/LaunchIntroView.swift`](Flashcards/Views/LaunchIntroView.swift)
runs once per cold launch, about 1.9s: the tile springs in, the book strokes
draw themselves, the pages swing shut onto the spine, and the gradient wordmark
rises underneath. Tap to skip. Under Reduce Motion it snaps to the finished
state, holds briefly, and leaves.

**App icon.** Generated at 1024×1024 from the same geometry by
[`Tools/MakeIcon.swift`](Tools/MakeIcon.swift), a standalone CoreGraphics script
— no Xcode needed:

```
swift Tools/MakeIcon.swift Flashcards/Assets.xcassets/AppIcon.appiconset/Icon-1024.png
```

### UX decisions worth knowing

- **Hidden actions are mirrored.** Every swipe action on a row (rename, delete,
  flag, make default) is also in a long-press context menu, because a swipe
  advertises nothing. Creating is a labelled gradient button, not a toolbar
  glyph.
- **The study controls don't move.** The answer row has a fixed height, so
  replacing *Show answer* with the two answer buttons can't resize the card
  under the reader's eyes.
- **Answers are felt, not just seen.** Answering fires a haptic — success or
  warning — because your attention is already on the next card, not the button.
- **Empty states say which emptiness.** "No cards", "nothing flagged", "no
  search results" and "not loaded yet" are four different situations and each
  gets its own message, with the obvious action attached where one exists.
- **Rows are buttons.** Tap handling used `onTapGesture`, which gives VoiceOver
  no button trait. Rings are hidden from VoiceOver and replaced with a spoken
  label and value, rather than being read as decoration.

## Layout

```
Flashcards/
  FlashcardsApp.swift        app entry, builds settings + store
  Models/Card.swift          Card, StudyProgress, ReviewOutcome
  Models/StudyDeck.swift     the ordered study queue and its filters
  Networking/APIClient.swift every backend call, bearer token attached
  Networking/AuthService.swift        Auth0 login / logout / refresh
  Networking/AuthConfiguration.swift  Auth0 values, read from Info.plist
  Networking/PKCE.swift      code verifier + challenge (S256)
  Networking/Keychain.swift  where the tokens live
  Networking/ServerSettings.swift  the backend base URL (UserDefaults)
  Stores/LibraryStore.swift  single source of truth; all mutations go here
  Support/Theme.swift        the web palette, ported token for token
  Support/RecallCardsLogo.swift  the app mark as SwiftUI shapes
  Support/FlipCardView.swift the flip animation
  Views/                     one file per screen, plus LaunchIntroView
```

Two backend quirks the client is built around, both handled in `APIClient`:

- **Failures arrive as HTTP 200** with `{"status": 4xx, "error": "..."}` in the
  body, so the status code alone never tells you whether a write worked. Every
  write checks the payload too.
- **Writes rewrite the whole card document** server-side (renames, review-history
  merges), so `LibraryStore` refetches after a mutation instead of guessing the
  new state locally. The one exception is recording a review, which patches the
  single returned card so the study session doesn't stall between answers.

## Not included

- Push notifications, offline caching, and unit tests.
- Biometric re-auth on launch. The Keychain item uses
  `kSecAttrAccessibleAfterFirstUnlock`, so the session survives restarts without
  a further prompt.
