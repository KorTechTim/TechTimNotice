#Requires -RunAsAdministrator

<#
.SYNOPSIS
    영문 Windows를 한국어 환경으로 설정합니다.

.DESCRIPTION
    1. Windows 방화벽 전체 프로필 비활성화
    2. 시간대를 Korea Standard Time으로 변경
    3. 한국어 기본 언어팩 설치
    4. 한국어 표시 언어와 Microsoft IME 설정
    5. 시스템 로캘, 지역 형식, 국가를 대한민국으로 변경
    6. 로그인 화면과 신규 사용자 계정에 설정 복사

.EXAMPLE
    .\Set-KoreanWindows.ps1

.EXAMPLE
    .\Set-KoreanWindows.ps1 -Restart
#>

[CmdletBinding()]
param (
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

$LanguageTag   = "ko-KR"
$TimeZoneId   = "Korea Standard Time"
$KoreaGeoId   = 134
$KoreanInput  = "0412:00000412"

function Write-Step {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Test-Administrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

try {
    if (-not (Test-Administrator)) {
        throw "PowerShell을 관리자 권한으로 실행해야 합니다."
    }


    Write-Step "1. Windows 방화벽 전체 프로필 비활성화"

    & netsh.exe advfirewall set allprofiles state off

    if ($LASTEXITCODE -ne 0) {
        throw "Windows 방화벽 비활성화에 실패했습니다. ExitCode: $LASTEXITCODE"
    }

    Write-Host "[완료] Domain, Private, Public 방화벽을 비활성화했습니다." -ForegroundColor Green


    Write-Step "2. Windows 시간대를 한국 표준시로 변경"

    & tzutil.exe /s $TimeZoneId

    if ($LASTEXITCODE -ne 0) {
        throw "시간대 변경에 실패했습니다. ExitCode: $LASTEXITCODE"
    }

    Write-Host "[완료] 시간대: $TimeZoneId" -ForegroundColor Green


    Write-Step "3. Windows Update 관련 서비스 확인"

    $RequiredServices = @(
        "wuauserv",
        "bits",
        "cryptsvc",
        "TrustedInstaller"
    )

    foreach ($ServiceName in $RequiredServices) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($null -eq $Service) {
            Write-Warning "서비스를 찾을 수 없습니다: $ServiceName"
            continue
        }

        if ($Service.Status -ne "Running") {
            Write-Host "[시작 중] $ServiceName"

            try {
                Start-Service -Name $ServiceName -ErrorAction Stop
            }
            catch {
                Write-Warning "$ServiceName 서비스를 시작하지 못했습니다: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "[실행 중] $ServiceName"
        }
    }


    Write-Step "4. 한국어 언어팩 설치"

    $KoreanInstalled = $false

    if (Get-Command "Get-InstalledLanguage" -ErrorAction SilentlyContinue) {
        $InstalledLanguages = Get-InstalledLanguage -ErrorAction SilentlyContinue

        $KoreanInstalled = [bool](
            $InstalledLanguages | Where-Object {
                $_.LanguageId -eq $LanguageTag -or
                $_.Language -eq $LanguageTag
            }
        )
    }
    else {
        $BasicCapability = Get-WindowsCapability `
            -Online `
            -Name "Language.Basic~~~ko-KR~0.0.1.0" `
            -ErrorAction SilentlyContinue

        if ($null -ne $BasicCapability) {
            $KoreanInstalled = ($BasicCapability.State -eq "Installed")
        }
    }

    if ($KoreanInstalled) {
        Write-Host "[이미 설치됨] 한국어 언어팩이 설치되어 있습니다." -ForegroundColor Green
    }
    elseif (Get-Command "Install-Language" -ErrorAction SilentlyContinue) {
        Write-Host "한국어 기본 표시 언어팩을 설치합니다."
        Write-Host "필기, OCR, 음성 인식, TTS 기능은 설치하지 않습니다."
        Write-Host "인터넷과 Windows Update 연결 상태에 따라 몇 분 정도 걸릴 수 있습니다."
        Write-Host ""

        Install-Language `
            -Language $LanguageTag `
            -CopyToSettings `
            -ExcludeFeatures `
            -ErrorAction Stop

        Write-Host "[완료] 한국어 기본 언어팩을 설치했습니다." -ForegroundColor Green
    }
    else {
        Write-Warning "Install-Language 명령을 지원하지 않는 Windows 버전입니다."
        Write-Host "Windows Capability 방식으로 한국어 기본 기능을 설치합니다."

        $CapabilityName = "Language.Basic~~~ko-KR~0.0.1.0"

        $Capability = Get-WindowsCapability `
            -Online `
            -Name $CapabilityName `
            -ErrorAction Stop

        if ($Capability.State -eq "Installed") {
            Write-Host "[이미 설치됨] $CapabilityName" -ForegroundColor Green
        }
        else {
            Write-Host "[설치 중] $CapabilityName"

            Add-WindowsCapability `
                -Online `
                -Name $CapabilityName `
                -ErrorAction Stop | Out-Host

            Write-Host "[완료] 한국어 기본 기능을 설치했습니다." -ForegroundColor Green
        }
    }


    Write-Step "5. 현재 사용자 표시 언어와 한글 입력기 설정"

    $LanguageList = New-WinUserLanguageList -Language $LanguageTag

    if ($LanguageList.Count -eq 0) {
        throw "한국어 사용자 언어 목록을 생성하지 못했습니다."
    }

    $LanguageList[0].InputMethodTips.Clear()
    $LanguageList[0].InputMethodTips.Add($KoreanInput)

    Set-WinUserLanguageList `
        -LanguageList $LanguageList `
        -Force

    Set-WinUILanguageOverride `
        -Language $LanguageTag

    Set-WinDefaultInputMethodOverride `
        -InputTip $KoreanInput

    if (Get-Command "Set-SystemPreferredUILanguage" -ErrorAction SilentlyContinue) {
        Set-SystemPreferredUILanguage `
            -Language $LanguageTag
    }

    Write-Host "[완료] 한국어 표시 언어와 Microsoft IME를 설정했습니다." -ForegroundColor Green


    Write-Step "6. 시스템 로캘과 대한민국 지역 설정"

    Set-WinSystemLocale `
        -SystemLocale $LanguageTag

    Set-Culture `
        -CultureInfo $LanguageTag

    Set-WinHomeLocation `
        -GeoId $KoreaGeoId

    Write-Host "[완료] 시스템 로캘: ko-KR" -ForegroundColor Green
    Write-Host "[완료] 지역 형식: 한국어(대한민국)" -ForegroundColor Green
    Write-Host "[완료] 국가 또는 지역: 대한민국" -ForegroundColor Green


    Write-Step "7. 로그인 화면과 신규 사용자 계정에 설정 적용"

    if (Get-Command "Copy-UserInternationalSettingsToSystem" -ErrorAction SilentlyContinue) {
        Copy-UserInternationalSettingsToSystem `
            -WelcomeScreen $true `
            -NewUser $true

        Write-Host "[완료] 로그인 화면과 신규 사용자 계정에도 적용했습니다." -ForegroundColor Green
    }
    else {
        Write-Warning "현재 Windows 버전에서는 설정 복사 명령을 지원하지 않습니다."
        Write-Warning "현재 사용자와 시스템 설정은 정상적으로 적용되었습니다."
    }


    Write-Step "8. 최종 설정 결과"

    Write-Host "시간대             : $((Get-TimeZone).Id)"
    Write-Host "현재 사용자 Culture : $((Get-Culture).Name)"
    Write-Host "시스템 Locale       : $((Get-WinSystemLocale).Name)"
    Write-Host "국가 GeoID          : $((Get-WinHomeLocation).GeoId)"
    Write-Host ""

    Write-Host "현재 사용자 언어 목록:" -ForegroundColor Yellow
    Get-WinUserLanguageList | Format-List


    Write-Step "모든 설정 완료"

    Write-Host "한국어 표시 언어와 시스템 로캘을 완전히 적용하려면 재부팅이 필요합니다." -ForegroundColor Yellow

    if ($Restart) {
        Write-Host ""
        Write-Host "10초 후 Windows를 재부팅합니다." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Host ""
        Write-Host "지금 재부팅하려면 아래 명령을 실행하세요." -ForegroundColor Cyan
        Write-Host "Restart-Computer -Force" -ForegroundColor White
    }
}
catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " 오류가 발생했습니다." -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "확인 사항:" -ForegroundColor Yellow
    Write-Host "1. PowerShell 관리자 권한"
    Write-Host "2. 인터넷 연결 상태"
    Write-Host "3. Windows Update 서비스 상태"
    Write-Host "4. Windows Update 또는 WSUS 정책"
    exit 1
}
