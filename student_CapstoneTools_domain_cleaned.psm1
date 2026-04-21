# student_CapstoneTools_domain_cleaned.psm1
# Domain-friendly version for the APS capstone test environment.
# Cleaned up to suppress noisy Sysmon remoting output and return one object consistently.

function New-TargetPSSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [pscredential]$Credential
    )

    New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -ErrorAction Stop
}

function Get-RemoteProcessInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [pscredential]$Credential
    )

    $session = $null
    try {
        $session = New-TargetPSSession -ComputerName $ComputerName -Credential $Credential

        Invoke-Command -Session $session -ScriptBlock {
            Get-Process | Select-Object @{Name='ComputerName';Expression={$env:COMPUTERNAME}}, ProcessName, Id, Path
        } -ErrorAction Stop
    }
    finally {
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

function Get-RemoteServiceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [pscredential]$Credential
    )

    $session = $null
    try {
        $session = New-TargetPSSession -ComputerName $ComputerName -Credential $Credential

        Invoke-Command -Session $session -ScriptBlock {
            Get-Service | Select-Object @{Name='ComputerName';Expression={$env:COMPUTERNAME}}, Name, Status, StartType, DisplayName
        } -ErrorAction Stop
    }
    finally {
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

function Install-SysmonRemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [string]$BinaryPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $session = $null
    try {
        if (-not (Test-Path -LiteralPath $BinaryPath)) {
            throw "Sysmon binary not found: $BinaryPath"
        }

        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "Sysmon config not found: $ConfigPath"
        }

        $session = New-TargetPSSession -ComputerName $ComputerName -Credential $Credential

        $binaryName = Split-Path -Path $BinaryPath -Leaf
        $configName = Split-Path -Path $ConfigPath -Leaf
        $remoteBinary = "C:\Windows\Temp\$binaryName"
        $remoteConfig = "C:\Windows\Temp\$configName"

        Copy-Item -Path $BinaryPath -Destination $remoteBinary -ToSession $session -Force -ErrorAction Stop
        Copy-Item -Path $ConfigPath -Destination $remoteConfig -ToSession $session -Force -ErrorAction Stop

        $result = Invoke-Command -Session $session -ArgumentList $remoteBinary, $remoteConfig -ScriptBlock {
            param($BinPath, $CfgPath)

            $proc = Start-Process -FilePath $BinPath `
                -ArgumentList "-accepteula -i `"$CfgPath`"" `
                -Wait `
                -PassThru `
                -WindowStyle Hidden

            $svc = Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                SysmonState  = if ($svc) { [string]$svc.Status } else { 'NotInstalled' }
                ExitCode     = $proc.ExitCode
                Error        = $null
            }
        } -ErrorAction Stop

        [pscustomobject]@{
            ComputerName = $result.ComputerName
            SysmonState  = $result.SysmonState
            ExitCode     = $result.ExitCode
            Error        = $result.Error
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName = $ComputerName
            SysmonState  = 'Failed'
            ExitCode     = $null
            Error        = $_.Exception.Message
        }
    }
    finally {
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Get-RemoteProcessInfo, Get-RemoteServiceInfo, Install-SysmonRemote
