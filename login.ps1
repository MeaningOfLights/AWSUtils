<#
    .SYNOPSIS
        SAML Login Tool for AWS
    .DESCRIPTION
        This powershell script is based off samlf5.python to login to AWS.
    .EXAMPLE
        Call the script: aws-login.ps1 -a <ACCOUNT_NUMBER> -i $false -l "https://idp.COMPANY.com.au/<ACCOUNT_NAME>" -role "<ROLE>", eg:

        PS C:\> .\aws-login.ps1 -a AccountNUMBER -i $false -l "https://idp.COMPANY.com.au/awsACCOUNTNAME" -role "Role-AWS-devops-appstack"

        THE CORRECT WAY TO CALL THIS SCRIPT IS VIA THE USERS FOLDER, AND MORE SPECIFICALLY FROM YOUR OWN TEAM/PROJECT REPO
    .NOTES
        Powerhshell 5 installed
        AWS Tools for Powershell installed
#>
Param(
  [string]  $account,
  [boolean] $is2FA,
  [string]  $loginUrl,
  [string]  $role = 'AUR-Resource-AWS-dpatnonprod-devops-appstack',
  [string]  $Password,
  [string]  $PINcode,
  [switch]  $quiet=$false,
  [switch]  $returnPassword=$false
  )

import-module powershell-yaml
import-module awspowershell

if (-not(Get-Command utility-functions-Hello -errorAction SilentlyContinue)) {
  . "$PSScriptRoot\utility-functions.ps1"
  }

if (-not(Get-Command yaml-utils-Hello -errorAction SilentlyContinue)) {
  . "$PSScriptRoot\yaml-utils.ps1"
  }

$COMPANYSamlUrl = 'https://idp.COMPANY.com.au/my.policy'
$COMPANYDomain  = 'aur.national.com.au'
$profile    = 'saml'

[string]$originalUserName  = $env:UserName
[string]$username  = $env:UserName
[string]$Tokencode = ''


function Query-for-secret{ param( [string]$preprompt, [string]$prompt)
  if ($preprompt) { Write-Host $preprompt }
  [string]$value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR( $(Read-Host -asSecureString $prompt)))
  $value
  }

##Check if this machine is an EC2 with an IAM profile, if it is we don't need to log in to AWS using SAML
##When we run this on a EC2 then we don't need to login as it has an IAM role assigned
#$IsAWSEC2 = IsAWSEC2
#
#if ($IsAWSEC2 -eq $False) {
#  #Check we have the username - sometime they log in using AD Federated Authentication, sonetimes its a WorkGroup with Admin access
#  if ($username -eq "administrator") {
#    $username = Query-for-secret -pre "Logged into a EC2 which is part of the WorkGroup", -prompt "What is your <ID> - Administrator isn''t going to work?"
#  } 
#  if ($username -eq "administrator") {
#    Write-Host 'Administrator isn''t going to work? - exiting script - please try again entering you <ID>'
#    exit
#  }
#}
#else {
#  #Its an EC2 with an IAM role, so we can exit because we have SAML access to AWs...
#  exit
#}


function Query-for-password{ param( [string]$preprompt)
  Query-for-secret -preprompt $preprompt -prompt 'Input password'
  }

function Query-for-passcode{ param( [boolean]$is2FA)
  if (-not($is2FA)) {
      ''
    } else {
      if (($script:PINcode -eq $null) -or ($script:PINcode -eq '')) {
        [string]$script:PINcode = Query-for-secret -prompt 'Input 4 digit PIN code OR 8 digit soft token code:'
        }
      if (($script:PINcode -eq $null) -or ($script:PINcode -eq '')) {
        Throw "Login aborted at user request."
        }
      if ($script:PINcode.length -eq 8) {
          $script:Tokencode = $script:PINcode
          $script:PINcode   = ''
        } else {
          $script:Tokencode = $null
          [string]$script:Tokencode = Query-for-secret -prompt 'Input 6 digit RSA token code:'
          if (($script:Tokencode -eq $null) -or ($script:Tokencode -eq '')) {
            Throw "Login aborted at user request."
            }
        }
      $script:PINcode + $script:Tokencode
    }
  }

function Web-POST{ param( [string]$uri, $session, [hashtable]$params)
  $resp = Invoke-WebRequest -Uri $uri -WebSession $session -Method POST -Body $params
  $resp.RawContent
  }

