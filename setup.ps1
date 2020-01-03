if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Output "Requires PowerShell Version 3 or newer"
    Write-Output "Upgrade PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell"
    # don't abort if invoked with iex that would close the PS session
    if ($MyInvocation.MyCommand.CommandType -eq 'Script') { Return } else { Exit 1 }
}

# make sure any other files, required by this script, are available locally
if (-not ("config.json" | Test-Path)) {
    (New-Object System.Net.WebClient).DownloadFile("https://raw.githubusercontent.com/jwinn/setup-system/master/config.json", "config.json") 
}

$config = Get-Content -Raw -Path config.json | ConvertFrom-Json

function Is-Administrator {
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-YesNoOptions { [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No") }

function Start-PSAdmin { Start-Process PowerShell -Verb RunAs }

function Install-ScoopPackage ([String]$Name, [PSCustomObject]$Config) {
    if ($null -ne $Config -and $null -ne $Config.requires) {
        Write-Host "=> Installing Prerequisites..."
        if ($null -ne $Config.requires.list) {
            foreach ($requiredPkg in $config.requires.list) {
                Install-ScoopPackage -Name $requiredPkg -Config $Config.requires.$requiredPkg
            }
        } else {
            foreach ($requiredPkg in $Config.requires) {
                Install-ScoopPackage -Name $requiredPkg
            }
        }
    }

    if ($null -ne $Config -and $null -ne $Config.preinstall) {
        Write-Host "=> Pre Install..."
        foreach ($pkgCmd in $Config.preinstall) {
            $pkgCmd
        }
    }

    scoop install $Name

    if ($null -ne $Config -and $null -ne $Config.postinstall) {
        Write-Host "=> Post Install..."
        foreach ($pkgCmd in $Config.postinstall) {
            $pkgCmd
        }
    }
}

function Install-Scoop ([PSCustomObject]$Config) {
    if (Get-Command $Config.pkg.cmd -ErrorAction SilentlyContinue) {
        Write-Host "Scoop Already Installed, Updating..."
        scoop update
        scoop update *
        Return
    }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Host -ForegroundColor Red "Scoop Requires PowerShell Version 5 or newer"
        Return
    }

    Write-Host "Installing Scoop..."
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
        iwr -useb get.scoop.sh | iex
        Write-Host -ForegroundColor green "Success"

        if ($null -ne $Config -and $null -ne $Config.pkg.postinstall) {
            Write-Host "=> Post Install..."
            foreach ($pkgCmd in $Config.pkg.postinstall) {
                $pkgCmd
            }
        }

        $yesNoOptions = Get-YesNoOptions
        $packagesYesNo = $host.UI.PromptForChoice("Install Scoop Packages?", "", $yesNoOptions, 0)
        if ($packagesYesNo -eq 0) {
            foreach ($package in $Config.packages.list) {
                Install-ScoopPackage -Name $package -Config $Config.packages.$package
            }
        }
    } catch {
        Write-Host $PSItem
        Write-Host -ForegroundColor red "Failed"
    }
}

function Install-Choclatey () {
    if (Get-Command "chocolatey" -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey Already Installed, Skipping..."
    } else {
        if ($PSVersionTable.PSVersion.Major -lt 3) {
            Write-Host -ForegroundColor Red "Chocolatey Requires PowerShell Version 3 or newer"
            Return
        }

        Write-Host "Installing Chocolatey..."
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
            Write-Host -ForegroundColor green "Success"
        } catch {
            Write-Host -ForegroundColor red "Failed"
        }
    }
}

$yesNoOptions = Get-YesNoOptions

$scoopYesNo = $host.UI.PromptForChoice("Install Scoop?", "", $yesNoOptions, 0)
if ($scoopYesNo -eq 0) {
    Install-Scoop -Config $config.windows
} else {
    Write-Host "Skipping Scoop..."
}

# Install chocolatey
$chocoYesNo = $host.UI.PromptForChoice("Install Chocolatey?", "", $yesNoOptions, 1)
if ($chocoYesNo -eq 0) {
    Install-Chocolatey
} else {
    Write-Host "Skipping Chocolatey..."
}

$wslYesNo = $host.UI.PromptForChoice("Enable WSL?", "", $yesNoOptions, 0)
if ($wslYesNo -eq 0) {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
}