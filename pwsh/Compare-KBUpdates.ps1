<#
.SYNOPSIS
    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date.

.DESCRIPTION
    This script retrieves the latest installed KB ID along with the installation date and OS build version, fetches the remote KB IDs (excluding preview updates), and compares them. It checks if the currently installed KB/OS Build is updated or counts how many updates it is behind.

.PARAMETER Verbose
    Optional parameter to write all details about retrieved data.

.EXAMPLE
    .\Compare-KBUpdates.ps1

    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date.

.EXAMPLE
    .\Compare-KBUpdates.ps1 -Verbose

    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date, with detailed output.
#>

param (
    [switch]$Verbose
)

Function Get-MyWindowsVersion {
    [CmdletBinding()]
    Param (
        $ComputerName = $env:COMPUTERNAME
    )

    $Table = New-Object System.Data.DataTable
    $Table.Columns.AddRange(@("ComputerName","Windows edition","Version","Build number"))
    $ProductName = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption | Select -ExpandProperty Caption
    Try {
        $DisplayVersion = (Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction Stop)
    } Catch {
        $DisplayVersion = "N/A"
    }
    $CurrentBuild = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild
    $UBR = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR
    $OSVersion = $CurrentBuild + "." + $UBR
    $TempTable = New-Object System.Data.DataTable
    $TempTable.Columns.AddRange(@("ComputerName","Windows edition","Version","Build number"))
    [void]$TempTable.Rows.Add($env:COMPUTERNAME,$ProductName,$DisplayVersion,$OSVersion)

    return $TempTable
}

Function Get-LatestKBUpdate {
    try {
        # Get Windows info
        $CurrentWindowsVersion = Get-MyWindowsVersion -ErrorAction Stop

        # Set the correct URL for W11 or W10
        If ($CurrentWindowsVersion.'Build number' -like "2*") {
            $URI = "https://aka.ms/Windows11UpdateHistory"
        }
        If ($CurrentWindowsVersion.'Build number' -like "1*") {
            $URI = "https://support.microsoft.com/en-gb/topic/windows-10-update-history-7dd3071a-3906-fa2c-c342-f7f86728a6e3"
        }

        # Retrieve the web pages
        If ($PSVersionTable.PSVersion.Major -ge 6) {
            $Response = Invoke-WebRequest -Uri $URI -ErrorAction Stop
        } else {
            $Response = Invoke-WebRequest -Uri $URI -UseBasicParsing -ErrorAction Stop
        }

        # Pull the version data from the HTML
        If (!($Response.Links)) { throw "Response was not parsed as HTML" }
        $VersionDataRaw = $Response.Links | where {$_.outerHTML -match "supLeftNavLink" -and $_.outerHTML -match "KB"}

        # Get the latest patch info
        $CurrentPatch = $VersionDataRaw | where {$_.outerHTML -match $CurrentWindowsVersion.'Build number'} | Select -First 1

        # Extract the KB ID from the title
        $kb = "KB" + $CurrentPatch.href.Split('/')[-1]

        # Format the date
        $dateString = $CurrentPatch.outerHTML.Split('>')[1].Replace('</a','').Replace('&#x2014;',' - ')
        $date = $null
        $dateFormats = @("MMMM d, yyyy", "MMMM dd, yyyy", "MMMM d, yyyy h:mm tt", "MMMM dd, yyyy h:mm tt", "MMMM d", "MMMM dd", "MMMM", "MMMM yyyy")
        foreach ($format in $dateFormats) {
            try {
                $date = [datetime]::ParseExact($dateString.Split(' - ')[0], $format, $null)
                break
            } catch {
                continue
            }
        }
        if ($null -eq $date) {
            throw "Failed to parse date: $dateString"
        }

        # Get the OS build version
        $osBuild = $CurrentWindowsVersion.'Build number'

        # Format the output
        $output = "$dateString (OS Builds $osBuild)"
        return [PSCustomObject]@{
            Output = $output
            KB = $kb
            OSBuild = $osBuild
            Date = $date
        }
    } catch {
        Write-Error "Failed to retrieve the latest KB update: $_"
        return $null
    }
}

Function Get-RemoteKBUpdates {
    # Fetch the content from the Windows Update History URL
    $uri = "https://aka.ms/WindowsUpdateHistory"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop

    # Extract the links from the response
    $links = $response.Links

    # Filter the links to include only those that match "supLeftNavLink" and contain "KB", and exclude those that contain "Preview"
    $filteredLinks = $links | Where-Object { $_.outerHTML -match "supLeftNavLink" -and $_.outerHTML -match "KB" -and $_.outerHTML -notmatch "Preview" }

    # Extract KB IDs and raw details
    $kbList = $filteredLinks | ForEach-Object {
        if ($_.outerHTML -match "OS Builds") {
            [PSCustomObject]@{
                RawDetails = $_.outerHTML
            }
        }
    }

    # Return the raw KB list
    return $kbList
}

