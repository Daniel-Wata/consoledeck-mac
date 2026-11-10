on run
    try
        with timeout of 15 seconds
            tell application id "com.spotify.client" to next track
        end timeout
    on error errorText number errorNumber
        if errorNumber is -1743 then
            display alert "Spotify control needs permission" message "In System Settings, go to Privacy & Security, then Automation. Allow Spotify Next Track to control Spotify."
        else
            display alert "Spotify could not skip to the next track" message errorText
        end if
    end try
end run
