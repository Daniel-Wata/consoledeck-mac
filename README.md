# ConsoleDeck for macOS

A native macOS menu bar app for an Arduino Nano macro pad. The nine grid
buttons and the Media button can open apps, files, folders, or websites,
send keyboard shortcuts, and control playback. Turn the knob to adjust
system volume and press it to toggle speaker mute. The knob controls the
current system output directly and works without Accessibility permission
when macOS can adjust that output.

## Download and install

1. [Download the source ZIP](https://github.com/Daniel-Wata/consoledeck-mac/archive/refs/heads/main.zip)
   and unzip it. ConsoleDeck requires macOS 14 or later.
2. If you haven't installed the Xcode command-line tools, run
   `xcode-select --install` in Terminal and finish the installer.
3. In Terminal, type `cd ` (with a trailing space), drag the unzipped folder
   into the window, and press Return. Build the apps and open the output
   folder in Finder.

   ```sh
   ./build.sh
   open .build
   ```

   To include the Spotify launchers, install Spotify for Mac first and run
   `./build.sh --spotify` in place of `./build.sh`.
4. Move `ConsoleDeck.app` from the build folder to `~/Applications` (the
   Applications folder in your home folder). Create that folder if needed,
   then open the installed app and connect the deck by USB.
5. Select **Configure Buttons…** from the ConsoleDeck menu bar icon. Use
   **Start at Login** if you want the app to run when you sign in.
   Click **Allow Keyboard Control…** to grant macOS Accessibility access
   if you use the system Play / Pause action or keyboard shortcuts.

The app recognizes the CH340 USB adapter with vendor ID `0x1a86` and
product ID `0x7523`. It communicates at 115200 baud and reconnects when
the device appears.

## Reinstall or move to another Mac

For a reinstall on the same Mac, choose **Quit ConsoleDeck** from its menu
bar icon, download and build the source again, and replace the installed
`ConsoleDeck.app` at the same path. Then reopen it. Assignments are stored
in your macOS preferences, separately from the app. Keep any helper apps
at the paths your buttons already use, or reselect them under
**Configure Buttons…**. If the Nano already runs ConsoleDeck firmware,
reinstalling the Mac app requires no firmware upload.

To back up your button assignments, quit ConsoleDeck and run this command
in Terminal.

```sh
defaults export local.codex.consoledeck "$HOME/Downloads/ConsoleDeck-settings.plist"
```

Save that plist and any custom launcher apps in a private backup. The plist
can contain personal URLs and local paths. For a restore, install the app
and helpers, quit ConsoleDeck if it's open, and import the backup. This
replaces the current ConsoleDeck preferences.

```sh
defaults import local.codex.consoledeck "$HOME/Downloads/ConsoleDeck-settings.plist"
open "$HOME/Applications/ConsoleDeck.app"
```

If your backup is elsewhere, change the path in the import command. On a
different Mac or user account, reselect apps and launchers whose paths have
changed, recreate any browser profiles your custom launchers use, and set
up **Start at Login** and any macOS permissions you use.

## Firmware

Upload [ConsoleDeck.ino](firmware/ConsoleDeck/ConsoleDeck.ino) to a classic
Arduino Nano. This build uses the ATmega328P Old Bootloader option. The
buttons are active-low and connect to GND.

| Control | Pins |
| --- | --- |
| Keys 1–3 | D12, A1, D11 |
| Keys 4–6 | A0, D9, D10 |
| Keys 7–9 | D5, D6, D7 |
| Media | D8 |
| Knob push | D2 |
| Knob rotation | D4, D3 |

Adjust the pin definitions in the sketch if your wiring differs.

## Microphone and Spotify

Move `.build/Mute Microphone.app` to a permanent location and assign it
to a button with **Open App, File or Folder**. Click **Save Action** to
apply the assignment. It toggles the Mac's default
input on devices that expose a native mute control. ConsoleDeck’s menu bar
icon turns into a red crossed-out microphone when the input is muted. Its
menu also shows the current state.

To build the optional Spotify launchers, install the Spotify desktop app
and run `./build.sh --spotify`. Move `.build/Spotify Play-Pause.app` and
`.build/Spotify Next Track.app` to a permanent location. Assign them to Media
and a grid button with **Open App, File or Folder**. Allow each launcher to
control Spotify when macOS prompts on first use.
