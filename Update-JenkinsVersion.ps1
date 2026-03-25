<#
    .Synopsis
    Upgrades the version information in the register from the current Jenkins war file.
    .Description
    The purpose of this script is to update the version of Jenkins in the registry
    when the user may have upgraded the war file in place. The script probes the
    registry for information about the Jenkins install (path to war, etc.) and 
    then grabs the version information from the war to update the values in the
    registry so they match the version of the war file. 

    This will help with security scanners that look in the registry for versions
    of software and flag things when they are too low. The information in the 
    registry may be very old compared to what version of the war file is 
    actually installed on the system.
#>


# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    # We may be running under powershell.exe or pwsh.exe, make sure we relaunch the same one.
    $Executable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        # Launching with RunAs to get elevation
        $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
        Start-Process -FilePath $Executable -Verb Runas -ArgumentList $CommandLine
        Exit
    }
}

function New-TemporaryDirectory {
    $Parent = [System.IO.Path]::GetTempPath()
    do {
        $Name = [System.IO.Path]::GetRandomFileName()
        $Item = New-Item -Path $Parent -Name $Name -ItemType "Directory" -ErrorAction SilentlyContinue
    } while (-not $Item)
    return $Item.FullName
}

function Exit-Script($Message, $Fatal = $False) {
    $ExitCode = 0
    if($Fatal) {
        Write-Error $Message
    } else {
        Write-Host $Message
    }
    Read-Host "Press ENTER to continue"
    Exit $ExitCode
}

# Let's find the location of the war file...
$JenkinsDir = Get-ItemPropertyValue -Path HKLM:\Software\Jenkins\InstalledProducts\Jenkins -Name InstallLocation -ErrorAction SilentlyContinue

if (($Null -eq $JenkinsDir) -or [String]::IsNullOrWhiteSpace($JenkinsDir)) {
    Exit-Script -Message "Jenkins does not seem to be installed. Please verify you have previously installed using the MSI installer" -Fatal $True
}

$WarPath = Join-Path $JenkinsDir "jenkins.war"
if(-Not (Test-Path $WarPath)) {
    Exit-Script -Message "Could not find war file at location found in registry, please verify Jenkins installation" -Fatal $True
}

# Get the MANIFEST.MF file from the war file to get the version of Jenkins
$TempWorkDir = New-TemporaryDirectory
$ManifestFile = Join-Path $TempWorkDir "MANIFEST.MF"
$Zip = [IO.Compression.ZipFile]::OpenRead($WarPath)
$Zip.Entries | Where-Object { $_.Name -like "MANIFEST.MF" } | ForEach-Object { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $ManiFestFile, $True) }
$Zip.Dispose()

$JenkinsVersion = $(Get-Content $ManiFestFile | Select-String -Pattern "^Jenkins-Version:\s*(.*)" | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Select-Object -First 1)
Remove-Item -Path $ManifestFile

# Convert the Jenkins version into what should be in the registry
$VersionItems = $JenkinsVersion.Split(".") | ForEach-Object { [int]::Parse($_) }

# Use the same encoding algorithm as the installer to encode the version into the correct format 
$RegistryEncodedVersion = 0
$Major = $VersionItems[0]
if ($VersionItems.Length -le 2) {
    $Minor = 0
    if (($VersionItems.Length -gt 1) -and ($VersionItems[1] -gt 255)) {
        $Minor = $VersionItems[1]
        $RegistryEncodedVersion = $RegistryEncodedVersion -bor ((($Major -band 0xff) -shl 24) -bor 0x00ff0000 -bor (($Minor * 10) -band 0x0000ffff))
    }
    else {
        $RegistryEncodedVersion = $RegistryEncodedVersion -bor (($Major -band 0xff) -shl 24)
    }
}
else {
    $Minor = $VersionItems[1]
    if ($Minor -gt 255) {
        $RegistryEncodedVersion = $RegistryEncodedVersion -bor ((($Major -band 0xff) -shl 24) -bor 0x00ff0000 -bor ((($Minor * 10) + $VersionItems[2]) -band 0x0000ffff))
    }
    else {
        $RegistryEncodedVersion = $RegistryEncodedVersion -bor ((($Major -band 0xff) -shl 24) -bor (($Minor -band 0xff) -shl 16) -bor ($VersionItems[2] -band 0x0000ffff))
    }
}

$ProductName = "Jenkins $JenkinsVersion"

