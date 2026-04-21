# CapstoneTools.psm1
# Reusable remote functions for capstone orchestration

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
        $session = New-CimSession `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -Authentication Negotiate `
            -ErrorAction Stop

        $processes = Get-CimInstance `
            -CimSession $session `
            -ClassName Win32_Process `
            -ErrorAction Stop

        foreach ($p in $processes) {
            [PSCustomObject]@{
                ComputerName = $ComputerName
                Name         = $p.Name
                ProcessId    = $p.ProcessId
                Path         = $p.ExecutablePath
            }
        }
    }
    catch {
        Write-Error "Process query failed on $ComputerName : $($_.Exception.Message)"
    }
    finally {
        if ($session) {
            Remove-CimSession $session -ErrorAction SilentlyContinue
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
        $session = New-CimSession `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -Authentication Negotiate `
            -ErrorAction Stop

        $services = Get-CimInstance `
            -CimSession $session `
            -ClassName Win32_Service `
            -ErrorAction Stop

        foreach ($svc in $services) {
            [PSCustomObject]@{
                ComputerName = $ComputerName
                Name         = $svc.Name
                State        = $svc.State
                StartMode    = $svc.StartMode
            }
        }
    }
    catch {
        Write-Error "Service query failed on $ComputerName : $($_.Exception.Message)"
    }
    finally {
        if ($session) {
            Remove-CimSession $session -ErrorAction SilentlyContinue
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
        [ValidateScript({ Test-Path $_ })]
        [string]$BinaryPath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ConfigPath
    )

    $session = $null

    try {
        $session = New-PSSession `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -Authentication Negotiate `
            -ErrorAction Stop

        Copy-Item `
            -Path $BinaryPath `
            -Destination 'C:\Windows\Temp\' `
            -ToSession $session `
            -Force `
            -ErrorAction Stop

        Copy-Item `
            -Path $ConfigPath `
            -Destination 'C:\Windows\Temp\' `
            -ToSession $session `
            -Force `
            -ErrorAction Stop

        $binaryName = Split-Path $BinaryPath -Leaf
        $configName = Split-Path $ConfigPath -Leaf

        Invoke-Command `
            -Session $session `
            -ArgumentList $binaryName, $configName `
            -ErrorAction Stop `
            -ScriptBlock {
                param($Bin, $Cfg)

                & "C:\Windows\Temp\$Bin" -accepteula -i "C:\Windows\Temp\$Cfg" | Out-Null
            }

        $state = Invoke-Command `
            -Session $session `
            -ErrorAction Stop `
            -ScriptBlock {
                $svc = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
                if ($svc) { $svc.Status } else { 'NotInstalled' }
            }

        [PSCustomObject]@{
            ComputerName = $ComputerName
            SysmonState  = $state
            Error        = $null
        }
    }
    catch {
        [PSCustomObject]@{
            ComputerName = $ComputerName
            SysmonState  = 'Failed'
            Error        = $_.Exception.Message
        }
    }
    finally {
        if ($session) {
            Remove-PSSession $session -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Get-RemoteProcessInfo, Get-RemoteServiceInfo, Install-SysmonRemote