Function Parse-KBDetails {
    param (
        [string]$rawDetails
    )

    $kb = $null
    $osBuilds = $null
    $date = $null

    # Extract KB ID
    if ($rawDetails -match "KB[0-9]+") {
        $kb = $matches[0]
    }

    # Extract OS Builds
    if ($rawDetails -match "OS Builds ([^<]+)") {
        $osBuilds = $matches[1] -split " and "
    }

    # Extract Date
    if ($rawDetails -match ">([^<]+)&#x2014;") {
        $dateString = $matches[1].Trim()
        $parsedDate = $null
        $dateFormats = @("MMMM d, yyyy", "MMMM dd, yyyy", "MMMM d, yyyy h:mm tt", "MMMM dd, yyyy h:mm tt", "MMMM d", "MMMM dd", "MMMM", "MMMM yyyy")
        foreach ($format in $dateFormats) {
            try {
                $parsedDate = [datetime]::ParseExact($dateString, $format, $null)
                break
            } catch {
                continue
            }
        }
        $date = $parsedDate
    }

    return [PSCustomObject]@{
        KB = $kb
        OSBuilds = $osBuilds
        Date = $date
    }
}

Function Compare-KBUpdates {
    param (
        [switch]$Verbose
    )

    # Get local installed KB ID and OS Build
    $localKBUpdate = Get-LatestKBUpdate
    if ($null -eq $localKBUpdate) {
        return
    }
    $localKB = $localKBUpdate.KB
    $localOSBuild = $localKBUpdate.OSBuild
    $localDate = $localKBUpdate.Date

    # Get remote KB IDs and OS Builds
    $remoteKBList = Get-RemoteKBUpdates
    $parsedKBList = $remoteKBList | ForEach-Object { Parse-KBDetails -rawDetails $_.RawDetails }

    if ($Verbose) {
        Write-Output "Local KB Update: $($localKBUpdate.Output)"
        Write-Output "Local KB ID: $localKB"
        Write-Output "Local OS Build: $localOSBuild"
        Write-Output "Local KB Date: $($localKBUpdate.Date.ToString('MM/dd/yyyy'))"
        Write-Output "----------------------"
        Write-Output "Remote KB List:"
        $parsedKBList | ForEach-Object { Write-Output $_ }
        Write-Output "----------------------"
    }

    # Find the index of the local KB in the remote KB list
    $localKBIndex = $parsedKBList.KB.IndexOf($localKB)
    if ($localKBIndex -ge 0) {
        $updatesBehind = $localKBIndex
        if ($Verbose) {
            Write-Output "Local KB is up to date with the latest remote KB."
            Write-Output "Days behind: 0"
            Write-Output "Latest remote KB Update: $($parsedKBList[0].KB) (OS Builds $($parsedKBList[0].OSBuilds -join ', '))"
            Write-Output "Latest remote KB ID: $($parsedKBList[0].KB)"
            Write-Output "Latest remote OS Build: $($parsedKBList[0].OSBuilds -join ', ')"
            Write-Output "Latest remote KB Date: $($parsedKBList[0].Date.ToString('MM/dd/yyyy'))"
        }
        return $updatesBehind
    }

    # If local KB is not found, calculate how many updates it is behind
    $updatesBehind = ($parsedKBList | Where-Object { $_.Date -gt $localDate }).Count
    if ($Verbose) {
        Write-Output "Local KB is behind the latest remote KB by $updatesBehind updates."
        Write-Output "Days behind: $($updatesBehind)"
        Write-Output "Latest remote KB Update: $($parsedKBList[0].KB) (OS Builds $($parsedKBList[0].OSBuilds -join ', '))"
        Write-Output "Latest remote KB ID: $($parsedKBList[0].KB)"
        Write-Output "Latest remote OS Build: $($parsedKBList[0].OSBuilds -join ', ')"
        Write-Output "Latest remote KB Date: $($parsedKBList[0].Date.ToString('MM/dd/yyyy'))"
    }
    return $updatesBehind
}

# Main section to call the function
Function Main {
    param (
        [switch]$Verbose
    )

    try {
        $result = Compare-KBUpdates -Verbose:$Verbose
        Write-Output $result
    } catch {
        Write-Error $_.Exception.Message
    }
}

# Call the main function
Main -Verbose:$Verbose