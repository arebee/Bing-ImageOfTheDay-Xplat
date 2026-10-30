# Update-BingImageOfTheDayMetadata.ps1
# Insert image data from the Bing Image of the Day feed into Bing Wallpaper images files using EXIFTOOL
#
# Copyright 2025, 2026 Richard Burte
# License: MIT license

<#
    .SYNOPSIS
    Fetch the Bing wallpaper image of the day metadata and then write into Bing Wallpaper images files using EXIFTOOL.
    Bing "Image of the Day" files are identified as matching the ????-??-??.jpg pattern in the Path

    .DESCRIPTION
    Fetch the Bing wallpaper image of the day metadata. It examines the files in the wallpaper path provided and then 
    applies metadata to them using the enhanced feed and core Bing feed.
    Requires EXIFTOOL in path. e.g. 'brew install exiftool' or 'winget install --id=OliverBetz.ExifTool'

    .PARAMETER Path
    Specify the location of an image, or a path to serch for Bing Images of the Day.
    Default: Wallpaper folder in your Pictures folder.

    .PARAMETER UseAlternateSource
    Use an alternative, non-official endpoint enumerating Bing wallpaper information. Contains many more image files than the official endpoint.
    Default: False, use Bing endpoint

    .PARAMETER Locale
    Specifies the locale of the image to download. By using the value `'auto'`, Bing will attempt to determine an applicable locale based on your IP address.
    Default value: "auto".
    
    .PARAMETER Resolution
    Specify the size of the image file. Select from the set, or use "auto" to detect.
    Default is "auto".
    
    .INPUTS
    None. You can't pipe objects to Update-BingImageOfTheDayMetadata.

    .OUTPUTS
    Writes a collection of objects, each of which contains the name, full name including path, and caption of a modified image(s) updated.
    
    .LINK
    Git Repo: https://github.com/arebee/Bing-wallpapers-x-plat
#>


