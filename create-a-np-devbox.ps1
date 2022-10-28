
<#
    .SYNOPSIS
        Script for provisioning EC2's on AWS
    .DESCRIPTION
        Script for provisioning EC2 developer machines on AWS with Oracle driver and Chocolatey installer included. 
    .EXAMPLE
        To call the script see the examples in the Users/JeremyThompson/LaunchEC2DevBox.ps1 , eg:
        PS C:\> . "$PSScriptRoot\..\..\src\create-a-np-devbox.ps1" -Instances $config.InstanceSize -sub $config.SubnetId -sec $config.SecurityGroupId -accountNumb $config.AccountNumber -AccountName $config.AccountName -AccountRole $config.AccountRole -bucket $config.Bucket -githubKn $config.GithubKnownHosts -email $config.Email -KeyName $config.KeyName -InstanceP $config.InstanceProfileName -TagN $config.TagName -TagAcc $config.TagAccount -TagAppli $config.TagApplicationID -TagAppC $config.TagAppCategory -TagCostC $config.TagCostCentre -TagDesc $config.Description -TagEnv $config.Environment -TagPow $config.PowerMgt -TagTech $config.TechnicalService
    .NOTES
        Powerhshell 5 installed
        AWS Tools for Powershell installed
    .LINK

#>

#DONT CHANGE THE PARAMETERS - MAKE A CALLING SCRIPT IN THE "USERS" FOLDER!! See examples...
Param(
  [parameter(mandatory = $true, helpmessage = "Machine Instance Size")]
  [string]$InstanceSize = 't2.medium',
  [parameter(mandatory = $true, helpmessage = "String array of Subnets - VPC Subnets, eg: @('Subnets-aaaa','Subnets-bbb')")]
  [string[]]$SubnetId = @('subnet-GUID', 'subnet-GUID', 'subnet-GUID'),
  [parameter(mandatory = $true, helpmessage = "Security Group")]
  [string]$SecurityGroupId = 'sg-GUID',
  [parameter(mandatory = $true, helpmessage = "Account Number")]
  [string]$AccountNumber = 'AccountNumber',
  [parameter(mandatory = $true, helpmessage = "Account Name")]
  [string]$AccountName = 'AccountName',
  [parameter(mandatory = $true, helpmessage = "Account Role")]
  [string]$AccountRole = 'Role-AWS-devops-appstack',
  [parameter(mandatory = $true, helpmessage = "S3 GitHub Keys Bucket Name")]
  [string]$Bucket = 'bucketName',
  [parameter(mandatory = $true, helpmessage = "GitHub KnownHosts File Contents")]
  [string]$GithubKnownHosts = 'github....',
  [parameter(mandatory = $true, helpmessage = "Your Email")]
  [string]$Email = 'YourEmail',
  [parameter(mandatory = $true, helpmessage = "An existing EC2 Key Pair")]
  [string]$KeyName = 'The_Key_Pair',
  [parameter(mandatory = $true, helpmessage = "Instance Profile Name")]
  [string]$InstanceProfileName = 'HIPBaseInstanceProfile',
  [parameter(mandatory = $true, helpmessage = "Tag Name")]
  [string]$TagName = 'dev-box',
  [parameter(mandatory = $true, helpmessage = "Tag Account")]
  [string]$TagAccount = 'Account',
  [parameter(mandatory = $true, helpmessage = "Tag ApplicationID")]
  [string]$TagApplicationID = 'AppID',
  [parameter(mandatory = $true, helpmessage = "Tag AppCategory")]
  [string]$TagAppCategory = 'A',
  [parameter(mandatory = $true, helpmessage = "Tag CostCentre")]
  [string]$TagCostCentre = 'CostCentre',
  [parameter(mandatory = $true, helpmessage = "Tag Description")]
  [string]$TagDescription = 'Dev box',
  [parameter(mandatory = $true, helpmessage = "Tag TagEnvironment")]
  [string]$TagEnvironment = 'dev',
  [parameter(mandatory = $true, helpmessage = "Tag PowerMgt")]
  [string]$TagPowerMgt = 'MBHSTOPS',
  [parameter(mandatory = $true, helpmessage = "Tag TechnicalService")]
  [string]$TagTechnicalService = 'tbd',
  [parameter(ValueFromRemainingArguments = $true, mandatory = $false, helpmessage = "arraySetupFilesToInstall, in the src EC2 directory eg: visualstudiocode,python3,notepadpp,dbeaver(bucket:yourS3bucketname) ")]
  [string[]]$arraySetupFilesToInstall = ''
)