function Web-Nav{ param( [string]$uri, $session)
  Invoke-WebRequest -Uri $uri -WebSession $session | out-null
  }


function Get-Current-Identity{
  try {
      set-defaultawsregion -region ap-southeast-2
      $callerId = Get-STSCallerIdentity
      $currentAccount = $callerId | select -ExpandProperty Account
      $arn     = $callerId | select -ExpandProperty Arn
      # $arn == 'arn:aws:sts::STSROLE:assumed-role/Role-AWS-devops-appstack/USerName@'
      $assumed = substring-after -haystack $arn -needle 'assumed-role/'
      # $assumed == 'Role-AWS-devops-appstack/USerName@'
      $currentRoleAndUser = split-string -haystack $assumed -needle '/'
      # $roleAndUser == {left='Role-AWS-devops-appstack'; right='USerName@'}
      $currentRole = $currentRoleAndUser.left
      $currentUser = substring-before -haystack $currentRoleAndUser.right -needle '@'
      @{account=$currentAccount; role=$currentRole; user=$currentUser}
    } catch {
      @{account=''; role=''; user=''}
    }
  }

function Is-Same-Identity{ param( [hashtable]$IdentityA, [hashtable]$IdentityB)
  ($IdentityA.account -eq $IdentityB.account) -and `
  ($IdentityA.role    -eq $IdentityB.role) -and `
  ($IdentityA.user    -eq $IdentityB.user)
  }

function Extract-Saml-from-Html{ param( [string]$html)
  if ($html.IndexOf( 'name="SAMLResponse"') -ne -1) {
      $base64Value = substring-after -haystack $html -needle 'name="SAMLResponse"' |
        substring-after -needle 'value="' |
        substring-before -needle '"'
      $decoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String( $base64Value))
      [xml]$doc = $decoded
      @{doc=$doc; saml=$base64Value}
    } else {
      Write-Error "SAML response not returned."
      exit
    }
  }

function Get-Saml-Response{ param( [string]$Url, [boolean]$is2FA) # Global $password is an implied input parameter.
  $sessionEstablished = $false
  $passwordAttempts = 0
  do {
      do {
        $session = $null
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        Web-Nav -uri $Url -session $session
        $passwordNotYetAccepted = $true
        do {
          $passwordAttempts = $passwordAttempts + 1
          Write-Host "Login attempt" $passwordAttempts
          if (-not($script:Password)) { $script:Password = Query-for-password }
          if (-not($script:Password)) { Write-Error 'Aborted at user request.'}
          $resp = Web-POST -uri $COMPANYSamlUrl -session $session -params @{ username=$username;  password=$script:Password; domain=$COMPANYDomain; vhost='standard'}
          if ($resp.Contains( 'The username or password is not correct.')) {
              Write-Warning 'The username ($username) or password is not correct. Please try again, or enter empty to quit.'
              $script:Password  = ''
              $Tokencode = $null
            } else {
              $passwordNotYetAccepted = $false
            }
            if ($passwordAttempts -eq 3){
              throw "Login failed"
            }
          } while ($passwordNotYetAccepted)
          if ($resp.Contains( 'Your session could not be established.')) {
            $sessionEstablished = $false
          } else {
            $sessionEstablished = $true
          }
        } while (-not $sessionEstablished)
      if ($resp.Contains( 'F5_challenge')) {
        $passcode = Query-for-passcode -is2FA $is2FA
        $resp = Web-POST -uri $COMPANYSamlUrl -session $session -params @{ password=$passcode; vhost='standard'}
        if ($resp.Contains( 'The username or password is not correct.')) {
          Write-Warning 'The PIN or tokencode is not correct. Please try again, or enter empty to quit.'
          $script:Password  = ''
          $script:PINcode   = $null
          $Tokencode = $null
          $passcode = $null
          $sessionEstablished = $false
          }
      }
    } while (-not $sessionEstablished)
  $Tokencode = $null
  Extract-Saml-from-Html -html $resp
  }

