# Invoke-Capstone.ps1
# Thin orchestrator for remote process/service collection and optional Sysmon deployment

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [Parameter(Mandatory)]
    [pscredential]$Credential,

    [Parameter(Mandatory)]
    [string]$ModulePath,

    [switch]$DeploySysmon,

    [string]$SysmonBinary,

    [string]$SysmonConfig,

    [int]$ThrottleLimit = 5
)

begin {
    if (-not (Test-Path $ModulePath)) {
        throw "ModulePath not found: $ModulePath"
    }

    if ($DeploySysmon) {
        if (-not $SysmonBinary) {
            throw "SysmonBinary is required when -DeploySysmon is used."
        }

        if (-not $SysmonConfig) {
            throw "SysmonConfig is required when -DeploySysmon is used."
        }

        if (-not (Test-Path $SysmonBinary)) {
            throw "SysmonBinary not found: $SysmonBinary"
        }

        if (-not (Test-Path $SysmonConfig)) {
            throw "SysmonConfig not found: $SysmonConfig"
        }
    }
}

process {
    $results = $ComputerName | ForEach-Object -Parallel {
        $target = $_
        $cred   = $using:Credential
        $mod    = $using:ModulePath
        $deploy = $using:DeploySysmon
        $bin    = $using:SysmonBinary
        $cfg    = $using:SysmonConfig

        try {
            Import-Module $mod -Force -ErrorAction Stop

            $procs = Get-RemoteProcessInfo -ComputerName $target -Credential $cred
            $svcs  = Get-RemoteServiceInfo -ComputerName $target -Credential $cred

            $sysmonState = $null
            $sysmonError = $null

            if ($deploy) {
                $sysmonResult = Install-SysmonRemote `
                    -ComputerName $target `
                    -Credential $cred `
                    -BinaryPath $bin `
                    -ConfigPath $cfg

                $sysmonState = $sysmonResult.SysmonState
                $sysmonError = $sysmonResult.Error
            }

            [PSCustomObject]@{
                ComputerName = $target
                Status       = if ($sysmonState -eq 'Failed') { 'PartialFailure' } else { 'Success' }
                ProcessCount = @($procs).Count
                ServiceCount = @($svcs).Count
                SysmonState  = $sysmonState
                Error        = $sysmonError
            }
        }
        catch {
            [PSCustomObject]@{
                ComputerName = $target
                Status       = 'Failed'
                ProcessCount = 0
                ServiceCount = 0
                SysmonState  = $null
                Error        = $_.Exception.Message
            }
        }
    } -ThrottleLimit $ThrottleLimit

    $results = $results | Sort-Object ComputerName

    Write-Host ''
    Write-Host 'Results:'
    $results | Format-Table -AutoSize

    $successCount = @($results | Where-Object Status -eq 'Success').Count
    $partialCount = @($results | Where-Object Status -eq 'PartialFailure').Count
    $failedCount  = @($results | Where-Object Status -eq 'Failed').Count

    Write-Host ''
    Write-Host "Summary: $successCount succeeded, $partialCount partial failure, $failedCount failed"

    return $results
}