function get-the-latest-windows-ami {
  $baseYear = 2016
  try {
	  $local:ami = aws ec2 describe-images --owners amazon --filters "Name=name,Values=Windows_Server*" --query 'sort_by(Images, &CreationDate)[].Name'
    $local:ami = invoke-webrequest -uri "https://" | select -expandProperty Content
  }
  catch {
    #SSL failure
    $local:ami = invoke-webrequest -uri "http://" | select -expandProperty Content    
  }
  $local:ami.Trim()
}

function make-tagspec( [hashtable]$tags) {
  $tagspec1 = new-object Amazon.EC2.Model.TagSpecification
  $tagspec1.ResourceType = "instance"
  $tags.GetEnumerator() | % { $tagspec1.Tags.Add( @{key = $_.Key; value = $_.Value }) }
  $tagspec1
}

#Get helper utility functions
$ufFN = Resolve-Path -path "$PSScriptRoot\..\utility-functions.ps1" | select -expandProperty Path
. $ufFN


$ami = get-the-latest-windows-ami


#If its not in a domain we’ve coded the script so it will work with administrator as well:
$user = $env:username
$queueName = "build-ec2-$user"

#Choose a random subnet
if ($SubnetId.count -ge 2) {
  $stringSubnet = $SubnetId[(get-random -minimum 0 -maximum ($SubnetId.count - 1))]
}
else {
  $stringSubnet = $SubnetId[0]
}

Set-DefaultAWSRegion -Region ap-southeast-2

#UPLOAD YOUR GITHUB KEYS TEMPORARILY - THEY ARE DELETED IN THE USERDATA SCRIPT
$sshKeyPath = "C:\Users\$user\.ssh"
$privKeyFN = "$sshKeyPath\id_rsa.ppk"
$openSshKeyFN = "$sshKeyPath\id_rsa"
$pubKeyFN = "$sshKeyPath\id_rsa.pub"
$prefix = "provisioning-workspace/dev-box/$user/"
Write-S3Object -BucketName $bucket -File $openSshKeyFN -Key "$($prefix)id_rsa"
Write-S3Object -BucketName $bucket -File $pubKeyFN     -Key "$($prefix)id_rsa.pub"

$qUrl = New-SQSQueue -queuename $queueName -f

#Set/replace the UserData varaible declarations with values dynamically
$userdataFN = Resolve-Path -path "$PSScriptRoot\dev-box-userdata.ps1" | select -expandProperty Path
$userdata = get-content -path $userdataFN -raw
$userdata = $userdata -replace '<#user>', $user
$userdata = $userdata -replace '<#email>', $Email
$userdata = $userdata -replace '<#bucket>', $Bucket
$userdata = $userdata -replace '<#githubKnownHosts>', $GithubKnownHosts


$fileArr = $arraySetupFilesToInstall -join "','"
$fileArr = "@('" + $fileArr + "')"
$userdata = $userdata -replace "'<#arraySetupFilesToInstall>'", $fileArr.TrimStart("""").TrimEnd("""")

$userdata = '<powershell>' + $userdata + '</powershell>'

$params = @{
  ImageId              = $ami
  KeyName              = $KeyName
  InstanceType         = $InstanceSize
  InstanceProfile_Name = $InstanceProfileName
  SecurityGroupId      = $SecurityGroupId
  SubnetId             = $stringSubnet
  TagSpecification     = (make-tagspec -tags @{
      Name             = $TagName
      Account          = $TagAccount
      ApplicationID    = $TagApplicationID
      AppCategory      = $TagAppCategory
      CostCentre       = $TagCostCentre
      Creator          = $user
      Description      = $TagDescription
      Environment      = $TagEnvironment
      HIPVersion       = $ami
      Owner            = $Email
      PowerMgt         = $TagPowerMgt
      TechnicalService = $TagTechnicalService
    })
  UserData             = $userdata
  EncodeUserData       = $true
}
write-host "This will take about 30 minutes."
get-date | write-host
$inst = New-EC2Instance @params
$instanceId = $inst.Instances[0].InstanceId
$IP = $inst.Instances[0].PrivateIpAddress
$ok = $false
do {
  $r = Receive-SQSMessage -queueUrl $qUrl
  if ($r -ne $null) {
    $status = $r[0] | select -expandProperty Body | ConvertFrom-Json | select -expandProperty status
  }
  else {
    $status = ''
  }
  $ok = $status -ne ''
  if (-not($ok)) {
    write-host "waiting ..."
    sleep -s 10
  }
} until ($ok)
Remove-SQSQueue -queueUrl $qUrl -force
get-date | write-host
Write-Host "Dev-box created with private IP at $IP"
Write-Host "Once your done, terminate with commandlet:"
Write-Host "Remove-EC2Instance -instanceId $instanceId -force"

