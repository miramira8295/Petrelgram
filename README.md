# Petrelgram

**English** · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [Français](README.fr.md)

[![Telegram](https://img.shields.io/badge/Telegram-Join%20the%20group-26A5E4?style=flat&logo=telegram&logoColor=white)](https://t.me/+khkR9mLZyoliODFl)
[![Release](https://img.shields.io/github/v/release/miramira8295/Petrelgram?style=flat)](https://github.com/miramira8295/Petrelgram/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat)](LICENSE)

An open-source **unofficial Telegram client for HarmonyOS NEXT**, written in
ArkTS/ArkUI on top of [TDLib](https://core.telegram.org/tdlib), Telegram's own
client library, bridged through native N-API.

## Features

- **Accounts** — phone login with 2FA, multiple accounts, switching, sign-out
- **Chats** — folders, archive, unread badges, live connection status
- **Messages** — rich text, photos, albums, video, files, stickers (WEBP / TGS /
  WEBM), custom emoji, replies, forwards, reactions, comment threads, pinned
  messages, scheduled messages, multi-select
- **Composer** — mentions and command autocomplete, media, files, voice, music,
  location, contacts, polls, dice
- **Calls** — end-to-end encrypted 1:1 voice and video via tgcalls
- **Group calls & live streams** — multi-party voice, camera and screen sharing,
  channel broadcasts, in-app floating window
- **Topics & Stories** — forum topic lists and per-topic message streams;
  full-screen story viewer
- **Search** — global search across 11 categories
- **Profiles** — user, bot, group and channel pages; avatar, bio and username
  editing; QR business card
- **Settings** — privacy and security, notifications, storage, sessions and
  devices, chat folders, battery saver, dark mode

## Layout

```
AppScope/            app-level config (bundle name, icon)
entry/src/main/ets/
  tdkit/             TDLib N-API bridge, client, auth service
  store/             immutable stores + subscriptions (chats, messages, …)
  pages/             ArkUI pages (login, chat list, chat, profile, search …)
  services/          media streaming, live-stream background tasks, audio
  util/              parsing and formatting (rich text, albums, dates …)
entry/src/main/cpp/  native bridge (libentry.so → libtdjson.so / libtgcalls_ohos.so)
entry/src/test/      unit tests (run via scripts/run-local-tests.sh)
scripts/             TDLib/tgcalls fetch and build scripts, local test gate
```

## Building

### Requirements

- **DevEco Studio 6.0+** with its bundled OpenHarmony SDK/NDK
- `curl` and `file` (preinstalled on macOS/Linux)

### 1. Native libraries

The app bundles TDLib and tgcalls as prebuilt native libraries in
`entry/libs/arm64-v8a/` (~50 MB, not committed). `libentry.so` links against
both — **missing either one stops the build** at ninja's
`missing and no known rule to make it`.

**Option A — download prebuilt (recommended):**

```bash
bash scripts/fetch-libs.sh [tag]   # both libraries, from this repo's Releases
```

Without an argument the script resolves the latest release. Do not fall back to
the rolling `tdlib-latest` tag: its `libtdjson.so` stays current but its
`libtgcalls_ohos.so` lags behind the versioned releases.

**Option B — build from source (~10–15 min on a recent Mac):**

```bash
# needs clang (Xcode CLT), cmake, ninja, gperf, patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
bash scripts/build-tgcalls-ohos.sh
```

`build-tdlib.sh` wraps [`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build)
end to end: cross-compiles OpenSSL (static, `1_1_1w`) and TDLib (release
**1.8.65**) for arm64-v8a, pre-generates TDLib's TL-schema sources on the host
(required when cross-compiling), and normalises the SONAME to `libtdjson.so`
with `patchelf` — without that last step the native bridge fails to load
**silently**. The script is idempotent; re-running it is safe.

`build-tgcalls-ohos.sh` downloads and builds WebRTC on first run, which takes a
while. Pinned versions and current media limits are in
[`scripts/tgcalls/README.md`](scripts/tgcalls/README.md).

### 2. Telegram API credentials

TDLib needs your own `api_id`/`api_hash` — this repository ships none.

1. Register an application at <https://my.telegram.org/apps>.
2. Copy `entry/src/main/ets/tdkit/ApiCredentials.template.ets` to
   `ApiCredentials.ets` in the same directory.
3. Generate the packed constants and paste the three printed values in:

   ```bash
   node scripts/gen-creds.mjs <api_id> <api_hash>
   ```

`ApiCredentials.ets` is gitignored — **never commit real credentials**; revoke
and regenerate immediately if they leak. The packing is obfuscation, not
encryption: it only raises the bar for casual extraction from an installed
package.

### 3. Signing

`signingConfigs` in `build-profile.json5` is empty. Open the project in DevEco
Studio and use **File > Project Structure > Signing Configs > Support HarmonyOS
Auto-Sign** (requires a Huawei developer account) to generate a local debug
certificate. No signing material needs to be committed or shared.

### 4. Build and run

Open in DevEco Studio and run on a HarmonyOS NEXT device or emulator, or:

```bash
hvigorw assembleHap --no-daemon
```

Run the test gate:

```bash
./scripts/run-local-tests.sh    # must print "LOCAL TESTS: PASS"
```

The script runs the i18n check before the unit tests — a static check that
answers in a second should not sit behind a two-minute test build.

## Localization

All UI copy lives in resource files. The source language (Simplified Chinese) is
`entry/src/main/resources/base/element/string.json`; translations go in
language-qualified directories (`en_US/element/string.json` and so on), plurals
in `element/plural.json`. The system matches the device language and falls back
to `base`.

**`$r()` vs `str()`.** Anything a component renders uses `$r('app.string.x')`:
it is a `Resource`, re-resolved by ArkUI on configuration change, so switching
language takes effect immediately. `str('x')` returns a plain string fixed at
build time — use it only where a `string` is genuinely required: `string`-typed
`@State`, model fields, comparisons, `.join()`, and non-UI code. When a
`@Builder` parameter causes a type conflict, widen it to `ResourceStr` rather
than reverting the call site to `str()`.

**Module-level `const` cannot hold copy.** Constants are built on first import,
before the string source is ready, freezing the language at that moment. Use a
function (`fallbackCountries()`, not `FALLBACK_COUNTRIES`).

**Never match on displayed text.** `label.substring(0, 2)` or
`text.includes('Retry')` breaks the moment the language changes; branch on
structured fields instead.

Diagnostic strings that only reach `console.*` are not translated; mark them
with `// i18n-exempt: <reason>`.

```bash
node scripts/i18n-extract.mjs               # remaining hardcoded copy, by domain
node scripts/i18n-extract.mjs --domain util # details and key suggestions
node scripts/i18n-lit.mjs <file>            # literals with line numbers
node scripts/i18n-check.mjs                 # the gate (also in run-local-tests.sh)
```

`i18n-check.mjs` checks five things: every key referenced in code exists in
`base`; every key in `base` is referenced somewhere; **no `${` template source
survives in a resource value, and placeholder numbering matches across
languages**; no orphan keys outside `base` and which entries each language is
missing; **no Chinese literals remain in directories already covered by the
gate**.

The third check was added after the fact — the gate, the tests and the compiler
each see one class of error, but none of them can see that the value of
`file_downloading` *is* the template source `${sizeLabel} · downloading`. That
kind of mistake only shows up on a device.

`MIGRATED` in `scripts/i18n-config.mjs` now covers every source directory — add
new directories to it, or the gate will quietly skip them. Key naming is
`<domain>_<component>_<meaning>`, e.g. `chat_forward_title`.

## Status and disclaimer

- Under active development; the interface aims to stay close to the official
  Android client.
- This is an **unofficial** client. Use your own API credentials and comply with
  the [Telegram API Terms of Service](https://core.telegram.org/api/terms).
- Stranger search follows Telegram/TDLib server-side discoverability rules: it
  generally finds only users with a public username or otherwise in the server's
  search scope, and cannot be used to enumerate arbitrary phone numbers.

## License

[Apache License 2.0](LICENSE)
