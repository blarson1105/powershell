# student_Invoke-Capstone_domain.ps1
# Domain-friendly orchestrator for the APS capstone test environment.

[CmdletBinding()]
param(
    [string[]]$ComputerName = @('WOIC-PwSh-PE'),
    [pscredential]$Credential,
    [string]$ModulePath = '.\student_CapstoneTools_domain.psm1',
    [switch]$DeploySysmon,
    [string]$SysmonBinary,
    [string]$SysmonConfig
)

$ErrorActionPreference = 'Stop'

if (-not $Credential) {
    $Credential = Get-Credential -UserName 'Student' -Message 'Enter the credential for the remote target.'
}

$resolvedModulePath = (Resolve-Path -Path $ModulePath).Path
Import-Module -Name $resolvedModulePath -Force

$results = foreach ($target in $ComputerName) {
    try {
        $processes = Get-RemoteProcessInfo -ComputerName $target -Credential $Credential
        $services  = Get-RemoteServiceInfo -ComputerName $target -Credential $Credential

        $sysmonState = $null
        $sysmonError = $null

        if ($DeploySysmon) {
            $sysmonResult = Install-SysmonRemote -ComputerName $target -Credential $Credential -BinaryPath $SysmonBinary -ConfigPath $SysmonConfig
            $sysmonState = $sysmonResult.SysmonState
            $sysmonError = $sysmonResult.Error
        }

        [pscustomobject]@{
            ComputerName = $target
            Status       = 'Success'
            ProcessCount = @($processes).Count
            ServiceCount = @($services).Count
            SysmonState  = $sysmonState
            Error        = $sysmonError
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName = $target
            Status       = 'Failed'
            ProcessCount = 0
            ServiceCount = 0
            SysmonState  = $null
            Error        = $_.Exception.Message
        }
    }
}

""
'Results:'
$results | Format-Table -AutoSize
""
"$((@($results | Where-Object Status -eq 'Success')).Count) succeeded, $((@($results | Where-Object Status -eq 'Failed')).Count) failed"

$results
