# Attach to your client script, with a statement like ...
# if (-not(Get-Command utility-functions-Hello -errorAction SilentlyContinue)) {
#   . "C:\DEV\General\Automation\Scripts\utility-functions.ps1"
#   }

import-module awspowershell
import-module powershell-yaml
import-module posh-ssh

function utility-functions-Hello {
  Write-Host "Hello from $($MyInvocation.MyCommand.Name)"
  }


$putty = 'G:\IT\Secure\Development\Installation Software & Downloads\Network tools\putty\0.71\64-bit\putty.exe'
$baseOfSecretDocuments = 'S:\Shared Documents\IT Secure\AWS'

function set-putty-location( [string]$puttyNewValue) {
  if (-not(test-path -path $puttyNewValue)) { throw "Not putty at $puttyNewValue" }
  $script:putty = $puttyNewValue
  }

function set-base-of-secrets-location( [string]$baseOfSecretDocumentsNewValue) {
  $script:baseOfSecretDocuments = $baseOfSecretDocumentsNewValue
  }

function split-string{ param( [Parameter( ValueFromPipeline=$true)] [string[]]$haystack, [string]$needle)
  # If the needle is not present, we deem the left bit to take up the whole haystack.
  forEach ($input in $haystack) {
    $pos = $input.IndexOf( $needle)
    if ($pos -ne -1) {
        $leftBit  = $input.Substring( 0, $pos)
        $middle   = $needle
        $rightBit = $input.Substring( $pos+$needle.length)
      } else {
        $leftBit  = $input
        $middle   = ''
        $rightBit = ''
      }
    @{left=$leftBit; middle=$middle; right=$rightBit}
    }
  }

function substring-before{ param( [Parameter( ValueFromPipeline=$true)] [string[]]$haystack, [string]$needle)
  # If the needle is not present, return the whole haystack.
  split-string -haystack $haystack -needle $needle | %{ $_.left }
  }

function substring-after{ param( [Parameter( ValueFromPipeline=$true)] [string[]]$haystack, [string]$needle)
  # If the needle is not present, return empty.
  split-string -haystack $haystack -needle $needle | %{ $_.right }
  }

function hasProperty{ param( [Parameter( ValueFromPipeline=$true)] $object, [string]$name)
  $name -in $object.PSobject.Properties.Name
  }

function Read-String{ param( [xml]$doc, [string]$path)
  Select-Xml -Xml $doc -XPath $path |
    select -ExpandProperty Node |
    %{ $n = $_
       if (hasProperty -object $n -name Data) {$textProp = 'Data'} else {$textProp = '#text'}
       select -InputObject $n -ExpandProperty $textProp
     }
  }



function read-hashtable{ param( [hashtable]$doc, [string]$path, [string]$default)
  $run = $doc
  foreach ($particle in $path.split('.')) {
    if ($run -ne $null) {
      $run = $run[$particle]
	  }
	if ($run -eq $null) { break }
    }
  if ($run -eq $null) { $run = $default }
  if ($run -eq $ThrowError) {
      throw "Path $path not found where expected."
	} else {
      $run
	}
  }

function Get-StringHash([String] $String,$HashName = "SHA-256") {
  $StringBuilder = New-Object System.Text.StringBuilder
  [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))|%{
    [Void]$StringBuilder.Append($_.ToString("x2"))
    }
  $StringBuilder.ToString()
  }


function Write-Host-Table( [String]$caption, [hashtable[]]$dataset, [String]$sortColumn, [string]$columns) {
  if ($caption -ne '') {
    Write-Host $caption
    Write-Host "$($caption -replace '.','=')"
	}
  if ($dataset.length -eq 0) {
      Write-Host "table empty"
    } else {
	  if ($sortColumn -ne '') {
	      [array]$sorted = $dataset | sort-object {$_[$sortColumn]}
	    } else {
	      [array]$sorted = $dataset
		}
	  $sorted |
        %{ new-object PSObject -property $_ } |
        format-table -autosize -property $columns.split(',') |
        Out-String | %{ Write-Host $_ }
	}
  Write-Host ""
  }

try {
  Add-Type -errorAction SilentlyContinue @"
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.Globalization;

    public class HashtableComparer: IComparer, IComparer<Hashtable>
    {

        private static readonly CompareInfo compareInfo = CompareInfo.GetCompareInfo(CultureInfo.InvariantCulture.Name);

        public int Compare(object x, object y)
        {
            return Compare(x as Hashtable, y as Hashtable);
        }
        public int Compare(Hashtable x, Hashtable y)
        {
            return compareInfo.Compare(x["sortKey"] as string, y["sortKey"] as string, CompareOptions.OrdinalIgnoreCase);
        }
        public HashtableComparer() {}
    }
"@
  } catch {
  }

