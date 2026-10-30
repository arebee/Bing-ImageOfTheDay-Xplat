function Get-Resolution {
    # Get the appropiate screen resolution, using OS specific probing
    if ($PSVersionTable.OS.Contains('Windows')) {
        Write-Verbose 'On Windows'
        Add-Type -AssemblyName System.Windows.Forms
        $primaryScreen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { $_.Primary -eq 'True' }
        $width = $primaryScreen.Bounds.Width
        $height = $primaryScreen.Bounds.Height
    }
    elseif ($PSVersionTable.OS.Contains('macOS') -or $PSVersionTable.OS.Contains('Darwin')) {
        Write-Verbose 'On MacOS'
        $null = system_profiler SPDisplaysDataType -json | ConvertFrom-Json -OutVariable displayInfo
        foreach ($display in $displayInfo[0].SPDisplaysDataType[0].spdisplays_ndrvs[0]) {
            if ($display.spdisplays_main -eq 'spdisplays_yes') {
                [int]$width = $display._spdisplays_pixels.split('x')[0].Trim()
                [int]$height = $display._spdisplays_pixels.split('x')[1].Trim()
            }
        }
    }
    else {
        # Default for Linux HD
        $width = 1920
        $height = 1080
    }

    # Determine the resolution to download based on width and height
    if ($width -le 1024) {
        $Resolution = '1024x768'
    }
    elseif ($width -le 1280) {
        $Resolution = '1280x720'
    }
    elseif ($width -le 1366) {
        $Resolution = '1366x768'
    }
    elseif ($height -le 1080) {
        $Resolution = '1920x1080'
    }
    elseif ($width -le 1920) {
        $Resolution = '1920x1080'
    }
    else {
        $Resolution = 'UHD'
    }
        
    Write-Verbose "Resolution: $resolution"
    return $Resolution
}