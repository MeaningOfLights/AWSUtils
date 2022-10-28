
param (
)

#Install visual studio code
choco install visualstudiocode -y

#Install c# plugins!!!
choco install vscode-csharp -y


setx path "%path%;c:\Program Files\Microsoft VS Code\bin"

#Install all the extensions, ref for cmd line VSCode Extension installation https://code.visualstudio.com/docs/editor/extension-gallery#_command-line-extension-management

try {
  #Install Python Extension, if Python insn't installed first you will get an error: Make sure you use the full extension ID, including the publisher,
  & "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension ms-python.python
}
catch {
}

try {  
  #Install Powershell
  &  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension ms-vscode.PowerShell
}
catch {
  
}

#Install Chrome Javascript Debugging
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension msjsdiag.debugger-for-chrome

#The two top Beautify/Pretty extensions, in the Settings I remove JS from Beautify
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension hookyqr.beautify
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension esbenp.prettier-vscode

#AI Intellisense for Python, JS and Java
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension visualstudioexptteam.vscodeintellicode

#Install rest client (a postman alternative in VSCode)
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension humao.rest-client

#Go to Definition of CSS Class in the HMTL
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension pranaygp.vscode-css-peek

#Tooltip for hex colours
&  "c:\Program Files\Microsoft VS Code\bin\code"  --install-extension bierner.color-info


# Use the developer preferred settings

#Command Palette enable Linting, see all the options: https://code.visualstudio.com/docs/python/linting#_specific-linters
#Python: Enable Linting : On
#"python.linting.<linter>Enabled": true

Set-content -path "$env:APPDATA\Code\User\settings.json" -value @"
{
  "editor.suggestSelection": "first",
  "vsintellicode.modify.editor.suggestSelection": "automaticallyOverrodeDefaultValue",
  "python.jediEnabled": false,
  "window.zoomLevel": 0,
  "editor.formatOnPaste": true,
  "editor.formatOnSave": true,
  "editor.fontFamily": "'Cascadia Code', Consolas, 'Courier New', monospace",
  "editor.fontLigatures": true,
  "workbench.editor.highlightModifiedTabs": true,
  "files.autoSave": "afterDelay",
  "explorer.sortOrder": "type",
  "files.trimFinalNewlines": true,
  "editor.fontSize": 16,
  "python.linting.enabled": true,
  "beautify.language": { "js": [] }
  }
"@



