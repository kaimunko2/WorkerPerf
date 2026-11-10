#!/usr/bin/env bash
# Richtet PowerShell 7 und Pester 5 in einer frischen Linux-Sitzung (x64) ein.
set -euo pipefail
PWSH_VERSION=7.4.6
PESTER_VERSION=5.7.1
if ! command -v pwsh >/dev/null 2>&1; then
  curl -sSL -o /tmp/pwsh.tgz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-x64.tar.gz"
  mkdir -p /opt/pwsh && tar -xzf /tmp/pwsh.tgz -C /opt/pwsh
  chmod +x /opt/pwsh/pwsh && ln -sf /opt/pwsh/pwsh /usr/local/bin/pwsh && rm /tmp/pwsh.tgz
fi
MODDIR="${HOME}/.local/share/powershell/Modules/Pester/${PESTER_VERSION}"
if [ ! -f "${MODDIR}/Pester.psd1" ]; then
  # powershellgallery.com ist in Cloud-Sitzungen gesperrt; nuget.org liefert das Modul unter tools/.
  curl -sSL -o /tmp/pester.nupkg "https://api.nuget.org/v3-flatcontainer/pester/${PESTER_VERSION}/pester.${PESTER_VERSION}.nupkg"
  rm -rf /tmp/pester-x && unzip -q /tmp/pester.nupkg 'tools/*' -d /tmp/pester-x
  mkdir -p "${MODDIR}" && cp -r /tmp/pester-x/tools/. "${MODDIR}/" && rm -rf /tmp/pester-x /tmp/pester.nupkg
fi
pwsh -NoProfile -Command 'Import-Module Pester -MinimumVersion 5.0; "Pester " + (Get-Module Pester).Version'