function Sort-DataSet( [hashtable[]]$dataset, [switch]$descending) {
  [System.Collections.ArrayList]$a = $dataset
  if (-not($dataset)) {
    Write-Warning "dataset parameter is empty?"
    }
  if ($a.Count -eq 0) {
    Write-Warning "array equivalent is empty?"
    }
  if ($a.Count -ge 2) {
    $a.Sort([HashtableComparer]::new())
    if ($descending) {
      $a.reverse()
      }
	}
  [array]$sortedDataset = $a | %{
    $item = $_.Clone()
    $item.Remove('sortKey')
	$item
    }
  $sortedDataset
  }


function Open-Linux-Bastion-Session( [string]$ppkKey, [string]$pemKey, [string]$bastionName, [string]$bastionId) {
  if (test-path -path $ppkKey) {
      $ppk = $ppkKey
    } else {
      $ppk = "$baseOfSecretDocuments\$($ppkKey).ppk"
    }
  $ppk = '"' + $ppk + '"'
  if (test-path -path $pemKey) {
      $pem = $pemKey
    } else {
      $pem = "$baseOfSecretDocuments\$($pemKey).pem"
    }
  Set-DefaultAWSRegion -region ap-southeast-2
  if ($bastionId -ne $null) {
      $ip = get-ec2instance -InstanceId $bastionId |
        select -expandProperty Instances |
        select -expandProperty PrivateIpAddress
    } else {
      $ip = get-ec2instance -filter @( @{name='tag:Name'; values=$bastionName}) |
        select -expandProperty Instances | select -first 1 | select -expandProperty PrivateIpAddress
    }
  $hostEc2 = "ec2-user@$ip"
  & $putty -ssh $hostEc2 22 -i $ppk
  $creds = New-Object -TypeName System.Management.Automation.PSCredential ("ec2-user", (new-object System.Security.SecureString))
  Write-Host "Opeing SSH session to $ip as ec2-user; pem == $pem"
  $session = New-SSHSession -ComputerName $ip -Credential $creds -KeyFile $pem -force
  $session
  }

function Execute-on-Bastion( $session, [string]$command) {
  $ret = Invoke-SSHCommand -SessionId $session.SessionId -Command $command
  $ret | select -expandProperty Output
  }

function Execute-on-Bastion-via-Script( $session, [string]$tmpDir, [string]$bucket, [string]$prefix, [string[]]$commands) {
  $fn = "$tmpDir\temp-bash.sh"
  $waveGoodByeMessage = 'Hello World from Execute-on-Bastion-via-Script()'
  if (test-path -path $fn) { remove-item -path $fn }
  New-Item -ItemType Directory -Force -Path $tmpDir | out-null
  add-content -path $fn -value '#!/bin/bash'
  add-content -path $fn -value $commands
  add-content -path $fn -value 'echo $waveGoodByeMessage'
  $objectKey = "$($prefix)temp-bash.sh"
  set-defaultawsregion -region ap-southeast-2
  Write-S3Object -BucketName $bucket -file $fn -Key $objectKey | out-null
  Execute-on-Bastion -session $session -command "aws s3 cp s3://$bucket/$($prefix)temp-bash.sh temp-bash.sh" | out-null
  Execute-on-Bastion -session $session -command 'chmod u+x temp-bash.sh' | out-null
  Execute-on-Bastion -session $session -command 'sed -i -e ''s/\r$//'' temp-bash.sh' | out-null
  Execute-on-Bastion -session $session -command './temp-bash.sh' | out-null
  Execute-on-Bastion -session $session -command 'rm temp-bash.sh' | out-null
  remove-item -path $fn
  Remove-S3Object -BucketName $bucket -Key $objectKey -force | out-null
  }


function Close-Linux-Bastion-Session( $session) {
  Remove-SSHSession -SessionId $session.SessionId | out-null
  stop-process -name putty | out-null
  }

function get-platform-config() {
  $fn = $env:platformConfig
  if ($fn -eq $null) { $fn = 'C:\DEV\platform-config.yaml' }
  if (-not(test-path -path $fn)) {
      write-warning "platform-config.yaml not found. Please deploy and localise."
    } else {
      [hashtable] $config = [string]::join("`r`n",(Get-Content $fn)) | ConvertFrom-Yaml
      $config
    }
  }

function Test-AbsolutePath( [String]$path){
  [System.IO.Path]::IsPathRooted( $path)
  }
  
  
  
  
  
  
  
  