# Find the registry key for Jenkins in the Installer\Products area and CurrentVersion\Uninstall
$JenkinsProductsRegistryKey = Get-ChildItem -Path HKLM:\SOFTWARE\Classes\Installer\Products  | Where-Object { $_.GetValue("ProductName", "").StartsWith("Jenkins") }

$JenkinsUninstallRegistryKey = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall  | Where-Object { $_.GetValue("DisplayName", "").StartsWith("Jenkins") }

if (($Null -eq $JenkinsProductsRegistryKey) -or ($Null -eq $JenkinsUninstallRegistryKey)) {
    Exit-Script -Message "Could not find the product information for Jenkins" -Fatal $True
}

# Update the Installer\Products area
$RegistryPath = $JenkinsProductsRegistryKey.Name.Substring($JenkinsProductsRegistryKey.Name.IndexOf("\"))

$OldProductName = $JenkinsProductsRegistryKey.GetValue("ProductName", "")
if ($OldProductName -ne $ProductName) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "ProductName" -Type String -Value $ProductName 
}

$OldVersion = $JenkinsProductsRegistryKey.GetValue("Version", 0)
if ($OldVersion -ne $RegistryEncodedVersion) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "Version" -Type DWord -Value $RegistryEncodedVersion
}

# Update the Uninstall area
$RegistryPath = $JenkinsUninstallRegistryKey.Name.Substring($JenkinsUninstallRegistryKey.Name.IndexOf("\"))
$OldDisplayName = $JenkinsUninstallRegistryKey.GetValue("DisplayName", "")
if ($OldDisplayName -ne $ProductName) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "DisplayName" -Type String -Value $ProductName
}

$OldDisplayVersion = $JenkinsUninstallRegistryKey.GetValue("DisplayVersion", "")
$DisplayVersion = "{0}.{1}.{2}" -f ($RegistryEncodedVersion -shr 24), (($RegistryEncodedVersion -shr 16) -band 0xff), ($RegistryEncodedVersion -band 0xffff)
if ($OldDisplayVersion -ne $DisplayVersion) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "DisplayVersion" -Type String -Value $DisplayVersion
}

$OldVersion = $JenkinsUninstallRegistryKey.GetValue("Version", 0)
if ($OldVersion -ne $RegistryEncodedVersion) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "Version" -Type DWord -Value $RegistryEncodedVersion
}

$OldVersionMajor = $JenkinsUninstallRegistryKey.GetValue("VersionMajor", 0)
$VersionMajor = $RegistryEncodedVersion -shr 24
if ($OldVersionMajor -ne $VersionMajor) {

    Set-ItemProperty -Path HKLM:$RegistryPath -Name "VersionMajor" -Type DWord -Value $VersionMajor
}

$OldVersionMinor = $JenkinsUninstallRegistryKey.GetValue("VersionMinor", 0)
$VersionMinor = ($RegistryEncodedVersion -shr 16) -band 0xff
if ($OldVersionMinor -ne $VersionMinor) {
    Set-ItemProperty -Path HKLM:$RegistryPath -Name "VersionMinor" -Type DWord -Value $VersionMinor
}

Read-Host "Press ENTER to continue"

