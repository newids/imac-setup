---
title: imac-setup
---

# iMac 키보드 실습 환경 자동 설정

실습실 iMac(macOS Sequoia 15.7, 구름 입력기 1.13)에서 **관리자 권한 없이, System Settings 를 열지 않고, 로그아웃 없이** 아래 세 가지를 한 번에 설정합니다.

| 항목 | 설정값 |
|---|---|
| 키보드 › fn 키를 누를 때 실행할 동작 | 입력 소스 변경 |
| 키보드 단축키 › 보조 키 › Caps Lock 키 | fn 기능 |
| 텍스트 입력 › 입력 소스 | ABC + 구름 입력기 두벌식 (+ 요청한 배열) |

설정이 끝나면 **Caps Lock 키 한 번으로 ABC(영문) ↔ 구름 입력기(한글)** 가 전환됩니다.

## 실행

로그인한 뒤 터미널(Terminal)을 열고 아래 한 줄을 붙여 넣습니다.

두벌식만:

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh
```

두벌식 + 세벌식 최종:

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- han3final
```

여러 배열을 한꺼번에:

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- han3final han390
```

배열 이름 확인:

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- --list
```

- 두벌식(`han2`)은 항상 포함됩니다. 로그인 에이전트가 두벌식을 강제로 켜기 때문에, 목록에 없으면 로그인 때마다 확인 창이 뜹니다.
- 여러 번 실행해도 안전합니다. 실행할 때마다 구름 입력기 목록을 "두벌식 + 지정한 배열"로 다시 씁니다. 세벌식을 빼고 싶으면 인자 없이 다시 실행하면 됩니다.

## 배열 이름

| 이름 | 배열 | 비고 |
|---|---|---|
| `han2` | 두벌식 | 기본, 항상 포함 |
| `han3final` | 세벌식 최종 | |
| `han390` | 세벌식 390 | |
| `han3noshift` | 세벌식 순아래 | |
| `han3finalnoshift` | 세벌식 최종 순아래 | |
| `han3-2011` `han3-2012` | 세벌식 2011 / 2012 | |
| `han2classic` `han3classic` | 두벌식 옛글 / 세벌식 옛글 | |
| `hanahnmatae` | 안마태 | |
| `system` | 로마자 | **추가하지 마세요.** 영문은 ABC 로 입력합니다 |
| `hanroman` | 한글 로마자 | 로마자로 한글을 조합하는 배열. 영문 입력용이 아닙니다 |
| `qwerty` `dvorak` `colemak` | 영문 배열 | 구름 입력기에서 제거 예정 |

**로마자 주의**: 구름 입력기의 "로마자"는 영문 자판이 아니라 구름 입력기 안의 영문 모드입니다. 이 항목이 입력 소스에 들어가면 fn/Caps Lock 전환이 ABC → 로마자 → 두벌식 3단계로 돌고, 로마자 상태에서는 영문 입력이 정상적으로 되지 않습니다. 스크립트는 이 항목을 목록에서 제외합니다. 영문은 ABC 하나로 충분합니다.

## 실행 중 화면

```
0. 로그인 초기화 완료 대기
  … 로그인 에이전트(kr.codyssey.gureum.init) 실행 중 (최대 180초)....
  / 로그인 초기화 완료 (8초 대기)

1. fn 키를 누를 때 실행할 동작 -> 입력 소스 변경
  / AppleFnUsageType = 1

2. 보조 키: Caps Lock -> fn 기능
  / modifiermapping.1452-591-0 저장
  / 키보드 1대에 즉시 적용

3. 입력 소스: 구름 입력기
  / org.youknowone.inputmethod.Gureum.han2 켜짐
  / org.youknowone.inputmethod.Gureum.han3final 켜짐

완료. 세 항목 모두 지금 적용되었고 재로그인 후에도 유지됩니다.
```

**0단계에서 기다리는 이유**: 실습실 iMac 은 로그인 직후 관리자 에이전트가 구름 입력기를 띄우고 swift 로 두벌식을 강제 선택합니다. 이 작업이 끝나기 전에 설정을 바꾸면 나중에 끝나는 쪽이 입력 소스 목록을 덮어써서 추가한 배열이 사라집니다.

**로그인 직후 뜨는 확인 창**: "swift 이(가) 서드파티 입력 방법 '구름 입력기'를 활성화하려고 합니다" 창입니다. 관리자 에이전트가 API(TISEnableInputSource)로 두벌식을 켤 때 macOS 가 묻는 것으로, 두벌식이 이미 서드파티 입력 소스 목록에 들어 있으면 뜨지 않습니다. 이 스크립트를 한 번 실행해 두면 목록에 들어가므로 다음 로그인부터는 뜨지 않아야 합니다. 관리자 에이전트 자체는 이 스크립트에서 바꿀 수 없습니다.

## 확인

- 메뉴 막대 오른쪽 입력 메뉴에 ABC 와 구름 입력기 배열이 보이면 성공입니다.
- Caps Lock 을 누르면 ABC ↔ 구름 입력기가 바뀝니다. 한글 배열이 둘 이상이면 순서대로 돕니다.
- 터미널에서 직접 확인:

