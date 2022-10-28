import-module powershell-yaml

# Attach to your client script, with a statement like ...
# if (-not(Get-Command yaml-utils-Hello -errorAction SilentlyContinue)) {
#   . "C:\DEV\General\Automation\Scripts\yaml-utils.ps1"
#   }

function yaml-utils-Hello {
  Write-Host "Hello from $($MyInvocation.MyCommand.Name)"
  }

function lines-to-hashtable{ param( [string[]]$lines) 
  try {
      [hashtable]$hashtable = [string]::join("`r`n",$lines) | ConvertFrom-Yaml
    } catch {
      $hashtable = $null
    }
  $hashtable
  }

function read-local-yaml { param( [string]$path) 
  # This function reads a yaml file.
  # If the file does not exist, $null is returned.
  try {
      $lines = Get-Content $path
      lines-to-hashtable -lines $lines
    } catch {}
  }

function read-yaml-from-remote-git { param( [string]$git, [string]$commitId, [string]$path) 
  try {
      $lines = & $git show "$($commitId):$path"
      lines-to-hashtable -lines $lines
    } catch {}
  }
  
function y-path( [hashtable]$db, [string]$path) {
  $res = $db
  $path -split '\.' | %{
    if ($res) {
      if (($res -is [hashtable]) -and ($res.ContainsKey( $_))) {
          $res = $res[$_]
        } else {
          $res = $null
        }
      }
    }
  return $res
  }


