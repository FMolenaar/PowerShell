PARAM(
    [string]$ComputerName = $env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN
)
$JobPrincipal = New-ScheduledTaskPrincipal -LogonType ServiceAccount -UserId SYSTEM
$jobopt = New-ScheduledJobOption
$trigger = New-JobTrigger -Daily -DaysInterval 1 -At 08:00:00 
Register-ScheduledJob -Name 'VerifyWINRMHTTPSListener'`
    -ScheduledJobOption $jobopt `
    -Trigger $trigger `
    -MaxResultCount 90 `
    -ScriptBlock {
        FUNCTION Get-Cert{
            PARAM(
                [string]$ComputerName = $env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN
            )
            Try {
                $Cert = dir cert:localmachine\my -ErrorAction Stop|Where-Object {$_.Subject -like "*$ComputerName*" -AND $_.HasPrivateKey -eq $true -AND $_.NotAfter -gt (get-date) -AND $_.EnhancedKeyUsageList -like "*Server Authentication*" -AND $_.Issuer -like "*OU=Certificate Authorities, OU=Services, O=INSIM"}
                IF($Cert -eq $null){
                    Write-Output "No Certificate Found that is valid to use" 
                    Break
                }
            }
            Catch{
                Write-Output "No Certificate Found" 
                Write-Output $Error[0].Exception
                Break
            }
            RETURN $Cert
        }
        FUNCTION ADD-WINRMHTTPSListener {
            PARAM(
                [string]$ComputerName = $env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN
            )
            Try{
                $CurrentWSMAN = get-wsmaninstance winrm/config/listener -selectorset @{Address="*";Transport="https"} -ErrorAction Stop
                If($CurrentWSMAN.CertificateThumbprint -ne (Get-Cert -ComputerName $ComputerName).Thumbprint){
                    Set-WSManInstance -ResourceURI winrm/config/listener -selectorset @{Address="*";Transport="https"} -ValueSet @{Hostname=$ComputerName;CertificateThumbprint=(Get-Cert -ComputerName $ComputerName).Thumbprint} -ErrorAction Stop
                }
                Write-Output "WSMAN Listener for HTTPS has been correctly configured"
            }
            Catch{
                If ($Error[0].Exception -like "*The service cannot find the resource identified by the resource URI and selectors*"){
                    New-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Address='*';Transport='HTTPS'} -ValueSet @{Hostname=$ComputerName;CertificateThumbprint=(Get-Cert -ComputerName $ComputerName).Thumbprint}
                }
                Else{
                    Write-Output "An Unexpected Error occured while executing"
                    Write-Output $Error[0]
                    Break
                }
            }
        }
        ADD-WINRMHTTPSListener
    } `
    
Copy-Item "C:\Users\$env:USERNAME\AppData\Local\Microsoft\Windows\PowerShell\ScheduledJobs" "C:\IMS\PSJobs"
$schJobs = Get-ScheduledJob -Name 'VerifyWINRMHTTPSListener'
((($schTask.CimInstanceProperties|where {$_.name -eq "Actions"}).value).Arguments).replace("C:\Users\$env:USERNAME\AppData\Local\Microsoft\Windows\PowerShell\ScheduledJobs","C:\IMS\PSJobs\ScheduledJobs")
Set-ScheduledJob $schJobs
$schTask = Get-ScheduledTask -TaskName 'VerifyWINRMHTTPSListener'
$schTask.Principal =$JobPrincipal
Set-ScheduledTask $schTask

(($schTask.CimInstanceProperties|where {$_.name -eq "Actions"}).value).Arguments = Get-Process
"C:\Users\$env:USERNAME\AppData\Local\Microsoft\Windows\PowerShell\ScheduledJobs","C:\IMS\PSJobs\ScheduledJobs")

$Temp = ($schTask.CimInstanceProperties.value.arguments)[0].replace("C:\Users\$env:USERNAME\AppData\Local\Microsoft\Windows\PowerShell\ScheduledJobs","C:\IMS\PSJobs\ScheduledJobs")
($schTask.CimInstanceProperties.value.arguments)[0] =$Temp