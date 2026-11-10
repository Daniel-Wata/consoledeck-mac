#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$project_dir/.build"
target="$(uname -m)-apple-macosx14.0"

build_swift_app() {
    local name="$1" executable="$2" plist="$3"
    shift 3
    local bundle="$build_dir/$name.app"
    mkdir -p "$bundle/Contents/MacOS"
    cp "$plist" "$bundle/Contents/Info.plist"
    xcrun swiftc -swift-version 5 -O -target "$target" "$@" -o "$bundle/Contents/MacOS/$executable"
    codesign --force --sign - "$bundle"
    codesign --verify --strict "$bundle"
}

build_swift_app ConsoleDeck ConsoleDeck "$project_dir/Info.plist" \
    -parse-as-library "$project_dir"/Sources/*.swift
build_swift_app "ConsoleDeck Mic Status" ConsoleDeckMicStatus "$project_dir/MicStatus/Info.plist" \
    "$project_dir/MicStatus/main.swift"
build_swift_app "Mute Microphone" MuteMicrophone "$project_dir/Launchers/Info-microphone.plist" \
    "$project_dir/Launchers/Mute Microphone.swift"

if [[ "${1:-}" == "--spotify" ]]; then
    spotify_app="$build_dir/Spotify Play-Pause.app"
    osacompile -o "$spotify_app" "$project_dir/Launchers/Spotify Play-Pause.applescript"
    spotify_plist="$spotify_app/Contents/Info.plist"
    set_spotify_plist() {
        if ! plutil -replace "$1" "$2" "$3" "$spotify_plist" 2>/dev/null; then
            plutil -insert "$1" "$2" "$3" "$spotify_plist"
        fi
    }
    set_spotify_plist CFBundleIdentifier -string local.codex.consoledeck.spotify-play-pause
    set_spotify_plist LSUIElement -bool true
    set_spotify_plist NSAppleEventsUsageDescription -string "The ConsoleDeck Play button controls Spotify playback."
    codesign --force --sign - "$spotify_app"
    codesign --verify --strict "$spotify_app"
fi

printf 'Built apps in %s\n' "$build_dir"
