

[string]$user = '<#user>'
[string]$email = '<#email>'
[string]$bucket = '<#bucket>'
[string]$githubKnownHosts = '<#githubKnownHosts>'
[string[]]$arraySetupFilesToInstall = '<#arraySetupFilesToInstall>'

$repoOwner = 'RepoName'
$queueName = "build-ec2-$user"
$path = "C:\temp\"

#Powershell Logging
Start-Transcript -Path "C:\temp\InstallTransript.txt"

Write-Host 'Install Chocolatey'
Set-ExecutionPolicy Bypass -Scope Process -Force; 
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

Write-Host 'Install NuGet, Git, SSH Keys directory and set region'
choco install git -y
$newPath = "$($env:PATH)C:\Program Files\Git\cmd;"
[Environment]::SetEnvironmentVariable( 'PATH', $newPath, "Machine")
$env:PATH = $newPath
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
install-module posh-git -force
import-module awspowershell
New-Item -ItemType Directory -Force -Path 'C:\Users\Administrator\.ssh' | out-null
$destinDir = "C:\Users\$($env:username)\.ssh"
$prefix = "provisioning-workspace/dev-box/$user/"
set-defaultawsregion -region ap-southeast-2
if ($user) {
  Write-Host 'Download GitHub Keys: Copy-S3Object -bucketname ' + $bucket + ' -key ' + $($prefix) + 'id_rsa -localfile ' + $destinDir + '\id_rsa'
  Copy-S3Object -bucketname $bucket -key "$($prefix)id_rsa" -localfile $destinDir\id_rsa -region ap-southeast-2
  Copy-S3Object -bucketname $bucket -key "$($prefix)id_rsa.pub" -localfile $destinDir\id_rsa.pub -region ap-southeast-2

  Write-Host 'Remove GitHub Keys: -key ' + $($prefix) + 'id_rsa'
  Remove-S3Object -bucketname $bucket -key "$($prefix)id_rsa" -force -region ap-southeast-2
  Remove-S3Object -bucketname $bucket -key "$($prefix)id_rsa.pub" -force -region ap-southeast-2

  Write-Host 'Save the GitHub Known_Hosts file'
  add-content -path "$destinDir\known_hosts" `
    -value $githubKnownHosts
  git config --global user.email $email
  git config --global user.name  $user
}

if ($user) {
  Write-Host 'Create and cd to Dev Share Directory'
  $devDir = 'C:\DEV'
  new-item -itemtype directory -force -path $devDir | out-null
  cd $devDir
  Write-Host 'Execute git clone git@git.com:' + $repoOwner + '/AWSPowershell.git'
  git clone git@git.com:$repoOwner/AWSPowershell.git
  $installDir =  $devDir + "\AWSPowershell\src\EC2"
  
  $arraySetupFilesToInstall | ForEach {
    try
    {
      $_ = $_.Trim()
      if ($_.EndsWith(")")) {
        $parameter = $_.Substring($_.IndexOf("("))
        $setupFileName = $_.Replace($parameter, '')        
        $parameter = $parameter.TrimStart("(").TrimEnd(")")
        $paramArr = $parameter.Split(",")
      
        $argumentList = @()
        $paramArr | ForEach {
          $arr = $_.Split("=")
          $arr[1] =  $arr[1].Trim()
          if ($arr[1].Contains(" ")){
            $argumentList += (" -" + $arr[0].Trim() + " `"" + $arr[1] + "`"")
          }
          else {
            $argumentList += (" -" + $arr[0].Trim() + " " + $arr[1].Trim())              
          }
        }
        $Command = "$installDir\setup-$setupFileName.ps1"
        Write-Host "& `"$Command`" $argumentList"
        Invoke-Expression "& `"$Command`" $argumentList"
      }
      else {
        $Command = "$installDir\setup-$_" + ".ps1"
        Write-Host  "$Command"
        Invoke-Expression "$Command"
      }
    }
    catch [Exception]
    {
      Write-Host "Error:" + $_.Exception|format-list -force
    }
  }
}


Write-Host 'Send-SQSMessage -queueUrl $qUrl'
$qUrl = New-SQSQueue -queuename $queueName -f
Send-SQSMessage -queueUrl $qUrl -MessageBody '{"status": "DONE"}'

Stop-Transcript

