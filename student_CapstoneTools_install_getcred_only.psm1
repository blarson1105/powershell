# CapstoneTools.psm1
# 170A WOAC Capstone - student submission

function Get-RemoteProcessInfo {
    param(
        [string]$ComputerName,
        [pscredential]$Credential
    )

    try {
        $session = New-CimSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -ErrorAction Stop
        $processes = Get-CimInstance -CimSession $session -ClassName Win32_Process

        foreach ($p in $processes) {
            [PSCustomObject]@{
                ComputerName = $ComputerName
                Name         = $p.Name
                ProcessId    = $p.ProcessId
                Path         = $p.ExecutablePath
            }
        }

        Remove-CimSession $session
    }
    catch {
        Write-Error "Process query failed on $ComputerName : $_"
    }
}


function Get-RemoteServiceInfo {
    param(
        [string]$ComputerName,
        [pscredential]$Credential
    )

    try {
        $session = New-CimSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -ErrorAction Stop
        $services = Get-CimInstance -CimSession $session -ClassName Win32_Service

        foreach ($s in $services) {
            [PSCustomObject]@{
                ComputerName = $ComputerName
                Name         = $s.Name
                State        = $s.State
                StartMode    = $s.StartMode
            }
        }

        Remove-CimSession $session
    }
    catch {
        Write-Error "Service query failed on $ComputerName : $_"
    }
}


function Install-SysmonRemote {
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [string]$BinaryPath,
        [string]$ConfigPath
    )

    $Credential = Get-Credential

    try {
        $session = New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -ErrorAction Stop

        Copy-Item -Path $BinaryPath -Destination 'C:\Windows\Temp\' -ToSession $session -Force
        Copy-Item -Path $ConfigPath -Destination 'C:\Windows\Temp\' -ToSession $session -Force

        $binaryName = Split-Path $BinaryPath -Leaf
        $configName = Split-Path $ConfigPath -Leaf

        Invoke-Command -Session $session -ScriptBlock {
            param($bin, $cfg)
            & "C:\Windows\Temp\$bin" -accepteula -i "C:\Windows\Temp\$cfg" | Out-Null
        } -ArgumentList $binaryName, $configName

        $state = Invoke-Command -Session $session -ScriptBlock {
            (Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue).Status
        }

        Remove-PSSession $session

        return [PSCustomObject]@{
            ComputerName = $ComputerName
            SysmonState  = $state
        }
    }
    catch {
        Write-Error "Sysmon install failed on $ComputerName : $_"
        return [PSCustomObject]@{
            ComputerName = $ComputerName
            SysmonState  = 'Failed'
        }
    }
}


Export-ModuleMember -Function Get-RemoteProcessInfo, Get-RemoteServiceInfo, Install-SysmonRemote