```sh
defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources   # 구름 입력기 목록
defaults read com.apple.HIToolbox AppleFnUsageType                        # 1 이면 입력 소스 변경
defaults -currentHost read -g | grep -A4 modifiermapping                  # Caps Lock -> fn (정수 값)
```

## 문제 해결

| 증상 | 조치 |
|---|---|
| 설정 화면 입력 소스 목록에 같은 구름 항목이 여러 개 | 예전 방식으로 `com.apple.HIToolbox` 에 들어간 항목이 원인. 스크립트를 다시 실행하면 정리됩니다 |
| 로마자 항목이 있고 영문이 이상하게 입력됨 | 스크립트를 다시 실행하면 로마자가 빠집니다 |
| Caps Lock 이 여전히 Caps Lock 으로 동작 | 스크립트를 다시 실행하고 "키보드 N대에 즉시 적용" 이 나오는지 확인. 안 나오면 로그아웃 후 다시 로그인 |
| 추가한 배열이 메뉴에 안 보임 | 스크립트를 다시 실행. 그래도 안 되면 로그아웃 후 다시 로그인 |
| `구름 입력기(Gureum.app)가 설치되어 있지 않습니다` | 관리자에게 설치 요청. 또는 `~/Library/Input Methods/` 에 Gureum.app 을 복사한 뒤 재로그인 |
| `… 구름 입력기에 없는 배열입니다` | `--list` 로 이름 확인 |

## 되돌리기

```sh
defaults write com.apple.HIToolbox AppleFnUsageType -int 2
defaults -currentHost delete -g com.apple.keyboard.modifiermapping.1452-591-0
defaults delete com.apple.inputsources AppleEnabledThirdPartyInputSources
launchctl kickstart -k gui/$(id -u)/com.apple.TextInputMenuAgent
```

Caps Lock 매핑은 로그아웃 후 다시 로그인하면 원래대로 돌아옵니다. 입력 소스는 System Settings › 키보드 › 입력 소스 › 편집에서도 정리할 수 있습니다.

## 동작 원리 (Sequoia 15.7 기준)

System Settings 가 쓰는 위치와 형식에 그대로 맞추고, 즉시 적용도 System Settings 와 같은 경로를 씁니다.

- **fn 키 동작**: `com.apple.HIToolbox` 의 `AppleFnUsageType` 을 1 로 씁니다.
- **Caps Lock → fn 저장**: ByHost `.GlobalPreferences` 의 `com.apple.keyboard.modifiermapping.<VendorID>-<ProductID>-<CountryCode>` 에 **정수** 값으로 씁니다. 문자열로 저장되면 시스템이 무시합니다. 로그인 때 시스템이 이 값을 읽어 키보드에 적용합니다.
- **Caps Lock → fn 즉시 적용**: 로그인 때 시스템이 키보드 서비스에 넣는 속성 `HIDKeyboardModifierMappingPairs` 를 지금 바로 넣습니다. 이 속성은 HID 이벤트 시스템의 monitor 클라이언트로만 넣을 수 있어서 `hidutil` 로는 안 되고, JXA(`osascript -l JavaScript`)로 IOKit 함수를 직접 호출합니다. `hidutil` 의 `UserKeyMapping` 으로 Caps Lock 을 fn 으로 바꾸면 키는 바뀌지만 fn 의 "입력 소스 변경" 동작이 일어나지 않습니다.
- **구름 입력 소스**: Sequoia 는 서드파티 입력기를 `com.apple.inputsources` 의 `AppleEnabledThirdPartyInputSources` 에 저장합니다 (입력기 항목 + 배열 항목). 스크립트는 이 목록을 "구름 입력기 + 두벌식 + 지정한 배열"로 쓰고, 예전 방식으로 `com.apple.HIToolbox` 의 `AppleEnabledInputSources` 에 들어간 구름 항목은 지웁니다 (양쪽에 다 있으면 설정 화면에 중복으로 나타남). 그 다음 입력 소스 변경 알림을 보내고 메뉴 막대 입력 메뉴(TextInputMenuAgent)를 다시 띄웁니다.
- `TISEnableInputSource` API 는 쓰지 않습니다. 이 API 는 호출한 프로그램 이름으로 "서드파티 입력 방법을 활성화하려고 합니다" 확인 창을 띄웁니다.
- 스크립트는 `/bin/sh`(bash 3.2 POSIX 모드)에서 동작하도록 배열과 프로세스 치환을 쓰지 않고, `curl | sh` 로 다운로드가 끊겨도 부분 실행되지 않도록 전체를 `main()` 에 담아 마지막 줄에서 호출합니다.

## 참고

- [구름 입력기](https://gureum.io/) · [GitHub](https://github.com/gureum/gureum) · [설치 도움말](https://github.com/gureum/gureum/wiki/Help-Install) · [환경설정 도움말](https://github.com/gureum/gureum/wiki/Help-Preference)
- 구름 입력기 자체의 ⇧Space 한영 전환은 구름의 "쿼티" 배열(제거 예정)을 추가해야 동작합니다. 이 스크립트는 그 대신 macOS 의 fn/Caps Lock 입력 소스 전환을 씁니다.

## 소스

- 스크립트: [iMac-setup.sh](iMac-setup.sh)
- 저장소: [github.com/newids/imac-setup](https://github.com/newids/imac-setup)
