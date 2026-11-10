on run
    try
        with timeout of 15 seconds
            if application id "com.spotify.client" is running then
                tell application id "com.spotify.client" to playpause
            else
                tell application id "com.spotify.client" to play
            end if
        end timeout
    on error errorText number errorNumber
        if errorNumber is -1743 then
            display alert "Spotify control needs permission" message "In System Settings, go to Privacy & Security, then Automation. Allow Spotify Play-Pause to control Spotify."
        else
            display alert "Spotify playback could not be changed" message errorText
        end if
    end try
end run