function Get-Saml-With-Role{ param( [string]$LoginUrl, [string]$fullRole, [boolean]$is2FA)
  $role_arn      = ''
  $principal_arn = ''
  $saml = Get-Saml-Response -Url $LoginUrl -is2FA $is2FA
  $nsmgr = New-Object System.Xml.XmlNamespaceManager $saml.doc.NameTable
  $nsmgr.AddNamespace( 'p', 'urn:oasis:names:tc:SAML:2.0:protocol')
  $nsmgr.AddNamespace( 'a', 'urn:oasis:names:tc:SAML:2.0:assertion')
  foreach ($xmlnode in $saml.doc.SelectNodes( 'p:Response/a:Assertion/a:AttributeStatement/a:Attribute[@Name="https://aws.amazon.com/SAML/Attributes/Role"]/a:AttributeValue/text()', $nsmgr)) {
    $assertion = split-string -haystack $xmlnode.Value -needle ','
    if ((substring-after -haystack $assertion.left -needle '/') -eq $fullRole) {
      $role_arn      = $assertion.left
      $principal_arn = $assertion.right
      break
      }
    }
  if (($role_arn -eq '') -or ($principal_arn -eq '') -or ($Saml.saml -eq '')) {
    Write-Error "Invalid Saml"
    exit
    }
  @{arn=$role_arn; principal=$principal_arn; saml=$Saml.saml}
  }


function is-logged-in{ # Use script parameters
  $currentIdentity = Get-Current-Identity
  if ($currentIdentity['account'] -ne '') {
    if (-not($quiet)) { Write-Host "current account == $($currentIdentity['account'])" }
    if (-not($quiet)) { Write-Host "current role == $($currentIdentity['role'])" }
    }
  $requestIdentity = @{account=$account; role=$role; user=$username}
  if (Is-Same-Identity -IdentityA $currentIdentity -IdentityB $requestIdentity) {
      $true
    } else {
      $false
    }
  }

function login{ # Use script parameters
  if (-not($quiet)) {
    Write-Host "Welcome to AWS login."
    }
  if (-not($quiet) -and $is2FA) { Write-Host "Login to this role requires two-factor authentication." }
  if (-not($quiet)) { Write-Host "You are $originalUserName, if on AURDEV you will use: $username" }
  if (-not($quiet)) { Write-Host "Account is $account" }

  if (is-logged-in) {
      if (-not($quiet)) { Write-Host "You are already logged in!" }
    } else {
      if (-not($quiet)) { write-host "Not logged in yet." }
      $samlInfo = Get-Saml-With-Role -LoginUrl $loginUrl -fullRole $role -is2FA $is2FA
      $Response = Use-STSRoleWithSAML -RoleArn $samlInfo.arn -PrincipalArn $samlInfo.principal -SAMLAssertion $samlInfo.saml
      $Credentials = $Response.Credentials
      $credsFile = "C:\Users\$originalUserName\.aws\credentials"
      Set-DefaultAWSRegion -Region ap-southeast-2
      Set-AWSCredential -ProfileLocation $credsFile -StoreAs $profile `
                        -AccessKey    $Credentials.AccessKeyId `
                        -SecretKey    $Credentials.SecretAccessKey `
                        -SessionToken $Credentials.SessionToken
      Set-AWSCredential -ProfileName $profile
      $env:AWS_ACCESS_KEY_ID     = $Credentials.AccessKeyId
      $env:AWS_SECRET_ACCESS_KEY = $Credentials.SecretAccessKey
      $env:AWS_SESSION_TOKEN     = $Credentials.SessionToken
      $env:AWS_PROFILE           = $profile
      $env:AWS_DEFAULT_REGION    = 'ap-southeast-2'
      if (-not($quiet)) {
        Write-Host "Credentials set!"
        Write-Host "For python, you might consider setting ... "
        Write-Host "`$env:https_proxy = ""proxyDETAILS"""
        Write-Host "`$env:http_proxy = ""%https_proxy%"""
        Write-Host "`$env:no_proxy = ""idp.COMPANY.com.au"""
        }
    }
  if (-not( $returnPassword)) {
    $script:Password  = ''
    }
  $script:Tokencode = $null
  $Credentials = $null
  $samlInfo    = $null
  $Response    = $null
  }

# Main body of script
# =======================================================================================
login # Using script parameters
if (($returnPassword) -and ($script:Password)) {
    write-warning "Password and pincode might be stored in a powershell variable."
    @{ 'password' = $script:Password
       'pincode'  = $script:PINcode
     }
  }
  
  