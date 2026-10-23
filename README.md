# Agent Guild for Android

An app that connects to a computer running [Agent Guild](https://github.com/oddessentials/agent-guild) and shows its Cards and Yard, as [agent-guild-apple](https://github.com/oddessentials/agent-guild-apple) does on iPhone, iPad and Apple Vision Pro.

This repository holds the plan, the emulator tools and a verification probe. The app itself is the next step: see [Next: the first version](#next-the-first-version).

## The approach

The app shows the manager's own page in a `WebView`, loaded from the manager's remote-access address with `#token=`. It adds what the page cannot do itself: keeping a list of computers, signing in, and opening links outside.

- **Never copy the page into the app.** The manager answers 403 to `Origin: null` and to custom schemes (`checkRequestSource` in agent-guild's `src/manager/server.mjs`), and a copy would drift from the manager it talks to. Loading the page from the manager keeps the app in step with every manager version.
- **Every way of running Agent Guild runs the same Node manager**, so there is one kind of server to connect to.
- **No Google Play services.** The app is sideloaded, including onto devices without them.

## How the app reaches a computer

- The manager listens on `127.0.0.1` only and refuses a `Host` outside its allowlist. An address is a Tailscale Serve route (`https://<computer>.<tailnet>.ts.net[:port]`, set up in Agent Guild's **Settings → Remote access**) or a reverse proxy saved there. Tailscale Serve's certificate is a public one for the `ts.net` name.
- **Remote access → Connect another device** shows the sign-in link as a QR code and as text.
- `GET /api/v1/health` needs no token. Every other request carries `Authorization: Bearer <token>`. See agent-guild's `docs/api.md`.

### The sign-in link

The manager's page builds the link in `web/remote-access.js`: the remote-access address with the fragment set by `new URLSearchParams({ token })`, so `https://<host>[:<port>]/#token=<token>`. The manager creates the token as 24 random bytes in lowercase hex, and accepts a saved token that matches `^[a-f0-9]{32,}$` (`src/manager/config.mjs`).

The app's parser accepts a link only when every rule holds, and otherwise says it isn't an Agent Guild sign-in link:

1. Leading and trailing whitespace is ignored. The rest parses as an absolute URL.
2. The scheme is `https`. Debug builds also accept `http://127.0.0.1:<port>`, for the scratch manager below; release builds never do.
3. There is a host, and no user name or password.
4. The path is empty or `/`, and there is no query.
5. The fragment is exactly one `token=<value>` pair, and the value matches `^[a-f0-9]{32,}$`. Anything else in the fragment, a second `token`, or percent-encoding in the value makes the link ambiguous, and it is refused.

The saved address is `https://<host>[:<port>]` with the host in lowercase, and no `:443`. Before saving, the app checks `GET <address>/api/v1/info` with the bearer token, a 10-second timeout and no redirects, and accepts it only when the answer is 200 with `"name": "agent-guild"`.

The token never appears in a log line, a crash report, a Custom Tab, or any URL other than the one the `WebView` loads. The page removes it from its own address and history once loaded. Any URL the app logs has its fragment removed.

## The page in the app: the bridge contract

agent-guild's `docs/api.md`, **The page in the Agent Guild app → Android**, is the contract. In short:

- The app registers a web message listener named `agentGuild` with `WebViewCompat.addWebMessageListener`, whose allowed origin rules hold exactly the manager's origin.
- The page sees `window.agentGuild.postMessage` and treats the app as its host. It posts JSON text, `{"source":"agent-guild","type":...}`: `ready` with `version`, `open` with `url`, and `expand` in the compact layout.
- The app accepts a message only when `isMainFrame` is true and `sourceOrigin` equals the manager's origin, then parses the JSON and accepts only those types with their fields.
- To show a view, the app runs `window.postMessage({ source: "agent-guild-app", type: "view", view }, location.origin)` with `evaluateJavascript` after `onPageFinished`. `view` is `"cards"` or `"yard"`, from a fixed list, never from text.

The page needs agent-guild's change "feat: support Agent Guild in the Android app web view". The app's minimum Agent Guild version is the first release that carries it.

## WebView security

No new navigation framework: the app uses `WebViewClient` and `WebChromeClient` directly.

- **First load:** only a URL built from a saved, validated computer: `<address>/#token=<token>` plus `&view=`.
- **Navigation and redirects:** `shouldOverrideUrlLoading` cancels any main-frame load whose origin isn't the manager's. A link the user followed opens in a Custom Tab instead, only for `http` and `https`. Server redirects reach the same check. As a second guard, `onPageStarted` stops a main-frame page whose origin isn't the manager's and shows the error screen.
- **New windows:** `setSupportMultipleWindows(true)`, and `onCreateWindow` returns `false`. The page sends links through the bridge instead.
- **Renderer recovery:** `onRenderProcessGone` destroys the `WebView`, creates a new one and loads the same validated URL.
- **Settings:** JavaScript and DOM storage on; file and content access off; mixed content never allowed; no `addJavascriptInterface`; `setWebContentsDebuggingEnabled` in debug builds only.
- **Microphone:** `onPermissionRequest` grants only `PermissionRequest.RESOURCE_AUDIO_CAPTURE`, only when the request's origin is exactly the manager's, and only after the user has granted the `RECORD_AUDIO` runtime permission. Every other request, origin or resource is denied.
- **Storage of computers:** name, address and token in DataStore, encrypted with an AES-GCM key from the Android Keystore, and kept out of cloud backups and device transfers through `dataExtractionRules` and `fullBackupContent`.

## What was verified on the emulator

The probe in `tools/probe` checked each of these in the Android 17 emulator with WebView 145, against the real page served by a scratch manager:

| Question | Result |
| --- | --- |
| Is `window.agentGuild` there before the page's first script? | Yes. An inline script in `<head>` sees it, so `theme.js` does. |
| What does `postMessage` carry? | Strings only. An object throws `TypeError`. JSON text arrives with `isMainFrame` true and the page's origin. |
| Does the page work as the app's host? | Yes, with agent-guild's Android host change: `ready` arrives as JSON, `#view=yard` opens and keeps the Yard, the token leaves the address, and the `view` message switches views. |
| Dictate | The `WebView`'s `webkitSpeechRecognition` uses Android's own speech recognition service. It reaches `audiostart`, and the service returns its final result (empty, with nothing spoken). |
| Dictate without a speech service | `start`, then `aborted`, then `end`. The page treats that as an ordinary stop. |
| Dictate right after boot, with a working service | The first attempt gave `aborted` before `audiostart`, the second `audio-capture`, and the third worked. So `aborted` before `audiostart` doesn't by itself mean there is no speech service, and the page keeps Dictate available. |
| Read aloud | `speechSynthesis` is undefined, so the page hides its Read aloud button. |
| The Yard | Renders with WebGL2 at the display's frame rate. |
| Tailscale | The emulator reaches tailnet addresses but doesn't resolve `ts.net` names. With `start.ps1 -Tailnet`, it loads `https://<computer>.<tailnet>.ts.net/api/v1/health` through Tailscale Serve, certificate included. |
| Android 10 system image | Its built-in WebView is 74, without `WEB_MESSAGE_LISTENER` or WebGL2. The app's startup check is tested by controlling the feature check, not by relying on that image (see below). |

## Toolchain

| | Version |
| --- | --- |
| JDK | Temurin 21.0.12.1+1 |
| Gradle | 9.8.2 (the project uses its wrapper) |
| Android Gradle Plugin | 9.4.1 |
| AndroidX WebKit | 1.18.0 |
| compileSdk, targetSdk | 37 |
| minSdk | 29 (Android 10), with the `WEB_MESSAGE_LISTENER` check at startup |
| Build tools | 37.0.0 |
| Emulator images | `google_apis` x86_64 for API 37.0 (`ag37`) and API 29 (`ag29`) |

These stay as they are unless a concrete compatibility problem calls for a change.

## Emulator tools

Windows, in PowerShell 7. Everything installs into user folders, without administrator rights. The emulator needs the Windows Hypervisor Platform; `setup.ps1` ends with `emulator -accel-check`, which says whether it is usable.

```powershell
pwsh tools/emulator/setup.ps1                       # JDK, Gradle, SDK packages, ag37 and ag29; skips what is there
. tools/emulator/env.ps1                            # puts them on PATH in this session
pwsh tools/emulator/start.ps1 -Avd ag37 -Tailnet    # headless; -Window to watch it; -Port for a second emulator
pwsh tools/emulator/stop.ps1                        # -Port to match start.ps1
```

- `start.ps1` returns once Android has booted and its network has settled. Right after boot the emulator's network drops for several seconds while Android picks a default network.
- **Always stop an emulator with `stop.ps1`.** A killed emulator leaves a crash report, and its consent dialog hangs the next boot. `start.ps1` clears such leftovers, and `stop.ps1` waits until the emulator's processes have exited, because one started while they run fails to boot.
- `-Tailnet` starts `dns-forward.mjs` on `127.0.0.1:53`. It sends `ts.net` names to Tailscale's MagicDNS resolver, `100.100.100.100`, and everything else to `1.1.1.1`. Starting the emulator with `-dns-server 100.100.100.100` directly breaks every lookup. The host must be signed in to Tailscale.
- `cdp.mjs` evaluates JavaScript in a debuggable `WebView`'s page, after `adb forward tcp:<port> localabstract:webview_devtools_remote_<pid>`.

### The probe

`tools/probe` is a verification app, never shipped. It loads the URL in its `url` extra, registers `agentGuild` for that URL's origin, grants whatever the page asks for, and logs under `AGPROBE`. `site/probe.html` reports the bridge, speech and WebGL; `site/speech.html#<case>` runs the Dictate cases (`normal`, `cancel-early`, `cancel-listening`, `busy`, `restart`, `restart-now`).

```powershell
. tools/emulator/env.ps1
gradle -p tools/probe assembleDebug
adb install -r -g tools/probe/app/build/outputs/apk/debug/app-debug.apk
python -m http.server 8765 --bind 127.0.0.1 --directory tools/probe/site    # in another terminal
adb reverse tcp:8765 tcp:8765
adb shell am start -n com.oddessentials.probe/.MainActivity --es url "'http://127.0.0.1:8765/probe.html'"
adb logcat -s AGPROBE:I
```

## Test boundaries

- **Never touch the manager that is already running on the default port, 47821.** It may be hosting the work itself: never stop, restart or reconfigure it, and never point its remote access elsewhere.
- **Scratch manager:** from an agent-guild checkout or the npm package, with its own data folder and port:

  ```sh
  AGENT_GUILD_HOME=<scratch folder> AGENT_GUILD_PORT=47931 AGENT_GUILD_NO_UPDATE_CHECK=1 node bin/agent-guild.mjs start
  ```

  The token is in `<scratch folder>/auth-token`. `adb reverse tcp:47931 tcp:47931` makes it reachable in the emulator at `http://127.0.0.1:47931`, a Host the manager already allows. Delete the scratch folder afterwards.
- **Tailscale:** signing in over Tailscale needs a Serve route to a scratch manager, which changes the host's Tailscale configuration. Ask before setting one up. Without one, only `GET /api/v1/health`, which needs no token, may be read through the existing route.
- **Unsupported WebView:** the startup check reads `WebViewFeature.isFeatureSupported(WEB_MESSAGE_LISTENER)` through a small interface. Instrumented tests replace it, so the unsupported screen is tested on any image.
- **Tests are deterministic:** no sleeps waiting for timing, and no dependence on the network beyond the scratch manager.
- **Never commit** credentials, tokens, signing keys, `local.properties`, build output or machine-specific paths.

## Next: the first version

The plan for the next session, in this repository:

1. **Project.** Kotlin and Compose, with the toolchain above, package `com.oddessentials.agentguild`, and the Gradle wrapper at 9.8.2.
2. **Startup check.** If `WEB_MESSAGE_LISTENER` isn't supported, show the `WebView` version and ask the user to update Android System WebView.
3. **Computers.** The list, add, rename, remove and sign in again, stored as described under [WebView security](#webview-security).
4. **Sign-in.** The parser above, a QR scanner using CameraX and ML Kit's bundled barcode model, and the `/api/v1/info` check. Errors read like the iOS app's `HealthProblem` messages, and the version check requires the Android host release.
5. **The page.** The `WebView` with the bridge and every rule under [WebView security](#webview-security); the Yard/Cards switch, saved per window; Custom Tabs for links.
6. **Recovery.** Check again on `ON_RESUME`. A rejected token or a changed address offers to scan or paste again; other failures keep the page with a banner.
7. **Demo.** An entry that opens the public demo, `https://oddessentials.github.io/agent-guild/`, simulated, with no computer needed.
8. **Tests.**
   - JVM: the parser's accept and reject cases; the health answers; the navigation, bridge and permission decisions; the store.
   - Instrumented, on `ag37` against a scratch manager: sign-in, loading, `ready`, view switching, a link opening outside, an off-origin navigation and redirect cancelled, `onCreateWindow` refused, microphone requests from another origin denied, recovery after a renderer crash, and a generated sign-in QR image read through ML Kit.
   - The unsupported-WebView screen, with the feature check replaced.

Later, each needing its own approval: native Read aloud using `TextToSpeech` and `/api/v1/sessions/:id/reply` (a bridge change), several windows, and the compact Yard on a second display.

## Release (proposed, not built)

Nothing here is built or run until the app works and its security and integration tests pass, and nothing is published without explicit permission.

- A signed universal APK attached to each GitHub release, for people to download and install. No app store.
- A release key generated once, stored as GitHub Actions secrets (the keystore in base64 and its passwords), and backed up offline. Android installs an update only when it is signed with the same key, so losing the key means every user reinstalls.
- On each push to `main`, semantic-release picks the version from Conventional Commit titles, and `versionCode` is the workflow run number. Gradle builds the release APK, `apksigner` signs it with v2 and v3 signatures, and `apksigner verify` must pass. The APK and its SHA-256 are attached to the release.
- Pull requests run the JVM tests, and the instrumented tests on an API 37 emulator against a scratch manager installed from npm.
- The app looks at the latest GitHub release and offers the newer APK through the browser, so it needs no permission to install packages.
- Google's developer verification covers sideloaded apps on certified devices: the package name and the release key are registered once in the Android Developer Console.

## Limits known now

- **Dictate** needs a speech recognition service on the device. Without one, pressing Dictate ends at once and the page shows nothing. Detecting that natively and telling the page would change the bridge contract, so it needs approval first.
- **Read aloud** is hidden until it is done natively.
- **No notifications or background connection:** the `WebView`'s sockets close when Android stops the app, and the page reconnects when it returns. The sessions keep running on the computer.
- **Emulator and Tailscale:** tailnet names resolve only with `start.ps1 -Tailnet`.

## License

[PolyForm Shield 1.0.0](LICENSE), as Agent Guild.
