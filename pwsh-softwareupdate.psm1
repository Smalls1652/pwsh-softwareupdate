<#
.SYNOPSIS
Gets software updates for macOS.

.DESCRIPTION
This cmdlet is a wrapper for the 'softwareupdate' cli tool built into macOS. This returns software updates available for the system as an object.

#>

function Get-SoftwareUpdate {
    [CmdletBinding()]
    param(
        [string]$UpdateType
    )

    begin {
        $softwareupdate = softwareupdate -l | Select-Object -Skip 4

        $ParseTypes = [Regex]::Matches($softwareupdate, ".{3}\*.(?<name>.*\-.)\s(?<updates>.*)", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    }

    process {

        function convertFileSize {
            param(
                $bytes
            )
    
            if ($bytes -lt 1MB) {
                return "$([Math]::Round($bytes / 1KB, 2)) KB"
            }
            elseif ($bytes -lt 1GB) {
                return "$([Math]::Round($bytes / 1MB, 2)) MB"
            }
            elseif ($bytes -lt 1TB) {
                return "$([Math]::Round($bytes / 1GB, 2)) GB"
            }
        }

        $returnUpdates = @()
        foreach ($Update in $ParseTypes) {
            $UpdateName = $Update | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "name" | Select-Object -ExpandProperty "Value"

            $ParseUpdate = [Regex]::Match(($Update | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "updates" | Select-Object -ExpandProperty "Value"), "\t(?<updatename>.*),.(?<size>\d*).{2}(?<tags>.*)")

            $UpdateSize = $ParseUpdate | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "size" | Select-Object -ExpandProperty "Value"
            $UpdateSize = convertFileSize -bytes ([convert]::ToInt32($UpdateSize) * 1KB)

            $UpdateTags = $ParseUpdate | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "tags" | Select-Object -ExpandProperty "Value"

            if ($UpdateTags) {
                $o = $UpdateTags.split(" ")
                if ($o.Count -gt 1) {

                    $UpdateTags = @()
                    foreach ($t in $o) {
                        $UpdateTags += $t.Replace("[", "").Replace("]", "")
                    }
                }
                elseif ($o.Count -eq 1) {
                    $UpdateTags = $UpdateTags.Replace("[", "").Replace("]", "")
                }
            }
            else {
                $UpdateTags = "None"
            }

            $o = $null

            $retObj = New-Object -TypeName psobject -Property @{
                "UpdateName" = $UpdateName;
                "Size"       = $UpdateSize;
                "Tags"       = $UpdateTags
            }

            $defaultOutput = "UpdateName", "Size", "Tags"
            $defaultPropertSet = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", [string[]]$defaultOutput)
            $CustomOutput = [System.Management.Automation.PSMemberInfo[]]@($defaultPropertSet)
            Add-Member -InputObject $retObj -MemberType MemberSet -Name PSStandardMembers -Value $CustomOutput

            $returnUpdates += $retObj
        }
    }

    end {
        return $returnUpdates
    }
}

<#
.SYNOPSIS
Installs software updates for macOS.

.DESCRIPTION
This cmdlet is a wrapper for the 'softwareupdate' cli tool built into macOS. This installs software updates based off the name of the update.

.PARAMETER UpdateName
The name of the update to install.

.PARAMETER DownloadOnly
Only downloads the update, so it can be installed later.

.EXAMPLE
PS > Install-SoftwareUpdate -UpdateName "macOS Mojave 10.14.3 Supplemental Update- "

.NOTES
Some updates are named weirdly, so it's best to pipe in the update from Get-SoftwareUpdate to avoid any issues.
#>

function Install-SoftwareUpdate {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)][String]$UpdateName,
        [switch]$DownloadOnly,
        [switch]$All
    )


    begin {

        $UpdateJob = {
            param(
                $a
            )

            $tmpFile = New-TemporaryFile

            Start-Process -FilePath softwareupdate -ArgumentList $a -Wait -RedirectStandardOutput $tmpFile

            $swup = Get-Content $tmpFile

            Remove-Item $tmpFile

            return $swup
        }
    }

    process {
        $swParams = @()

        switch ($DownloadOnly) {
            $true { 
                $swParams += "--download ""$($UpdateName)"""
            }
            $false {
                $swParams += "--install ""$($UpdateName)"""
            }
        }

        switch ($All) {
            $true { 
                $swParams += "--all"
            }
        }

        $updateJob = Start-Job -Name "Install-SoftwareUpdate" -ScriptBlock $UpdateJob -ArgumentList $swParams

        while ($UpdateJob.State -ne "Completed") {
            $null
        }

        $JobData = $UpdateJob | Receive-Job
    }

    end {

        switch ($DownloadOnly) {
            $true { 
                if ($JobData -contains "Done.") {
                    $DownloadFinished = $true
                }
                else {
                    $DownloadFinished = $false
                }

                return New-Object -TypeName psobject -Property @{
                    "UpdateName"   = $UpdateName;
                    "IsDownloaded" = $DownloadFinished
                }
            }
            $false {
                if ($JobData -contains "Done.") {
                    $InstallFinished = $true
                }
                else {
                    $InstallFinished = $false
                }

                return New-Object -TypeName psobject -Property @{
                    "UpdateName"  = $UpdateName;
                    "IsInstalled" = $InstallFinished
                }
            }
        }
    }
}

<#
.SYNOPSIS
Gets the software update history for macOS.

.DESCRIPTION
This cmdlet is a wrapper for the 'softwareupdate' cli tool built into macOS. This gets the software update history for the whole OS.
#>

function Get-SoftwareUpdateHistory {
    begin {
        $swupHistory = softwareupdate --history | Select-Object -Skip 2
    }
    
    process {
    
        $returnData = @()
    
        foreach ($line in $swupHistory) {
            $ParseUpdates = [regex]::Match($line, "(?<UpdateName>(?>\S+\s){1,})\s+(?<UpdateVersion>(?>\d+|\d*\.){0,}).*(?<UpdateDate>\d{2}\/\d{2}\/\d{4}),.(?<UpdateTime>\d{2}\:\d{2}\:\d{2})", [System.Text.RegularExpressions.RegexOptions]::Multiline + [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
            $UpdateName = $ParseUpdates | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "UpdateName" | Select-Object -ExpandProperty "Value"
    
            $UpdateVersion = $ParseUpdates | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "UpdateVersion" | Select-Object -ExpandProperty "Value"
    
            if (!($UpdateVersion)) {
                $UpdateVersion = "N/A"
            }
    
            $UpdateDate = $ParseUpdates | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "UpdateDate" | Select-Object -ExpandProperty "Value"
            $UpdateTime = $ParseUpdates | Select-Object -ExpandProperty "Groups" | Where-Object -Property "Name" -eq "UpdateTime" | Select-Object -ExpandProperty "Value"
    
            $UpdateDateTime = Get-Date "$($UpdateDate) $($UpdateTime)"
    
            $obj = New-Object -TypeName psobject -Property @{
                "UpdateName"  = $UpdateName.TrimEnd(" ");
                "Version"     = $UpdateVersion;
                "DateUpdated" = $UpdateDateTime
            }
    
            $defaultOutput = "UpdateName", "Version", "DateUpdated"
            $defaultPropertSet = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", [string[]]$defaultOutput)
            $CustomOutput = [System.Management.Automation.PSMemberInfo[]]@($defaultPropertSet)
            Add-Member -InputObject $obj -MemberType MemberSet -Name PSStandardMembers -Value $CustomOutput
    
            $returnData += $obj
        }
    }
    
    end {
        return $returnData
    }
}