---
title: mac-setup
---

# iMac 키보드 실습 환경 자동 설정

실습실 iMac 에서 **관리자 권한 없이, System Settings 를 열지 않고** 아래 세 가지를 한 번에 설정합니다.

| 항목 | 설정값 |
|---|---|
| 키보드 › fn 키를 누를 때 실행할 동작 | 입력 소스 변경 |
| 키보드 단축키 › 보조 키 › Caps Lock 키 | fn 기능 |
| 텍스트 입력 › 입력 소스 | 구름 입력기 추가 (기본 두벌식, 옵션으로 세벌식 등) |

설정이 끝나면 **Caps Lock 키 한 번으로 한/영이 전환**됩니다.

## 실행

로그인한 뒤 터미널(Terminal)을 열고 아래 한 줄을 붙여 넣습니다.

두벌식:

```sh
curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh
```

세벌식 최종:

```sh
curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh -s -- han3final
```

여러 배열을 한꺼번에 추가할 수도 있습니다.

```sh
curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh -s -- han2 han3final
```

사용 가능한 배열 이름 확인:

```sh
curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh -s -- --list
```

여러 번 실행해도 안전합니다. 이미 적용된 항목은 건너뜁니다.

## 배열 이름

| 이름 | 배열 |
|---|---|
| `han2` | 두벌식 (기본값) |
| `han2classic` | 두벌식 옛글 |
| `han3final` | 세벌식 최종 |
| `han3finalnoshift` | 세벌식 최종 (윗글쇠 없음) |
| `han390` | 세벌식 390 |
| `han3noshift` | 세벌식 순아래 |
| `han3-2011` | 세벌식 2011 |
| `han3-2012` | 세벌식 2012 |
| `han3classic` | 세벌식 옛글 |
| `han3layout2` | 세벌식 제2 배열 |
| `hanahnmatae` | 안마태 |
| `hanroman` | 로마자 |
| `qwerty` `dvorak` `colemak` | 영문 배열 |

## 실행 중 화면

```
0. 로그인 초기화 완료 대기
  … 로그인 에이전트(kr.codyssey.gureum.init) 실행 중 (최대 180초)....
  / 로그인 초기화 완료 (8초 대기)

1. fn 키를 누를 때 실행할 동작 -> 입력 소스 변경
  / AppleFnUsageType = 1

2. 보조 키: Caps Lock -> fn 기능
  / modifiermapping.1452-591-0
  / hidutil 즉시 적용 완료
  / 로그인 에이전트 local.imac-setup.capslock-fn 등록 (매 로그인마다 재적용)

3. 입력 소스에 구름 입력기 추가
  / org.youknowone.inputmethod.Gureum.han3final 켬 (즉시 적용)
  / org.youknowone.inputmethod.Gureum.han3final 저장 목록에 추가 (재로그인 후에도 유지)

완료.
```

**0단계에서 기다리는 이유**: 실습실 iMac 은 로그인 직후 관리자 에이전트가 구름 입력기를 띄우고 두벌식을 강제로 선택합니다. 이 작업이 끝나기 전에 설정을 바꾸면 나중에 끝나는 쪽이 입력 소스 목록을 덮어써서 추가한 배열이 사라집니다. 로그인 직후 뜨는 확인 창도 이 에이전트가 띄우는 것이라 스크립트에서는 없앨 수 없고, 에이전트가 끝날 때까지 기다린 뒤 진행합니다.

## 확인

- 메뉴 막대 오른쪽 입력 메뉴에 구름 입력기 배열이 보이면 성공입니다.
- Caps Lock 을 누르면 입력 소스가 바뀝니다.
- 터미널에서 직접 확인:

```sh
defaults read com.apple.HIToolbox AppleEnabledInputSources   # 입력 소스 저장 목록
hidutil property --get UserKeyMapping                        # Caps Lock -> fn 매핑
```

## 문제 해결

| 증상 | 조치 |
|---|---|
| 추가한 배열이 메뉴에 안 보임 | 한 번 로그아웃 후 다시 로그인 |
| Caps Lock 이 여전히 Caps Lock 으로 동작 | 로그아웃 후 다시 로그인. 그래도 안 되면 스크립트를 다시 실행 |
| `구름 입력기(Gureum.app)가 설치되어 있지 않습니다` | 관리자에게 설치 요청. 또는 `~/Library/Input Methods/` 에 Gureum.app 을 복사한 뒤 재로그인 |
| `… 구름 입력기에 없는 모드입니다` | `--list` 로 이름 확인 |

## 되돌리기

```sh
launchctl bootout gui/$(id -u)/local.imac-setup.capslock-fn
rm -f ~/Library/LaunchAgents/local.imac-setup.capslock-fn.plist
hidutil property --set '{"UserKeyMapping":[]}'
defaults -currentHost delete -g com.apple.keyboard.modifiermapping.1452-591-0
defaults write com.apple.HIToolbox AppleFnUsageType -int 2
```

입력 소스는 System Settings › 키보드 › 입력 소스 › 편집에서 지우거나, 메뉴 막대 입력 메뉴에서 다른 배열을 고른 뒤 필요 없는 것을 제거합니다.

## 동작 원리

- **fn 키 동작**: `com.apple.HIToolbox` 의 `AppleFnUsageType` 을 1(입력 소스 변경)로 씁니다.
- **Caps Lock → fn**: System Settings 와 같은 위치(`com.apple.keyboard.modifiermapping.<VendorID>-<ProductID>-<CountryCode>`)에 **정수** 값으로 저장합니다. 문자열로 저장하면 시스템이 무시합니다. 지금 바로 적용하기 위해 `hidutil` 을 쓰고, 이 매핑은 로그아웃하면 사라지므로 매 로그인마다 다시 적용하는 사용자 LaunchAgent(`~/Library/LaunchAgents/local.imac-setup.capslock-fn.plist`)를 등록합니다.
- **입력 소스**: System Settings 가 쓰는 API(`TISEnableInputSource`)를 JXA(`osascript -l JavaScript`)로 호출해 즉시 켜고, 로그인 시 읽는 저장 목록 `AppleEnabledInputSources` 에도 넣습니다. swift 는 컴파일 지연과 개발자 도구 의존이 있어 쓰지 않습니다.
- 스크립트는 `/bin/sh`(bash 3.2 POSIX 모드)에서 동작하도록 배열과 프로세스 치환을 쓰지 않고, `curl | sh` 로 다운로드가 끊겨도 부분 실행되지 않도록 전체를 `main()` 에 담아 마지막 줄에서 호출합니다.

## 소스

- 스크립트: [iMac-setup.sh](iMac-setup.sh)
- 저장소: [github.com/newids/mac-setup](https://github.com/newids/mac-setup)