function Update-BingImageOfTheDayMetadata {
    [CmdletBinding(SupportsShouldProcess)]
    Param(
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
        
        [ValidateSet(
            'auto', '800x600', '1024x768', '1280x720', '1280x768', '1366x768',
            '1920x1080', '1920x1200', '720x1280', '768x1024', '768x1280',
            '768x1366', '1080x1920', 'UHD'
        )][string]$Resolution = 'auto',
    
        [string]$Path = $(Join-Path $([Environment]::GetFolderPath("MyPictures")) "Wallpapers")
    )
    Write-Verbose ''
    Write-Verbose '===> Executing Update-BingImageOfTheDayMetadata'
    Write-Verbose ''
    $filesUpdatedCount = 0

    # URI to fetch the image locations from
    if ($Locale -eq 'auto') {
        $market = ''
    }
    else {
        $market = "&mkt=$Locale"
    }

    if ($Resolution -eq 'auto'){
        $Resolution = Get-Resolution
    }

    Write-Verbose "Resolution: $Resolution"
    
    $AltMetadataUri = 'https://api45gabs.azurewebsites.net/api/sample/bingphotos'
    $Const_Bing_Metadata_URL_1 = "https://www.bing.com/HPImageArchive.aspx?format=js$market&pid=hp&idx=0&n=8"
    $Const_Bing_Metadata_URL_2 = "https://www.bing.com/HPImageArchive.aspx?format=js$market&pid=hp&idx=8&n=8"

    # Test if EXIFTOOL is available on the path 
    if ($null -eq (get-Command -Name exiftool -ErrorAction Ignore)) {
        Write-Error "ExifTool is not available. Exiting."
        return
    }

    # Test if the Path provided is a container or leaf
    # If it is a leaf, test that its extension is in jpg or jpeg then add it to an array
    # Otherwise filter the children of the container.

    if (Test-Path -Path $Path -PathType Container) {
        # List the files that should have metadata added. Instead of examining all files we look at those that 
        # do not have _meta as the last part of the filename. This convention improves the speed of execution.
        $filesToProcess = $(Get-ChildItem -Filter "*.jpg" -Path "$Path\*" -Include "????-??-??.jpg" -Exclude "????-??-??_meta.jpg")
        if ($null -eq $filesToProcess) {
            Write-Verbose 'No files to process.'
            return
        }
    }
    else {
        # Leaf file test it ends in jpg or jpeg
        $FileInf = Get-Item -Path $Path -ErrorAction Stop
        if (($FileInf.Extension.ToLowerInvariant() -ne '.jpg') -and ($FileInf.Extension.ToLowerInvariant() -ne '.jpg')) {
            Write-Error "File is not a .jpg or .jpeg. Exiting"
            return
        }
        else {
            $filesToProcess = , $FileInf
        }
    }

    Write-Verbose "$($filesToProcess.Count) image(s) to process"
    if ($filesToProcess.Count -eq 0) { return }

    [System.Collections.ArrayList]$CombinedImageMetadata = [System.Collections.ArrayList]::new()
    
    # Fetch metadata from the Alt endpoint.
    if ($UseAlternateSource) {
        [System.Collections.ArrayList]$AltImageMetadata = [System.Collections.ArrayList]::new()
        # Fetch the metadata to apply from the Alternative endpoint.
        Write-Verbose "Try getting Alt Metadata"
        try {
            $altMetadata = ConvertFrom-Json -InputObject $(Invoke-WebRequest -Uri $AltMetadataUri -ContentType 'application/json; charset=utf-8').Content
            $AltImageMetadata.AddRange( $altMetadata )
        }
        catch {
            Write-Error "Error: Alt Metadata failed to load."
        }    
    }

    # Fetch metadata from the Bing Image of the Day endpoint.
    Write-Verbose "Getting Bing Metadata"
    [System.Collections.ArrayList]$BingMetadata = [System.Collections.ArrayList]::new()
    try {
        $BingMetadata.AddRange($(ConvertFrom-Json((Invoke-WebRequest -Uri $Const_Bing_Metadata_URL_1 -ContentType 'application/json; charset=utf-8').Content)).Images)
        $BingMetadata.AddRange($(ConvertFrom-Json((Invoke-WebRequest -Uri $Const_Bing_Metadata_URL_2 -ContentType 'application/json; charset=utf-8').Content)).Images)
    }
    catch {
        Write-Error "Error: Bing Metadata failed to load."
    }
    
    foreach ($item in $BingMetadata) {
        # Write-Verbose "Processing item $($item.startdate)"
        if ($UseAlternateSource) {
            Write-Verbose "Combining Bing and Alt metadata"
            $MatchesInCombined = $AltImageMetadata.Where({ $_.startdate -eq $item.startdate })
            if (0 -ne $MatchesInCombined.Count) {
                foreach ($match in $MatchesInCombined) {
                    Add-Member -Name desc -Type NoteProperty -Value $item.desc -InputObject $match -Force
                    Add-Member -Name caption -Type NoteProperty -Value $item.caption -InputObject $match -Force
                    Add-Member -Name copyrightonly -Type NoteProperty -Value $item.copyrightonly -InputObject $match -Force
                }
                null = $CombinedImageMetadata.AddRange($MatchesInCombined)
            }
            else {
                # Write-Verbose "No Alt feed item for $($item.startdate), using Bing metadata"
                $bingUrl = 'https://www.bing.com'
                $item.url = -join ($bingUrl, $item.url.Replace('1920x1080',$Resolution))
                $item.copyrightlink = -join ($bingUrl, $item.copyrightlink)

                $null = $CombinedImageMetadata.Add($item)
            }
        }
        else {
            # Write-Verbose "No Alt feed item for $($item.startdate), using Bing metadata"
            $bingUrl = 'https://www.bing.com'
            $item.url = -join ($bingUrl, $item.url.Replace('1920x1080',$Resolution))
            $item.copyrightlink = -join ($bingUrl, $item.copyrightlink)

            $null = $CombinedImageMetadata.Add($item)
        }
    }
    
    $processedFiles = [System.Collections.ArrayList]::new()

    # Process each file
    foreach ($file in ($filesToProcess | Sort-Object -Descending)) {
        Write-Verbose "`n"
        Write-Verbose "Processing '$($file.FullName)'"
        $existingCopyRight = exiftool -Copyright $($file.FullName)
        if ($null -ne $existingCopyRight) {
            Write-Verbose "$($file.FullName) already has copyright info"
            continue
        }
        $fileStartDate = $file.BaseName.Replace('-', '').Trim()    
        $imageMetadata = $CombinedImageMetadata.Where{ $_.startdate -eq $fileStartDate }[0]
        if (($null -eq $imageMetadata) -or ('' -eq $imageMetadata )) {
            Write-Verbose "No metadata available for $file"
            continue
        }
        
        if ($imageMetadata.PSObject.Properties.Name -contains 'desc') {
            $description = $imageMetadata.desc
            $copyright = $imageMetadata.copyrightonly
            $caption = $imageMetadata.caption
        }
        else {
            Write-Verbose "Transforming copyright info into description and copyright"
            Write-Verbose $($imageMetadata.copyright)
            $splitSourceCopyright = $imageMetadata.copyright.split('(')
            $description = $splitSourceCopyright[0].trim()
            $copyright = $splitSourceCopyright[1].substring(0, $splitSourceCopyright[1].length - 2)
            $caption = $description
        }
        
        $title = $imageMetadata.title
        
        Write-Verbose "Title: $title"
        Write-Verbose "Caption: $caption"
        Write-Verbose "Description: $description"
        Write-Verbose "Copyright: $copyright"
        Write-Verbose "Copyrightlink: $($imageMetadata.copyrightlink)"
        Write-Verbose "Url: $($imageMetadata.url)"
        
        if ($WhatIfPreference) {
            Write-Verbose "WhatIf: Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
            continue    
        }
        
        Write-Verbose "Updating $($file.FullName) to $($file.BaseName + "_meta" + $file.Extension)"
        
        # Update the file with metadata and then rename the file
        $null = exiftool -overwrite_original `
            -Description="$description" `
            -ImageTitle="$title" `
            -Subject="$caption" `
            -iptc:ObjectName="$title" `
            -iptc:Caption-Abstract="$caption" `
            -xmp:dc:source="$($imageMetadata.url)" `
            -Copyright="$copyright" `
            -CreatorWorkURL="$($imageMetadata.copyrightlink)" `
            -BaseURL="$($imageMetadata.url)" `
            -charset UTF8 -charset iptc=utf8 -charset exif=utf8 `
        $($file.FullName)
        $metafile = Rename-Item -PassThru -Path $file.FullName $($file.BaseName + "_meta" + $file.Extension)
        $filesUpdatedCount++

        $null = $processedFiles.Add([PSCustomObject]@{
                Name     = $metafile.Name
                FullName = $metafile.FullName
                Caption  = $caption
            })
    }

    Write-Verbose ""
    Write-Verbose "Summary"
    Write-Verbose "$($filesToProcess.Count) image(s) identified to process"
    Write-Verbose "$($filesUpdatedCount) image(s) updated"
    
    $processedFiles
}
