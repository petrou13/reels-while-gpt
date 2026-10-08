# Reels While GPT

Instagram is owned by Meta Platforms Inc., designated an extremist organization in Russia; its activities involving Facebook and Instagram are prohibited in Russia. [Russian Ministry of Justice list](https://minjust.gov.ru/ru/documents/7822/).

Your little break while ChatGPT thinks.

[Русский](README.md) · [License](LICENSE) · [Privacy](Release/PRIVACY.en.md)

A local menu bar utility for **Apple Silicon and macOS 13+**. It opens its own vertical Instagram Reels viewer while ChatGPT prepares a response, then hides it after confirmed completion. Supports the ChatGPT desktop app, Chrome and Safari. You can also open Reels manually.

Author: [petrou13](https://github.com/petrou13). Independent of OpenAI and Meta. Source-available under **PolyForm Noncommercial 1.0.0**; commercial use is not licensed. This is not OSI open source.

## Features

Floating window over fullscreen apps; single-reel swipes; seeking controls below Instagram; compact timeline that optionally expands on hover; retained feed for quick reopening; mute, language and focus-return preferences; browser PiP alternative; persistent local Instagram sign-in with an explicit removal button; one running instance; separate technical diagnostics.

## Install

Version **1.17** is a free testing build, ad-hoc signed with Hardened Runtime but **not Developer ID signed or notarized by Apple**. Published binaries, when available, are in [Releases](https://github.com/petrou13/reels-while-gpt/releases). If there is no release yet, build from source. Publication of source does not imply a binary release exists.

Quit the old app, extract the ZIP and move the app to a permanent folder such as `~/Applications`. macOS may block an unidentified/unnotarized app. If you trust the artifact, follow [Apple's per-app Open Anyway procedure](https://support.apple.com/102445) where available. Do not globally disable Gatekeeper or SIP.

Choose the ChatGPT source under Connection, grant required permissions, choose the viewer under Watch and sign in on Instagram if required. Enable automatic request-triggered viewing or use Open Reels manually.

## Permissions and data

Accessibility is required for native detection and browser fallback. Add the installed app copy to macOS Accessibility settings. Browser Automation permission and optionally Allow JavaScript from Apple Events are required for DOM mode (Safari Develop, Chrome View → Developer). AX fallback may recognize fewer states. Screen Recording, Input Monitoring, Full Disk Access, camera and microphone are not required.

The utility does not request password field values, message text or chat titles, and has no telemetry/developer server. Persistent WebKit website data retains sign-in using sensitive session cookies/tokens, not a password database maintained by the utility. Passwords are handled by the official Instagram page. Instagram's own storage/analytics remain governed by its policies. Browser cookies are not imported/exported. Watch → Remove saved Instagram sign-in deletes this app's website data after confirmation without changing Chrome/Safari sessions. See [privacy](Release/PRIVACY.en.md) and [audit scope](Release/SECURITY-AUDIT.ru.md).

## Build

Install/configure Xcode with a macOS SDK and accept its license. No paid Apple Developer membership is needed for local ad-hoc building. Node.js is needed for JS tests; CI uses Node 24.

```bash
./build.sh
./Tests/run.sh
```

Outputs: `dist/Reels While GPT.app`, `dist/ReelsWhileGPT-arm64.zip`. LICENSE and NOTICE are included in the app. Version 1.17 passed 245 local checks, including browser diagnostics and stop-control regressions. Live Instagram sign-in, AX and clean-Mac installation still need manual testing. The hosted CI/manual prerelease workflow has to run successfully before its artifact can be claimed tested.

## Distribution and contribution

The manual GitHub prerelease workflow requires no Apple secrets and deliberately labels binaries as ad-hoc/unnotarized. A later [Developer ID/notarization plan](Release/PUBLISH.en.md) is included. The current app is not App Sandbox enabled and is not ready for Mac App Store submission. Instagram/ChatGPT changes may break DOM/AX behavior; restrictions and login are not bypassed.

See [LICENSE](LICENSE), [NOTICE](NOTICE), [CONTRIBUTING](CONTRIBUTING.md), [SECURITY](SECURITY.md). Keep notices when sharing copies. Do not upload passwords, cookies, account tokens, private conversation content or third-party videos in reports.

Version 1.17: Connection includes advanced options. Check detector probes the selected app or browser, with separate macOS Automation, JavaScript and DOM/Accessibility results. Conversation URLs and field values are excluded. In Safari 17+, enable web developer features in Settings → Advanced, then Allow JavaScript from Apple Events in Settings → Developer.
