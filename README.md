# Attak
<img src="https://github.com/user-attachments/assets/ae0757fe-01a9-4cdb-8568-f8520ffbb706" width=49%> <img src="https://github.com/user-attachments/assets/2e71a356-8877-4fb9-b6ca-b8d5d08db09e" width=49%>

Attak is a Tak client for the existing playtak servers, written in godot.
It brings new features such as a 2D board and a mobile-friendly interface,
It is available on:
- desktop (Windows / Linux)
- android
- the web: [attak.club](attak.club)

## Installation
the latest version can be downloaded [here](https://github.com/The1Rogue/Attak/releases/latest)

#### Android:
download `Attak.apk` to you mobile device, and run to install the app.

#### Windows:
download `Attak_Win.zip` to your device, unzip to reveal 2 files (`Attak.pck`, `Attak.exe`)
make sure both files are in the same directory, then run `Attak.exe`

#### Linux:
download `Attak.x86_64`, and run it.

#### Web:
simply go to [attak.club](attak.club)

if you wish to host attak yourself, download `Attak_Web.zip`, unzip, and serve `Attak.html`,
do note that some functionality may be limited if your domain does not have access to the playtak api

## Playing offline against a bot

The **Play → Vs Bot** tab starts a game against a bot with no account and no
network connection. Pick a board size, your colour, and a difficulty.

The first three difficulties run a small built-in GDScript opponent, which works
on every platform including the web build. The two **Syntaks** difficulties run
[syntaks](https://github.com/Ciekce/syntaks) as a native extension — far
stronger, but only on desktop and Android arm64, and only on 6x6, which is the
size syntaks implements. They are hidden automatically when unavailable, and
picking one on another board size falls back to the built-in bot.

Syntaks games use a komi of 2, which is the komi the engine is built around.

## Building

`tools/build-apk.sh` produces a signed Android APK headlessly; see the comments at
the top of the script for the toolchain it expects. `.github/workflows/android.yml`
runs the same script in CI and uploads the APKs as artifacts.

The Syntaks extension is MIT licensed and places no conditions on Attak's own
licensing — see [LICENSE-THIRD-PARTY.md](LICENSE-THIRD-PARTY.md), which also
explains why it depends on a fork. Build with `SKIP_SYNTAKS=1` for an APK with no
native engine at all.

## Contributing
Attak is an open source hobby project, if you want to help me out, let me know!

you can find me in the [Tak discord server](https://discord.gg/Js7J3czm)
