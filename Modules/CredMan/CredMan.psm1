FUNCTION Add-StoredCredential{
    <#
    .Synopsis
      Saves specified credentials for operating user
    
    .Description
      Calls Win32 CredWriteW via [PsUtils.CredMan]::CredWrite
    
    .INPUTS
    
    .OUTPUTS
      [Boolean] true if successful
      [Management.Automation.ErrorRecord] if unsuccessful or error encountered
    
    .PARAMETER Target
      Specifies the URI for which the credentials are associated
            
    .PARAMETER UserName
      Specifies the username of credential to be written
      
    .PARAMETER Password
      Specifies the password of credential to be written
      
    .PARAMETER Comment
      Allows the caller to specify the comment associated with 
      these credentials
      
    .PARAMETER CredType
      Specifies the desired credentials type; defaults to 
      "CRED_TYPE_GENERIC"
    
    .PARAMETER CredPersist
      Specifies the desired credentials storage type;
      defaults to "CRED_PERSIST_ENTERPRISE"
    #>
    PARAM(
        [Parameter(Mandatory=$false)][ValidateLength(0,32676)][String] $Target,
		[Parameter(Mandatory=$true)][ValidateLength(1,512)][String] $UserName,
		[Parameter(Mandatory=$true)][ValidateLength(1,512)][String] $Password,
		[Parameter(Mandatory=$false)][ValidateLength(0,256)][String] $Comment = [String]::Empty,
		[Parameter(Mandatory=$false)][ValidateSet("GENERIC",
												  "DOMAIN_PASSWORD",
												  "DOMAIN_CERTIFICATE",
												  "DOMAIN_VISIBLE_PASSWORD",
												  "GENERIC_CERTIFICATE",
												  "DOMAIN_EXTENDED",
												  "MAXIMUM",
												  "MAXIMUM_EX")][String] $CredType = "GENERIC",
		[Parameter(Mandatory=$false)][ValidateSet("SESSION",
												  "LOCAL_MACHINE",
												  "ENTERPRISE")][String] $CredPersist = "ENTERPRISE"
    )
    BEGIN {Add-CredentialMan |Out-Null}
    PROCESS {
        IF([String]::IsNullOrEmpty($Target)){
		$Target = $UserName
	    }
	    IF("GENERIC" -ne $CredType -and 337 -lt $Target.Length){
		    [String] $Msg = "Target field is longer ($($Target.Length)) than allowed (max 337 characters)"
		    [Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
		    [Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, 666, 'LimitsExceeded', $null)
		    RETURN $ErrRcd
	    }
        IF([String]::IsNullOrEmpty($Comment)){
            $Comment = [String]::Format("Last edited by {0}\{1} on {2}",
                                        $Env:UserDomain,
                                        $Env:UserName,
                                        $Env:ComputerName)
        }
	    #[String] $DomainName = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
	    [PsUtils.CredMan+Credential] $Cred = New-Object PsUtils.CredMan+Credential
	    SWITCH($Target -eq $UserName -and 
		        ("CRED_TYPE_DOMAIN_PASSWORD" -eq $CredType -or 
		        "CRED_TYPE_DOMAIN_CERTIFICATE" -eq $CredType)){
		            $true  {$Cred.Flags = [PsUtils.CredMan+CRED_FLAGS]::USERNAME_TARGET}
		            $false  {$Cred.Flags = [PsUtils.CredMan+CRED_FLAGS]::NONE}
	            }
	    $Cred.Type = Get-CredType $CredType
	    $Cred.TargetName = $Target
	    $Cred.UserName = $UserName
	    $Cred.AttributeCount = 0
	    $Cred.Persist = Get-CredPersist $CredPersist
	    $Cred.CredentialBlobSize = [Text.Encoding]::Unicode.GetBytes($Password).Length
	    $Cred.CredentialBlob = $Password
	    $Cred.Comment = $Comment
	    [Int] $Results = 0
    	TRY{
		    $Results = [PsUtils.CredMan]::CredWrite($Cred)
	    }
	    CATCH{
		    RETURN $_
	    }
    	IF(0 -ne $Results){
		    [String] $Msg = "Failed to write to credentials store for target '$Target' using '$UserName', '$Password', '$Comment'"
		    [Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
		    [Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, $Results.ToString("X"), $ErrorCategory[$Results], $null)
		    RETURN $ErrRcd
	    }
	    RETURN $cred
        }
    END{}
}
FUNCTION Enum-StoredCredential{
    <#
    .Synopsis
      Enumerates stored credentials for operating user
    
    .Description
      Calls Win32 CredEnumerateW via [PsUtils.CredMan]::CredEnum
    
    .INPUTS
      
    
    .OUTPUTS
      [PsUtils.CredMan+Credential[]] if successful
      [Management.Automation.ErrorRecord] if unsuccessful or error encountered
    
    .PARAMETER Filter
      Specifies the filter to be applied to the query
      Defaults to [String]::Empty
      
    #>
    PARAM(
        [Parameter(Mandatory=$false)][AllowEmptyString()][String] $Filter = [String]::Empty
    )
    BEGIN {Add-CredentialMan |Out-Null}
    PROCESS {
        [PsUtils.CredMan+Credential[]] $Creds = [Array]::CreateInstance([PsUtils.CredMan+Credential], 0)
	    [Int] $Results = 0
	    try{
	    	$Results = [PsUtils.CredMan]::CredEnum($Filter, [Ref]$Creds)
	    }
	    catch{
	    	return $_
	    }
	    switch($Results){
            0 {break}
            0x80070490 {break} #ERROR_NOT_FOUND
            default
            {
        		[String] $Msg = "Failed to enumerate credentials store for user '$Env:UserName'"
        		[Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
        		[Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, $Results.ToString("X"), $ErrorCategory[$Results], $null)
        		return $ErrRcd
            }
	    }
	    return $Creds
    }
    END{}
}
FUNCTION Remove-StoredCredential{
    <#
    .Synopsis
      Deletes the specified credentials
    
    .Description
      Calls Win32 CredDeleteW via [PsUtils.CredMan]::CredDelete
    
    .INPUTS
      See function-level notes
    
    .OUTPUTS
      0 or non-0 according to action success
      [Management.Automation.ErrorRecord] if error encountered
    
    .PARAMETER Target
      Specifies the URI for which the credentials are associated
      
    .PARAMETER CredType
      Specifies the desired credentials type; defaults to 
      "CRED_TYPE_GENERIC"
    #>

    PARAM(
        [Parameter(Mandatory=$true)][ValidateLength(1,32767)][String] $Target,
		[Parameter(Mandatory=$false)][ValidateSet("GENERIC",
												  "DOMAIN_PASSWORD",
												  "DOMAIN_CERTIFICATE",
												  "DOMAIN_VISIBLE_PASSWORD",
												  "GENERIC_CERTIFICATE",
												  "DOMAIN_EXTENDED",
												  "MAXIMUM",
												  "MAXIMUM_EX")][String] $CredType = "GENERIC"
    )
    BEGIN {Add-CredentialMan|Out-Null}
    PROCESS {
        [Int] $Results = 0
	    TRY{
		    $Results = [PsUtils.CredMan]::CredDelete($Target, $(Get-CredType $CredType))
	    }
	    CATCH{
		    RETURN $_
        }
	    IF(0 -ne $Results){
		    [String] $Msg = "Failed to delete credentials store for target '$Target'"
		    [Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
		    [Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, $Results.ToString("X"), $ErrorCategory[$Results], $null)
		    RETURN $ErrRcd
	    }
	    #RETURN $Results
    }
    END{}
}
FUNCTION Get-StoredCredential{
    <#
    .Synopsis
      Reads specified credentials for operating user
    
    .Description
      Calls Win32 CredReadW via [PsUtils.CredMan]::CredRead
    
    .INPUTS
    
    .OUTPUTS
      [PsUtils.CredMan+Credential] if successful
      [Management.Automation.ErrorRecord] if unsuccessful or error encountered
    
    .PARAMETER Target
      Specifies the URI for which the credentials are associated
      this must match the internet of networkaddress from credential manager.
      if you don't know use Enum-StoredCredential to enumerate all stored objects
      
    .PARAMETER CredType
      Specifies the desired credentials type; defaults to 
      "CRED_TYPE_GENERIC"
    #>
    Param(
		[Parameter(Mandatory=$true)][ValidateLength(1,32767)][String] $Target,
		[Parameter(Mandatory=$false)][ValidateSet("GENERIC",
												  "DOMAIN_PASSWORD",
												  "DOMAIN_CERTIFICATE",
												  "DOMAIN_VISIBLE_PASSWORD",
												  "GENERIC_CERTIFICATE",
												  "DOMAIN_EXTENDED",
												  "MAXIMUM",
												  "MAXIMUM_EX")][String] $CredType = "GENERIC"
	)
    BEGIN{Add-CredentialMan|Out-Null}
    PROCESS{
        IF("GENERIC" -ne $CredType -and 337 -lt $Target.Length){
	        [String] $Msg = "Target field is longer ($($Target.Length)) than allowed (max 337 characters)"
	        [Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
	        [Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, 666, 'LimitsExceeded', $null)
	        return $ErrRcd
	    }
	    [PsUtils.CredMan+Credential] $Cred = New-Object PsUtils.CredMan+Credential
        [Int] $Results = 0
	    TRY{
	    	$Results = [PsUtils.CredMan]::CredRead($Target, $(Get-CredType $CredType), [Ref]$Cred)
	    }
	    CATCH{
	    	RETURN $_
	    }
	    
	    SWITCH($Results)
	    {
            0 {break}
            0x80070490 {return $null} #ERROR_NOT_FOUND
            default{
        		[String] $Msg = "Error reading credentials for target '$Target' from '$Env:UserName' credentials store"
        		[Management.ManagementException] $MgmtException = New-Object Management.ManagementException($Msg)
        		[Management.Automation.ErrorRecord] $ErrRcd = New-Object Management.Automation.ErrorRecord($MgmtException, $Results.ToString("X"), $ErrorCategory[$Results], $null)
        		RETURN $ErrRcd
            }
	    }
	    RETURN $Cred
    }
    END{}

}
FUNCTION Add-CredentialMan{
#region Inline C#
[String] $PsCredmanUtils = @"
using System;
using System.Runtime.InteropServices;

namespace PsUtils
{
    public class CredMan
    {
        #region Imports
        // DllImport derives from System.Runtime.InteropServices
        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode)]
        private static extern bool CredDeleteW([In] string target, [In] CRED_TYPE type, [In] int reservedFlag);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode)]
        private static extern bool CredEnumerateW([In] string Filter, [In] int Flags, out int Count, out IntPtr CredentialPtr);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredFree")]
        private static extern void CredFree([In] IntPtr cred);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredReadW", CharSet = CharSet.Unicode)]
        private static extern bool CredReadW([In] string target, [In] CRED_TYPE type, [In] int reservedFlag, out IntPtr CredentialPtr);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredWriteW", CharSet = CharSet.Unicode)]
        private static extern bool CredWriteW([In] ref Credential userCredential, [In] UInt32 flags);
        #endregion

        #region Fields
        public enum CRED_FLAGS : uint
        {
            NONE = 0x0,
            PROMPT_NOW = 0x2,
            USERNAME_TARGET = 0x4
        }

        public enum CRED_ERRORS : uint
        {
            ERROR_SUCCESS = 0x0,
            ERROR_INVALID_PARAMETER = 0x80070057,
            ERROR_INVALID_FLAGS = 0x800703EC,
            ERROR_NOT_FOUND = 0x80070490,
            ERROR_NO_SUCH_LOGON_SESSION = 0x80070520,
            ERROR_BAD_USERNAME = 0x8007089A
        }

        public enum CRED_PERSIST : uint
        {
            SESSION = 1,
            LOCAL_MACHINE = 2,
            ENTERPRISE = 3
        }

        public enum CRED_TYPE : uint
        {
            GENERIC = 1,
            DOMAIN_PASSWORD = 2,
            DOMAIN_CERTIFICATE = 3,
            DOMAIN_VISIBLE_PASSWORD = 4,
            GENERIC_CERTIFICATE = 5,
            DOMAIN_EXTENDED = 6,
            MAXIMUM = 7,      // Maximum supported cred type
            MAXIMUM_EX = (MAXIMUM + 1000),  // Allow new applications to run on old OSes
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct Credential
        {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public string TargetName;
            public string Comment;
            public DateTime LastWritten;
            public UInt32 CredentialBlobSize;
            public string CredentialBlob;
            public CRED_PERSIST Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential
        {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public IntPtr TargetName;
            public IntPtr Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public IntPtr TargetAlias;
            public IntPtr UserName;
        }
        #endregion

        #region Child Class
        private class CriticalCredentialHandle : Microsoft.Win32.SafeHandles.CriticalHandleZeroOrMinusOneIsInvalid
        {
            public CriticalCredentialHandle(IntPtr preexistingHandle)
            {
                SetHandle(preexistingHandle);
            }

            private Credential XlateNativeCred(IntPtr pCred)
            {
                NativeCredential ncred = (NativeCredential)Marshal.PtrToStructure(pCred, typeof(NativeCredential));
                Credential cred = new Credential();
                cred.Type = ncred.Type;
                cred.Flags = ncred.Flags;
                cred.Persist = (CRED_PERSIST)ncred.Persist;

                long LastWritten = ncred.LastWritten.dwHighDateTime;
                LastWritten = (LastWritten << 32) + ncred.LastWritten.dwLowDateTime;
                cred.LastWritten = DateTime.FromFileTime(LastWritten);

                cred.UserName = Marshal.PtrToStringUni(ncred.UserName);
                cred.TargetName = Marshal.PtrToStringUni(ncred.TargetName);
                cred.TargetAlias = Marshal.PtrToStringUni(ncred.TargetAlias);
                cred.Comment = Marshal.PtrToStringUni(ncred.Comment);
                cred.CredentialBlobSize = ncred.CredentialBlobSize;
                if (0 < ncred.CredentialBlobSize)
                {
                    cred.CredentialBlob = Marshal.PtrToStringUni(ncred.CredentialBlob, (int)ncred.CredentialBlobSize / 2);
                }
                return cred;
            }

            public Credential GetCredential()
            {
                if (IsInvalid)
                {
                    throw new InvalidOperationException("Invalid CriticalHandle!");
                }
                Credential cred = XlateNativeCred(handle);
                return cred;
            }

            public Credential[] GetCredentials(int count)
            {
                if (IsInvalid)
                {
                    throw new InvalidOperationException("Invalid CriticalHandle!");
                }
                Credential[] Credentials = new Credential[count];
                IntPtr pTemp = IntPtr.Zero;
                for (int inx = 0; inx < count; inx++)
                {
                    pTemp = Marshal.ReadIntPtr(handle, inx * IntPtr.Size);
                    Credential cred = XlateNativeCred(pTemp);
                    Credentials[inx] = cred;
                }
                return Credentials;
            }

            override protected bool ReleaseHandle()
            {
                if (IsInvalid)
                {
                    return false;
                }
                CredFree(handle);
                SetHandleAsInvalid();
                return true;
            }
        }
        #endregion

        #region Custom API
        public static int CredDelete(string target, CRED_TYPE type)
        {
            if (!CredDeleteW(target, type, 0))
            {
                return Marshal.GetHRForLastWin32Error();
            }
            return 0;
        }

        public static int CredEnum(string Filter, out Credential[] Credentials)
        {
            int count = 0;
            int Flags = 0x0;
            if (string.IsNullOrEmpty(Filter) ||
                "*" == Filter)
            {
                Filter = null;
                if (6 <= Environment.OSVersion.Version.Major)
                {
                    Flags = 0x1; //CRED_ENUMERATE_ALL_CREDENTIALS; only valid is OS >= Vista
                }
            }
            IntPtr pCredentials = IntPtr.Zero;
            if (!CredEnumerateW(Filter, Flags, out count, out pCredentials))
            {
                Credentials = null;
                return Marshal.GetHRForLastWin32Error(); 
            }
            CriticalCredentialHandle CredHandle = new CriticalCredentialHandle(pCredentials);
            Credentials = CredHandle.GetCredentials(count);
            return 0;
        }

        public static int CredRead(string target, CRED_TYPE type, out Credential Credential)
        {
            IntPtr pCredential = IntPtr.Zero;
            Credential = new Credential();
            if (!CredReadW(target, type, 0, out pCredential))
            {
                return Marshal.GetHRForLastWin32Error();
            }
            CriticalCredentialHandle CredHandle = new CriticalCredentialHandle(pCredential);
            Credential = CredHandle.GetCredential();
            return 0;
        }

        public static int CredWrite(Credential userCredential)
        {
            if (!CredWriteW(ref userCredential, 0))
            {
                return Marshal.GetHRForLastWin32Error();
            }
            return 0;
        }

        #endregion

        private static int AddCred()
        {
            Credential Cred = new Credential();
            string Password = "Password";
            Cred.Flags = 0;
            Cred.Type = CRED_TYPE.GENERIC;
            Cred.TargetName = "Target";
            Cred.UserName = "UserName";
            Cred.AttributeCount = 0;
            Cred.Persist = CRED_PERSIST.ENTERPRISE;
            Cred.CredentialBlobSize = (uint)Password.Length;
            Cred.CredentialBlob = Password;
            Cred.Comment = "Comment";
            return CredWrite(Cred);
        }

        private static bool CheckError(string TestName, CRED_ERRORS Rtn)
        {
            switch(Rtn)
            {
                case CRED_ERRORS.ERROR_SUCCESS:
                    Console.WriteLine(string.Format("'{0}' worked", TestName));
                    return true;
                case CRED_ERRORS.ERROR_INVALID_FLAGS:
                case CRED_ERRORS.ERROR_INVALID_PARAMETER:
                case CRED_ERRORS.ERROR_NO_SUCH_LOGON_SESSION:
                case CRED_ERRORS.ERROR_NOT_FOUND:
                case CRED_ERRORS.ERROR_BAD_USERNAME:
                    Console.WriteLine(string.Format("'{0}' failed; {1}.", TestName, Rtn));
                    break;
                default:
                    Console.WriteLine(string.Format("'{0}' failed; 0x{1}.", TestName, Rtn.ToString("X")));
                    break;
            }
            return false;
        }

        /*
         * Note: the Main() function is primarily for debugging and testing in a Visual 
         * Studio session.  Although it will work from PowerShell, it's not very useful.
         */
        public static void Main()
        {
            Credential[] Creds = null;
            Credential Cred = new Credential();
            int Rtn = 0;

            Console.WriteLine("Testing CredWrite()");
            Rtn = AddCred();
            if (!CheckError("CredWrite", (CRED_ERRORS)Rtn))
            {
                return;
            }
            Console.WriteLine("Testing CredEnum()");
            Rtn = CredEnum(null, out Creds);
            if (!CheckError("CredEnum", (CRED_ERRORS)Rtn))
            {
                return;
            }
            Console.WriteLine("Testing CredRead()");
            Rtn = CredRead("Target", CRED_TYPE.GENERIC, out Cred);
            if (!CheckError("CredRead", (CRED_ERRORS)Rtn))
            {
                return;
            }
            Console.WriteLine("Testing CredDelete()");
            Rtn = CredDelete("Target", CRED_TYPE.GENERIC);
            if (!CheckError("CredDelete", (CRED_ERRORS)Rtn))
            {
                return;
            }
            Console.WriteLine("Testing CredRead() again");
            Rtn = CredRead("Target", CRED_TYPE.GENERIC, out Cred);
            if (!CheckError("CredRead", (CRED_ERRORS)Rtn))
            {
                Console.WriteLine("if the error is 'ERROR_NOT_FOUND', this result is OK.");
            }
        }
    }
}
"@
    #endregion
    
    $PsCredMan = $null
    try{
    	$PsCredMan = [PsUtils.CredMan]
    }
    catch{
    	#only remove the error we generate
    	#$Error.RemoveAt($Error.Count-1)
    }
    if($null -eq $PsCredMan){
    	Add-Type $PsCredmanUtils
    }
    #endregion
    RETURN $PsCredMan
}
FUNCTION Get-CredType{
	Param(
		[Parameter(Mandatory=$true)][ValidateSet("GENERIC",
												  "DOMAIN_PASSWORD",
												  "DOMAIN_CERTIFICATE",
												  "DOMAIN_VISIBLE_PASSWORD",
												  "GENERIC_CERTIFICATE",
												  "DOMAIN_EXTENDED",
												  "MAXIMUM",
												  "MAXIMUM_EX")][String] $CredType = "GENERIC"
	)
    BEGIN{}
	PROCESS{
        switch($CredType){
		    "GENERIC" {return [PsUtils.CredMan+CRED_TYPE]::GENERIC}
		    "DOMAIN_PASSWORD" {return [PsUtils.CredMan+CRED_TYPE]::DOMAIN_PASSWORD}
		    "DOMAIN_CERTIFICATE" {return [PsUtils.CredMan+CRED_TYPE]::DOMAIN_CERTIFICATE}
		    "DOMAIN_VISIBLE_PASSWORD" {return [PsUtils.CredMan+CRED_TYPE]::DOMAIN_VISIBLE_PASSWORD}
		    "GENERIC_CERTIFICATE" {return [PsUtils.CredMan+CRED_TYPE]::GENERIC_CERTIFICATE}
		    "DOMAIN_EXTENDED" {return [PsUtils.CredMan+CRED_TYPE]::DOMAIN_EXTENDED}
		    "MAXIMUM" {return [PsUtils.CredMan+CRED_TYPE]::MAXIMUM}
		    "MAXIMUM_EX" {return [PsUtils.CredMan+CRED_TYPE]::MAXIMUM_EX}
	    }
    }
    END {}
}
FUNCTION Get-CredPersist{
	Param(
		[Parameter(Mandatory=$true)][ValidateSet("SESSION",
												  "LOCAL_MACHINE",
												  "ENTERPRISE")][String] $CredPersist = "ENTERPRISE"
    )
	BEGIN{}
	PROCESS{
        switch($CredPersist)
	    {
	    	"SESSION" {return [PsUtils.CredMan+CRED_PERSIST]::SESSION}
	    	"LOCAL_MACHINE" {return [PsUtils.CredMan+CRED_PERSIST]::LOCAL_MACHINE}
	    	"ENTERPRISE" {return [PsUtils.CredMan+CRED_PERSIST]::ENTERPRISE}
	    }
    }
    END {}
}

New-Alias -Name Update-StoredCredential -Value Add-StoredCredential -ErrorAction SilentlyContinue
Export-ModuleMember Enum-StoredCredential
Export-ModuleMember Remove-StoredCredential
Export-ModuleMember Add-StoredCredential -Alias Update-StoredCredential
Export-ModuleMember GET-StoredCredential
