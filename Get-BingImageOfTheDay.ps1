# Get the Bing "Image of the Day"
# 
# Forked from <https://github.com/timothymctim/Bing-wallpapers>
#
# Copyright (c) 2015 Tim van de Kamp, 2025-6 Richard Burte
# License: MIT license

<#
    .SYNOPSIS
    Fetch the Bing image of the day, or multiple from the archive.

    .DESCRIPTION
    Fetch the Bing image of the day. Can download previous day images as well. Skips downloading existing images.

    .PARAMETER Locale
    Specifies the locale of the image to download. By using the value `'auto'`, Bing will attempt to determine an applicable locale based on your IP address.
    Default value: "auto".

    .PARAMETER Count
    The number of wallpapers to download. 1 is the most recent.
    Default value: 3.
    
    .PARAMETER Delete
    Whether the script will delete all wallpapers not in the last $Count number when sorted.

    .PARAMETER Resolution
    Specify the size of the file. Select from the set, or use "auto" to detect.
    Default is "auto".
    
    .PARAMETER Path
    Specify the location where wallpapers will be downloaded.
    Default: Wallpaper folder in your Pictures folder.
    
    .PARAMETER UseAlternateSource
    Use an alternative, non-official endpoint enumerating Bing wallpaper information. Contains many more image files than the official endpoint.
    Default: False, use Bing endpoint
    
    .INPUTS
    None. You can't pipe objects to Get-BingImageOfTheDay.

    .OUTPUTS
    Writes images to specified path.

    .LINK
    https://github.com/arebee/Bing-wallpapers-x-plat

