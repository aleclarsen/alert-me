# alert-me

A tiny macOS menu-bar app that connects to your Google Calendar and plays a
full-screen animation the moment a meeting starts — so you never miss the start
of a call again.

- **Native Swift** menu-bar agent (no Dock icon, no window).
- **Bring-your-own Google OAuth** — nothing is hardcoded. Each user supplies
  their own OAuth client, tokens are stored in the macOS **Keychain**, and the
  flow uses **PKCE** on a loopback redirect. Anyone can use it securely.
- **Lottie animation** overlay that's a single JSON file you can swap out.

## Requirements

- macOS 13+
- Xcode / Swift toolchain (Swift 5.9+)

## Build & run

```bash
# Quick dev run (menu-bar agent appears in the status bar):
swift run AlertMe

# Or build a distributable AlertMe.app bundle:
./scripts/build-app.sh
open AlertMe.app
```

A 🔔 icon appears in your menu bar. First launch writes a config template to
`~/Library/Application Support/AlertMe/config.json`.

## Running & debugging locally

For day-to-day development, run straight from the terminal so you can see logs
and errors on stdout:

```bash
# Build + run the menu-bar agent, attached to the terminal:
swift run AlertMe

# Verify the bundled animation resolves & parses (no UI, exits 0/1):
swift run AlertMe --check

# Debug build path, if you want to run the binary directly:
swift build && .build/debug/AlertMe
```

Tips for testing it out:

- **Preview the overlay without a meeting:** click the 🔔 menu → **Test
  animation**. This is the fastest way to iterate on the animation or overlay
  window without wiring up Google.
- **Force a calendar refresh:** menu → **Sync now**. The menu's top line shows
  the last sync status (e.g. `Synced 3 upcoming • 10:42 AM`) or the last error.
- **Shorten the feedback loop:** set `pollIntervalSeconds` low (e.g. `15`) in the
  config while testing, then create a calendar event a minute out to watch it
  fire. Remember to restart the app after editing config.
- **Open in Xcode** for breakpoints/debugging: `xed .` (Xcode opens the Swift
  package directly; pick the `AlertMe` scheme and Run).
- **See logs from the bundled app** (when launched via `open AlertMe.app`):
  `log stream --predicate 'process == "AlertMe"' --level debug`, or run the
  binary inside the bundle directly: `./AlertMe.app/Contents/MacOS/AlertMe`.

### Resetting local state

```bash
# Wipe config (a fresh template is recreated on next launch):
rm ~/Library/"Application Support"/AlertMe/config.json

# Remove the stored OAuth refresh token from the Keychain (forces re-sign-in):
security delete-generic-password -s com.alertme.oauth -a google-refresh-token
```

> First launch of an ad-hoc/unsigned `AlertMe.app` may be blocked by Gatekeeper.
> Right-click the app → **Open**, or run via `swift run` during development.

## Connecting Google Calendar (one-time setup)

The app does not ship with any Google credentials. You create your own free
OAuth client so the connection is yours and nothing sensitive is baked into the
app:

1. Go to the [Google Cloud Console](https://console.cloud.google.com/), create
   (or pick) a project.
2. Enable the **Google Calendar API** for that project.
3. Configure the **OAuth consent screen** (External is fine; add your own Google
   account as a Test user).
4. Create an **OAuth client ID** of type **Desktop app**.
5. Copy the **Client ID** (and **Client secret**, which desktop clients are
   issued) into your config file:

```jsonc
{
  "clientId": "YOUR_CLIENT_ID.apps.googleusercontent.com",
  "clientSecret": "YOUR_CLIENT_SECRET",
  "scopes": ["https://www.googleapis.com/auth/calendar.readonly"],
  "pollIntervalSeconds": 300,
  "leadTimeSeconds": 0,
  "animationPath": null
}
```

Open the config quickly from the menu: **Open config file…**. Then choose
**Sign in to Google…**. Your browser opens for consent; the app captures the
redirect on a temporary `127.0.0.1` port, exchanges it for tokens, and stores
the refresh token in your Keychain. Access tokens stay in memory only.

> Security notes: the loopback + PKCE flow is Google's recommended pattern for
> installed apps. The client secret for a Desktop client is not treated as
> confidential, but it is never committed — it lives only in your local config
> (which is git-ignored).

## Configuration

| Key | Meaning |
| --- | --- |
| `clientId` | Your Google OAuth Desktop client ID (required). |
| `clientSecret` | Your Google OAuth Desktop client secret. |
| `scopes` | OAuth scopes. Read-only calendar is the default and enough. |
| `pollIntervalSeconds` | How often to re-sync the calendar (default 300). |
| `leadTimeSeconds` | Fire the overlay N seconds *before* start (0 = at start). |
| `animationPath` | Absolute path to a replacement Lottie JSON, or `null` for the bundled default. |

## Replacing the animation

The overlay plays a [Lottie](https://airbnb.io/lottie/) JSON animation. To use
your own, set `animationPath` in the config to any `.lottie`-style JSON file:

```json
"animationPath": "/Users/you/Downloads/my-animation.json"
```

Free, openly-licensed animations are available at
[LottieFiles](https://lottiefiles.com/) (check each file's license). The bundled
default (`Sources/AlertMe/Resources/train-animation.json`) is a little steam
train that chugs across the top of the screen, authored for this project and
MIT-licensed.

Use **Test animation** in the menu to preview the current animation any time.

## Menu actions

- **Sign in to Google… / Sign out** — manage the calendar connection.
- **Sync now** — force an immediate calendar re-sync.
- **Test animation** — preview the overlay.
- **Open config file…** — edit settings.
- **Quit alert-me**.

## How it works

| File | Responsibility |
| --- | --- |
| `Config.swift` | Loads/saves the user-editable JSON config. |
| `Keychain.swift` | Stores the OAuth refresh token securely. |
| `LoopbackServer.swift` | Catches the OAuth redirect on `127.0.0.1`. |
| `GoogleAuth.swift` | PKCE OAuth flow + access-token refresh. |
| `CalendarService.swift` | Lists upcoming primary-calendar events. |
| `MeetingScheduler.swift` | Polls and arms a timer per meeting. |
| `OverlayController.swift` | Transparent click-through window + Lottie. |
| `AppDelegate.swift` / `main.swift` | Menu-bar UI and entry point. |

## License

MIT.
