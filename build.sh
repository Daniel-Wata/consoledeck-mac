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
build_swift_app "Mute Microphone" MuteMicrophone "$project_dir/Launchers/Info-microphone.plist" \
    "$project_dir/Launchers/Mute Microphone.swift"

build_spotify_launcher() {
    local name="$1" identifier="$2" description="$3"
    local spotify_app="$build_dir/$name.app"
    local spotify_plist="$spotify_app/Contents/Info.plist"
    osacompile -o "$spotify_app" "$project_dir/Launchers/$name.applescript"
    set_spotify_plist() {
        if ! plutil -replace "$1" "$2" "$3" "$spotify_plist" 2>/dev/null; then
            plutil -insert "$1" "$2" "$3" "$spotify_plist"
        fi
    }
    set_spotify_plist CFBundleIdentifier -string "$identifier"
    set_spotify_plist LSUIElement -bool true
    set_spotify_plist NSAppleEventsUsageDescription -string "$description"
    codesign --force --sign - "$spotify_app"
    codesign --verify --strict "$spotify_app"
}

if [[ "${1:-}" == "--spotify" ]]; then
    build_spotify_launcher "Spotify Play-Pause" local.codex.consoledeck.spotify-play-pause \
        "The ConsoleDeck Play button controls Spotify playback."
    build_spotify_launcher "Spotify Next Track" local.codex.consoledeck.spotify-next-track \
        "The ConsoleDeck button skips to the next track in Spotify."
fi

printf 'Built apps in %s\n' "$build_dir"