#>
function Get-BingImageOfTheDay {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # Get the Bing image of this country
        [ValidateSet(
            'auto', 'ar-XA', 'bg-BG', 'cs-CZ', 'da-DK', 'de-AT', 'de-CH',
            'de-DE', 'el-GR', 'en-AU', 'en-CA', 'en-GB', 'en-ID', 'en-IE',
            'en-IN', 'en-MY', 'en-NZ', 'en-PH', 'en-SG', 'en-US', 'en-XA',
            'en-ZA', 'es-AR', 'es-CL', 'es-ES', 'es-MX', 'es-US', 'es-XL',
            'et-EE', 'fi-FI', 'fr-BE', 'fr-CA', 'fr-CH', 'fr-FR', 'he-IL',
            'hr-HR', 'hu-HU', 'it-IT', 'ja-JP', 'ko-KR', 'lt-LT', 'lv-LV',
            'nb-NO', 'nl-BE', 'nl-NL', 'pl-PL', 'pt-BR', 'pt-PT', 'ro-RO',
            'ru-RU', 'sk-SK', 'sl-SL', 'sv-SE', 'th-TH', 'tr-TR', 'uk-UA',
            'zh-CN', 'zh-HK', 'zh-TW'
        )][string]$Locale = 'auto',

        # Download the latest $Count wallpapers.
        [ValidateRange("Positive")]
        [int]$Count = 3,

        # Delete files in the folder that were not downloaded in this execution of the command.
        [switch]$Delete,

        # Resolution of the image to download.
        [ValidateSet(
            'auto', '800x600', '1024x768', '1280x720', '1280x768', '1366x768',
            '1920x1080', '1920x1200', '720x1280', '768x1024', '768x1280',
            '768x1366', '1080x1920', 'UHD'
        )][string]$Resolution = 'auto',

        # Destination folder to download the wallpapers to. 
        [string]$Path = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers"),

        # Get wallpaper information from an unofficial alternative API with > 500 images
        [switch]$UseAlternateSource
    )

    process {
        Write-Verbose ''
        Write-Verbose '===> Executing Get-BingImageOfTheDay'
        Write-Verbose ''
        # Contstants
        $Const_Url_Image_Host = 'https://www.bing.com'
        $Const_Url_Feed_Source = 'https://www.bing.com/HPImageArchive.aspx?format=js&pid=hp'
        $Const_Url_Feed_AltSource = 'https://api45gabs.azurewebsites.net/api/sample/bingphotos'

        # Check if download folder exists and otherwise create it
        if (!(Test-Path $Path)) {
            If ($WhatIfPreference -eq $true) {
                Write-Output "Create Directory $Path"
            }
            else {
                New-Item -ItemType Directory $Path
            }
        }

        # URI to fetch the image locations from
        if ($Locale -eq 'auto') {
            $market = ''
        }
        else {
            $market = "&mkt=$Locale"
        }

        # Get the appropiate screen resolution, using OS specific probing
        if ($Resolution -eq 'auto') {
                $Resolution = Get-Resolution
        }
        Write-Verbose "Resolution: $Resolution"

        # $items = New-Object System.Collections.ArrayList
        if ($UseAlternateSource) {
            # Uses a JSON format, all items returned. No "desc" field.
            [System.Collections.ArrayList]$jsonImgs = [System.Collections.ArrayList]::new()
            try {
                $jsonImgs += ConvertFrom-Json -InputObject $(Invoke-WebRequest -UseBasicParsing -Uri $Const_Url_Feed_AltSource).Content
            }
            catch {
                Write-Error "Error: Alt Metadata URL failed: $Const_Url_Feed_AltSource"
            }
        }
        else {
            # Using the JSON Format, which puts images in an images array.
            # Add paging support for when the count of images requested > 8
            # The most recent 12 images are available through the Bing API.
            # It's a zero index page. Page 0 returns items 1-page size
            # They have a bug on paging though so :shrug:
            # &idx=0&n=$maxItemCount
            $pageSize = 8 # Maximum page size 
            <# Action when all if and elseif conditions are false #>
            if ($Count -gt 15) { $Count = 15; Write-Verbose "Bing API supports a maximum of 15 images" }
            $pageAndRemainder = [System.Math]::DivRem($Count, $pageSize)
            # To support remainder logic vs 0 offset pages
            if (($pageAndRemainder.item2 -eq 0) -and ($pagesAndRemainder.item1 -ne 0)) {
                $pages = $pageAndRemainder.Item1 - 1
            }
            else {
                $pages = $pageAndRemainder.item1
            }
            for ($i = 0; $i -le $pages; $i++) {
                if ($pages -eq $i) { $pageItems = $pageAndRemainder.Item2 } else { $pageItems = $pageSize }
                [string]$pageUri = "$Const_Url_Feed_Source$market&idx=$($i * $pageSize)&n=$pageItems"
                Write-Verbose "Fetching Page $($i + 1)"
                try {
                    $request = Invoke-WebRequest -Uri $pageUri -DisableKeepAlive -UserAgent 'parp-1.0' -UseBasicParsing
                    $jsonImgs += $(ConvertFrom-Json -InputObject $request.Content).Images
                }
                catch {
                    Write-Error "Error: Web request to $pageUri failed."
                }
            }
        }

        # Add utility properties
        foreach ($item in $jsonImgs) {
            [string]$imageDate = [datetime]::ParseExact($item.startdate, 'yyyyMMdd', $null).ToString("yyyy-MM-dd")
            [string]$imageUrl = "$Const_Url_Image_Host$($item.urlBase)_$Resolution.jpg"
            Add-Member -Type NoteProperty -Name imagedate -Value $imageDate -InputObject $item -Force
            Add-Member -Type NoteProperty -Name imageurl -Value $imageUrl -InputObject $item -Force
        }
        if ($jsonImgs.Count -gt 0) {

            # Download items
            $jsonImgs = $($jsonImgs | Sort-Object -Property startdate -Unique -Descending)
            Write-Verbose "Most recent $Count images to check from $($jsonImgs.length)"
            $i = 0
            $client = New-Object System.Net.WebClient
            foreach ($item in $jsonImgs) {
                
                $destination = Join-Path $Path "$($item.imagedate).jpg"
                $destinationWithMetadata = Join-Path $Path $($item.imagedate + "_meta.jpg")
                
                # Download the enclosure if we haven't done so already
                if (!(Test-Path $destination) -and !(Test-Path $destinationWithMetadata)) {
                    Write-Verbose $('image: ' + $item.startdate + ' -- ' + $item.title)
                    Write-Verbose "Test-Path $destination $(Test-Path $destination)"
                    Write-Verbose "Test-Path $destinationWithMetadata $(Test-Path $destinationWithMetadata)"
                    if ($WhatIfPreference -eq $true) {
                        Write-Output "WhatIf: Downloading image from: $($item.imageurl) to: $destination"
                    }
                    else {
                        Write-Verbose "Downloading image from: $($item.imageurl) to: $destination"
                        $client.DownloadFile($item.imageurl, $destination)
                    }
                }
                $i++
                if ($i -eq $Count) { break }
                
            }
        }
            
        # Delete switch logic
        if ($Delete -and ($Count -gt 0)) {
            # We do not want to keep every file; remove the old ones
            Write-Host "Cleaning the directory..."
            $i = 1
            Get-ChildItem -Filter "*.jpg" "$Path\*" -Include "????-??-??.jpg", "????-??-??_meta.jpg" | Sort-Object -Descending FullName | ForEach-Object {
                if ($i -gt $Count) {
                    # We have more files than we want, delete the extra files
                    $fileName = $_.FullName
                    if ($WhatIfPreference -eq $true) {
                        Write-Output "Deleting file $fileName"
                    }
                    else {
                        Write-Verbose "Deleting file $fileName"
                        Remove-Item "$fileName"
                    }
                }
                $i++
            }
        }
    }
}
