#Requires -RunAsAdministrator

<#
.SYNOPSIS
    영문 Windows를 한국어 환경으로 초기 설정합니다.

.DESCRIPTION
    - Windows Defender Firewall 전체 비활성화
    - 시간대: Korea Standard Time
    - 한국어 언어팩 설치
    - Windows 표시 언어: 한국어
    - 시스템 로캘: 한국어(대한민국)
    - 지역 형식: 한국어(대한민국)
    - 국가/지역: 대한민국
    - 기본 입력기: Microsoft IME
    - 로그인 화면 및 신규 사용자 계정에 설정 복사

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

$LanguageTag = "ko-KR"
$TimeZoneId = "Korea Standard Time"
$KoreaGeoId = 134
$KoreanInputTip = "0412:00000412"

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

try {
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


    Write-Step "3. 한국어 언어팩 설치"

    if (Get-Command "Install-Language" -ErrorAction SilentlyContinue) {
        Write-Host "한국어 언어팩과 관련 언어 기능을 설치합니다."
        Write-Host "Windows Update 서버에서 파일을 다운로드하므로 인터넷 연결이 필요합니다."

        Install-Language `
            -Language $LanguageTag `
            -CopyToSettings `
            -ErrorAction Stop

        Write-Host "[완료] 한국어 언어팩을 설치했습니다." -ForegroundColor Green
    }
    else {
        Write-Warning "Install-Language 명령을 사용할 수 없습니다."
        Write-Host "Windows Capability 방식으로 한국어 기능을 설치합니다."

        $Capabilities = @(
            "Language.Basic~~~ko-KR~0.0.1.0",
            "Language.Handwriting~~~ko-KR~0.0.1.0",
            "Language.OCR~~~ko-KR~0.0.1.0",
            "Language.Speech~~~ko-KR~0.0.1.0",
            "Language.TextToSpeech~~~ko-KR~0.0.1.0"
        )

        foreach ($CapabilityName in $Capabilities) {
            $Capability = Get-WindowsCapability `
                -Online `
                -Name $CapabilityName `
                -ErrorAction SilentlyContinue

            if ($null -eq $Capability) {
                Write-Warning "지원되지 않는 언어 기능입니다: $CapabilityName"
                continue
            }

            if ($Capability.State -eq "Installed") {
                Write-Host "[이미 설치됨] $CapabilityName"
            }
            else {
                Write-Host "[설치 중] $CapabilityName"

                Add-WindowsCapability `
                    -Online `
                    -Name $CapabilityName `
                    -ErrorAction Stop | Out-Host
            }
        }

        Write-Host "[완료] 사용 가능한 한국어 기능을 설치했습니다." -ForegroundColor Green
    }


    Write-Step "4. 현재 사용자 언어와 한글 입력기 설정"

    $LanguageList = New-WinUserLanguageList -Language $LanguageTag

    # 한국어 Microsoft IME를 기본 입력기로 지정
    $LanguageList[0].InputMethodTips.Clear()
    $LanguageList[0].InputMethodTips.Add($KoreanInputTip)

    Set-WinUserLanguageList `
        -LanguageList $LanguageList `
        -Force

    Set-WinUILanguageOverride `
        -Language $LanguageTag

    Set-WinDefaultInputMethodOverride `
        -InputTip $KoreanInputTip

    Write-Host "[완료] Windows 표시 언어 및 한글 입력기를 설정했습니다." -ForegroundColor Green


    Write-Step "5. 시스템 로캘과 지역 설정을 대한민국으로 변경"

    # 비유니코드 프로그램용 시스템 로캘
    Set-WinSystemLocale `
        -SystemLocale $LanguageTag

    # 날짜, 시간, 숫자, 통화 등의 지역 형식
    Set-Culture `
        -CultureInfo $LanguageTag

    # 국가 또는 지역: 대한민국
    Set-WinHomeLocation `
        -GeoId $KoreaGeoId

    Write-Host "[완료] 시스템 로캘과 지역을 대한민국으로 설정했습니다." -ForegroundColor Green


    Write-Step "6. 로그인 화면 및 신규 사용자 기본값 적용"

    if (Get-Command "Copy-UserInternationalSettingsToSystem" -ErrorAction SilentlyContinue) {
        Copy-UserInternationalSettingsToSystem `
            -WelcomeScreen $true `
            -NewUser $true

        Write-Host "[완료] 로그인 화면과 신규 사용자 계정에도 적용했습니다." -ForegroundColor Green
    }
    else {
        Write-Warning "현재 Windows 버전은 자동 설정 복사 명령을 지원하지 않습니다."
        Write-Warning "현재 사용자와 시스템 로캘 설정은 정상적으로 적용되었습니다."
    }


    Write-Step "설정 결과 확인"

    Write-Host "시간대             : $((Get-TimeZone).Id)"
    Write-Host "현재 사용자 Culture : $((Get-Culture).Name)"
    Write-Host "시스템 Locale       : $((Get-WinSystemLocale).Name)"
    Write-Host "국가 GeoID          : $((Get-WinHomeLocation).GeoId)"
    Write-Host ""
    Write-Host "사용자 언어 목록:" -ForegroundColor Yellow

    Get-WinUserLanguageList | Format-List


    Write-Step "모든 설정이 완료되었습니다"

    Write-Host "Windows 표시 언어를 완전히 변경하려면 재부팅이 필요합니다." -ForegroundColor Yellow

    if ($Restart) {
        Write-Host "10초 후 컴퓨터를 재부팅합니다." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Host ""
        Write-Host "지금 재부팅하려면 다음 명령을 실행하세요:" -ForegroundColor Cyan
        Write-Host "Restart-Computer -Force" -ForegroundColor White
        Write-Host ""
        Write-Host "스크립트 실행과 동시에 재부팅하려면:" -ForegroundColor Cyan
        Write-Host ".\Set-KoreanWindows.ps1 -Restart" -ForegroundColor White
    }
}
catch {
    Write-Host ""
    Write-Host "[오류 발생]" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Windows Update 연결 상태와 관리자 권한을 확인하세요." -ForegroundColor Yellow
    exit 1
}