# SIG # Begin signature block
# MIIp/QYJKoZIhvcNAQcCoIIp7jCCKeoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDbyeWzg9oNvcU/
# j3Q0982rRxp4werHyv0Gv0YLxmkVkaCCDlowggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wggeiMIIFiqADAgECAhADJPGbkeizM3ep7tjv4Oh/MA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjMwNDAzMDAwMDAwWhcNMjYwNTE2
# MjM1OTU5WjCBqTELMAkGA1UEBhMCVVMxETAPBgNVBAgTCERlbGF3YXJlMRMwEQYD
# VQQHEwpXaWxtaW5ndG9uMTgwNgYDVQQKEy9DREYgQmluYXJ5IFByb2plY3QgYSBT
# ZXJpZXMgb2YgTEYgUHJvamVjdHMsIExMQzE4MDYGA1UEAxMvQ0RGIEJpbmFyeSBQ
# cm9qZWN0IGEgU2VyaWVzIG9mIExGIFByb2plY3RzLCBMTEMwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDfqgZcXDJTB5793QlJS7n18mEi24oIQM8oBEYa
# 9swJt4M/pvIyWSSKj0FIKtqOzJQAlaf1cyxOlAisOmsc6K1CCFnnFKvIlyNjRCso
# uoanpbp2Tm0YeoLZhnb71IgWKxcI0Rwida9L+sAsHvsmhWjBQiIs0iAn566nk5UM
# tucGtA4IIK516JmHP8oJxxTgB1X7epupLf0InZeCzd+p36Ct77aCh/wXAnimeBl+
# GrZ+fzHZLCxl7BYk5USiRHVAPJ/nyhqJuOdkHToplFApJBYQYAOhve4S8HWmyqKt
# oBCzeSOQPRYCLQ2bYAo/C23ldMEzEVXd1hju59ZpR4cbJOI4Uhh9tGy0NuzSGhf0
# QdG2XEFdPux/+JW47xpfe4IEkYUq3AKIaZVKWmCZQNoBNrwEmnccYp4tBCsGWO4E
# gcp6V9uChgFpOU4d22hcOxlJjJcTMduqBIskgpoZgoL8RuFXk1P3s9LzROzgJO4F
# d2GljWwDRlut5w/eUuo+++gPmawSKN7FvjvMG3DJGVFBOphwrAGGw7BQ7zSThICJ
# F7kuEFsawCdFNScZSll7FC011U6Hf/6qy/w+lEFhEPFc9GmHO2eQlD/EiU3flXex
# 3qsT0Tagv74AwJHK8Jh6E/WRa2Skqaj3IcPIkm6aZbSPGGNujjXh1KfOGq8hZ/0K
# MUQM2wIDAQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0
# TkIwHQYDVR0OBBYEFEA4cBGhmjuHUVaxlLPntLnIMLmQMA4GA1UdDwEB/wQEAwIH
# gDATBgNVHSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmlu
# Z1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hB
# Mzg0MjAyMUNBMS5jcmwwPgYDVR0gBDcwNTAzBgZngQwBBAEwKTAnBggrBgEFBQcC
# ARYbaHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMIGUBggrBgEFBQcBAQSBhzCB
# hDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFwGCCsGAQUF
# BzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJBgNVHRMEAjAA
# MA0GCSqGSIb3DQEBCwUAA4ICAQA0nYhrG8FM2LQT4e18lk9EgwvuN4ic4A87ci4b
# cxSjYmuUtM2xtsq/9mYROa+7054SbvE2JKyqkvisIb/Ks9zhTSr6hMN0PTO1fKjf
# tth5vBOc7JZTZEsMRJrjZN+zmE6M0w7R67r0TVKbOBWJeUH5g/XMOPaWH8WEEF5S
# m8f2QjmFYyi9inBD5EWBuGK9q4lfda2k2hZ5AY2IddA7apZTiD9QQH3ex/biVVr2
# Zql8TC8918EDnBTwntySMtPLP+GCp416JrQGyapolwbHRDug+hQQJ7+ie8ygWr6K
# 7aAOpvleE/Wjqkl023x6djUdMDe/MbqRDzkOU83osgN9sySIEzTPj5sH+BEjOjNo
# 5jkcPMIvLMeudoweglm+llsnnJMQNLKjik6vp0Klvc3Hphs0Iqo4oEixf5QGA1Ja
# BGsu/nBx94qGJg7zPmCDkTVR/kpbCywrpCnq5CDPMQjR8TkadzG9OUR/nr+YXDX8
# lfzH7MRxoh3dEOh10wduINeGf6FHJhNVcrf4Mts5oLFXLbKTZTPeJ+Vni2BVNOIA
# roQvMFYjIx8YZY0Z2n2xxtePSPh8fPkgH+eeAO/zvZEX0dIz+FudOpsrhO7MTrGl
# XZ5roSeSVy+ZqVngRkJaMCtsf0rd/4uRfxjnsdWWMaiBH4vDa/uI+JjwaPGMRH9C
# +U9y3DGCGvkwghr1AgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2ln
# bmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQAyTxm5HoszN3qe7Y7+DofzAN
# BglghkgBZQMEAgEFAKCB1DAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgSryF4dcs
# 7+G2EseArPHZ/z/KN04sbkO7SZGsfdIrWUgwaAYKKwYBBAGCNwIBDDFaMFigQIA+
# AEoAZQBuAGsAaQBuAHMAIABBAHUAdABvAG0AYQB0AGkAbwBuACAAUwBlAHIAdgBl
# AHIAIAAyAC4ANQA1ADahFIASaHR0cHM6Ly9qZW5raW5zLmlvMA0GCSqGSIb3DQEB
# AQUABIICAAVGXoBUvhdrEG2D5cxsADavwBVm5FPYmkviedrnUugMTRfwUjxT5Swc
# lvYB7yY03SS0j1BmB/t+9nj2TyrYZE0ajOvaCV786EmrLRKAybPNqjk+cy0b+S/t
# NicHivrNTxv+UhS6Y3bB1lOlhR9DbLWFnIAsVfXMdN+1RaTGkhVj7LGgU8sh8NbO
# fQkidZb/axhHfiKZ8h8EEH6pjwEqdq9yujLjaoO4iZFHcWD1HvdMgN3zXhkOCD0x
# g8O/6WStXpFTFjG1ruYyMtau1CfItSsEbgyXrNl1C50awvFC4UF+11CJiGFXBRce
# tIars2UIpvErft6OpXSjrg7EX77YxfVeBD+EqGurIpG7lbFhYRplC4PKwHrKjsD7
# 4QEH81IH6+C9PheeXnbvhkh8YHRwfTeu7fJ50DQ4Psfmy+huuWEoifkiymfmJD2s
# Mu1HeVyg2sMMda/rI8CqKJX6jekEK6VmHQ+csGFhE9rFeJE2DvwPOWw3BRnYLuQl
# ZPCbuVeAdyKdK0Bfb5Hupco1eNZ2ItoXERQO+AUMIxQg534bGrwVHjcLNOwE0vbn
# kyrQcFB9FK2Z2KF2Y5jKayQUkCQnRxhUnEtPHLdsAq6h/eYXX2+bjmQ4y2Tiuqy2
# 0ORHAYIH7EvdjKeYsthTMbxZqBBBUdO8wArn8h9c4UOAoY/GakomoYIXdjCCF3IG
# CisGAQQBgjcDAwExghdiMIIXXgYJKoZIhvcNAQcCoIIXTzCCF0sCAQMxDzANBglg
# hkgBZQMEAgEFADB3BgsqhkiG9w0BCRABBKBoBGYwZAIBAQYJYIZIAYb9bAcBMDEw
# DQYJYIZIAWUDBAIBBQAEIHe7z5mbOILMXimH55hW0iyo/va7/UMKKEWhvAK1VdU+
# AhBlghV6vA/Lo0zSP8Tc/yi6GA8yMDI2MDMyNDA2NTUwNlqgghM6MIIG7TCCBNWg
# AwIBAgIQCoDvGEuN8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0Ex
# MB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEy
# NTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3
# zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8Tch
# TySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWj
# FDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2Uo
# yrN0ijtUDVHRXdmncOOMA3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjP
# KHW5KqCvpSduSwhwUmotuQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KS
# uNLoZLc1Hf2JNMVL4Q1OpbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7w
# JNdoRORVbPR1VVnDuSeHVZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vW
# doUoHLWnqWU3dCCyFG1roSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOg
# rY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K
# 096V1hE0yZIXe+giAwW00aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCf
# gPf8+3mnAgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zy
# Me39/dfzkXFjGVBDz2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezL
# TjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsG
# AQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5j
# b20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNy
# dDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5j
# cmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEB
# CwUAA4ICAQBlKq3xHCcEua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZ
# D9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/
# ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu
# +WUqW4daIqToXFE/JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4o
# bEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2h
# ECZpqyU1d0IbX6Wq8/gVutDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasn
# M9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol
# /DJgddJ35XTxfUlQ+8Hggt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgY
# xQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3oc
# CVccAvlKV9jEnstrniLvUxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcB
# ZU8atufk+EMF/cWuiC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzCCBrQwggSc
# oAMCAQICEA3HrFcF/yGZLkBDIgw6SYYwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UE
# BhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2lj
# ZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1
# MDUwNzAwMDAwMFoXDTM4MDExNDIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0
# IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBALR4MdMKmEFyvjxGwBysddujRmh0tFEXnU2t
# jQ2UtZmWgyxU7UNqEY81FzJsQqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn
# 7SWCWgzbNfiR+2fkHUiljNOqnIVD/gG3SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vt
# La4+gKPsYfwEu7EEbkC9+0F2w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVwxKSpO0Xa
# F9DPfNBKS7Zazch8NF5vp7eaZ2CVNxpqumzTCNSOxm+SAWSuIr21Qomb+zzQWKhx
# KTVVgtmUPAW35xUUFREmDrMxSNlr/NsJyUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXK
# FifinT7zL2gdFpBP9qh8SdLnEut/GcalNeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3
# ZA4x5HHKS+rqBvKWxdCyQEEGcbLe1b8Aw4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F
# 20HHfIY4/6vHespYMQmUiote8ladjS/nJ0+k6MvqzfpzPDOy5y6gqztiT96Fv/9b
# H7mQyogxG9QEPHrPV6/7umw052AkyiLA6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u
# 70EwgWbVRSX1Wd4+zoFpp4Ra+MlKM2baoD6x0VR4RjSpWM8o5a6D8bpfm4CLKczs
# G7ZrIGNTAgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQW
# BBTvb1NK6eQGfHrK4pBW9i/USezLTjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/
# 57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYI
# KwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5j
# b20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9j
# cmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1Ud
# IAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEA
# F877FoAc/gc9EXZxML2+C8i1NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzS
# UGvI9NAzaoQk97frPBtIj+ZLzdp+yXdhOP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ
# 3essBS3q8nL2UwM+NMvEuBd/2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvR
# R2qKtntujB71WPYAgwPyWLKu6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOal95CHfmT
# nM4I+ZI2rVQfjXQA1WSjjf4J2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9nEC8EAqox
# W6q17r0z0noDjs6+BFo+z7bKSBwZXTRNivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9
# M+MtucVGyOxiDf06VXxyKkOirv6o02OoXN4bFzK0vlNMsvhlqgF2puE6FndlENSm
# E+9JGYxOGLS/D284NHNboDGcmWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3
# rGlHqhpB/8MluDezooIs8CVnrpHMiD2wL40mm53+/j7tFaxYKIqL0Q4ssd8xHZnI
# n/7GELH3IdvG2XlM9q7WP/UwgOkw/HQtyRN62JK4S1C8uw3PdBunvAZapsiI5YKd
# vlarEvf8EA+8hcpSM9LHJmyrxaFtoza2zNaQ9k+5t1wwggWNMIIEdaADAgECAhAO
# mxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUw
# EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
# JDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEw
# MDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxE
# aWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMT
# GERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprN
# rnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVy
# r2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4
# IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13j
# rclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4Q
# kXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQn
# vKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu
# 5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/
# 8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQp
# JYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFf
# xCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGj
# ggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/
# 57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8B
# Af8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6
# oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElE
# Um9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEB
# AHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0a
# FPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNE
# m0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZq
# aVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCs
# WKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9Fc
# rBjDTZ9ztwGpn1eqXijiuZQxggN8MIIDeAIBATB9MGkxCzAJBgNVBAYTAlVTMRcw
# FQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3Rl
# ZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhL
# jfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNjAzMjQwNjU1MDZaMCsGCyqGSIb3
# DQEJEAIMMRwwGjAYMBYEFN1iMKyGCi0wa9o4sWh5UjAH+0F+MC8GCSqGSIb3DQEJ
# BDEiBCBdWcsQsKuK2ufmA8r/cCeptbmd4nUjQyKrwXVoXlvjOjA3BgsqhkiG9w0B
# CRACLzEoMCYwJDAiBCBKoD+iLNdchMVck4+CjmdrnK7Ksz/jbSaaozTxRhEKMzAN
# BgkqhkiG9w0BAQEFAASCAgC6/3ZXa3ZATscloxJVTNzzR1mgF1xyvEy4QmCqeCpb
# 73/znwU2ZF0eWVZJOf5tfWqHhK+QtmGjtn+ZhrF/UmDCWya9/Z76pEEtA5jOsfik
# K6qrXBO8fx2aJioSDlb70fY2JXwhuEISb686fRBGxEZKa5Q+vB6XU4a1m+QKpPC6
# DCCDKaHsf93dVe54Z4NQdLIWHyufHC0HHQ5+PukZlyHFkPdf3RdSkO2/WO0Ux+Gp
# FDVvJHs2DOV2mUy7s6oKiTxn6sR3v+Ca2pE9odfUuktE/Zzb1AyQ4htTUatqX+6F
# u3GPks1MabmBNefBxf25YgvgT58ZHdpf/ixxd/ATYE8+LQISdSGhP4ACjrxdaW7D
# 5SJ4z6pTqo2zdKQ+gk50VHf8/OxEcN+vgtfbLVh23SbRy+1bjvwrQ51Zy/rSRJiX
# raePhGSJeBudUCLCfpSB0i0BAQDNPw0kX0l48YeWhqZsvfz3gv59F+G6PJIBImJ4
# NVD4H7361NHFCFBOF792x+pI1KcM9AMbkqGzS17mfunczflvVq5p7LvTR0LsI25+
# WsS4Loqlq0t+1U6VHE+IzJlxFok63gBs8zI6SFwl4pAQhZYa6b8SDv1K0wSqEsOZ
# U/jCKu0BPe9xElyPVzQQ72ZgSf27MpcpeKigep+8ZFOCUfMrtuEgYeNoE7kGa3y4
# lA==
# SIG # End signature block
