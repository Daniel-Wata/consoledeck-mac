# ConsoleDeck for macOS

A native macOS menu bar app for an Arduino Nano macro pad. The nine grid
buttons and the Media button can open apps, files, folders, or websites,
send keyboard shortcuts, and control playback. Turn the knob to adjust
system volume and press it to toggle speaker mute.

## Build and run

1. Install the Xcode command-line tools on macOS 14 or later and run
   `./build.sh`.
2. Move `.build/ConsoleDeck.app` to your Applications folder and open it.
   Select **Configure Buttons…** from its menu bar icon. Use **Start at
   Login** if you want it to run when you sign in.
3. Click **Allow Media Keys…** to grant macOS Accessibility access if you
   use media keys or keyboard shortcuts.

The app recognizes the CH340 USB adapter with vendor ID `0x1a86` and
product ID `0x7523`. It communicates at 115200 baud and reconnects when
the device appears.

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
to a button with **Open App, File or Folder**. It toggles the Mac's default
input on devices that expose a native mute control. ConsoleDeck’s own menu bar icon turns into a red crossed-out microphone
when that input is muted. Its menu also shows the current state.

To build the optional Spotify launcher, install the Spotify desktop app
and run `./build.sh --spotify`. Move `.build/Spotify Play-Pause.app` to a
permanent location and assign it to Media. Allow the launcher to control
Spotify when macOS prompts on first use.
