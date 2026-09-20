#!/bin/sh
#
# macOS 키보드 실습 환경 자동 설정 (관리자 권한 불필요, UI 조작 불필요)
#
#   0. 로그인 초기화 대기
#      관리자가 설치한 로그인 에이전트(kr.codyssey.gureum.init)가 구름 입력기를 띄우고
#      두벌식을 강제 선택하는 작업이 끝날 때까지 기다린다. 이 작업과 동시에 설정을
#      바꾸면 나중에 끝나는 쪽이 입력 소스 목록을 덮어써서 세벌식 추가가 사라진다.
#   1. 키보드 > fn 키를 누를 때 실행할 동작   -> 입력 소스 변경
#   2. 키보드 단축키 > 보조 키 > Caps Lock 키 -> fn 기능
#   3. 텍스트 입력 > 입력 소스                -> 구름 입력기 추가
#
# 사용법:
#   curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh                    # 두벌식
#   curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh -s -- han3final    # 세벌식 최종
#   curl -fsSL https://newids.github.io/mac-setup/iMac-setup.sh | sh -s -- --list       # 배열 목록
#
# 참고: 로그인 직후 뜨는 확인 창은 관리자 에이전트가 `open -g Gureum.app` 으로
# 입력기를 일반 앱처럼 실행하면서 macOS 가 묻는 권한 창이다. 이 스크립트에서는
# 제어할 수 없고, 에이전트가 끝날 때까지 기다리는 것으로 충돌만 피한다.
#
# curl | sh 로 중간에 끊겨도 부분 실행되지 않도록 전체를 main() 에 담고
# 마지막 줄에서 호출한다. /bin/sh(bash 3.2 POSIX 모드)에서 동작하도록
# 배열과 프로세스 치환은 쓰지 않는다.

set -u

PB=/usr/libexec/PlistBuddy
GUREUM_BUNDLE="org.youknowone.inputmethod.Gureum"

LOGIN_AGENT="kr.codyssey.gureum.init"                 # 관리자가 설치한 로그인 에이전트
LOGIN_AGENT_PROCS='init_gureum\.sh|set_gureum_ime\.swift'
WAIT_MAX=180                                          # 초

CAPS_AGENT="local.imac-setup.capslock-fn"             # 이 스크립트가 설치하는 사용자 에이전트
CAPS=30064771129                                      # 0x700000039  Caps Lock
FN=1095216660483                                      # 0xFF00000003 fn(지구본)
HIDUTIL_MAPPING="{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":$CAPS,\"HIDKeyboardModifierMappingDst\":$FN}]}"

info() { printf '  \033[32m/\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

find_gureum() {
    for d in "$HOME/Library/Input Methods" "/Library/Input Methods"; do
        if [ -d "$d/Gureum.app" ]; then printf '%s\n' "$d/Gureum.app"; return 0; fi
    done
    return 1
}

# ---------------------------------------------------------------- 0. 대기

# 아직 기다려야 하면 이유를 출력하고 0, 진행해도 되면 1.
login_init_busy() {
    if pgrep -qf "$LOGIN_AGENT_PROCS" \
       || launchctl print "gui/$uid/$LOGIN_AGENT" 2>/dev/null | grep -q 'state = running'; then
        echo "로그인 에이전트($LOGIN_AGENT) 실행 중"
        return 0
    fi
    if ! pgrep -qx TextInputMenuAgent; then
        echo "입력 메뉴 에이전트(TextInputMenuAgent) 시작 대기"
        return 0
    fi
    return 1
}

wait_for_login_init() {
    step "0. 로그인 초기화 완료 대기"
    waited=0
    while reason=$(login_init_busy); do
        if [ "$waited" -ge "$WAIT_MAX" ]; then
            printf '\n'
            warn "${WAIT_MAX}초가 지나도 끝나지 않아 그대로 진행합니다: $reason"
            return 0
        fi
        [ "$waited" -eq 0 ] && printf '  \033[33m…\033[0m %s (최대 %s초)' "$reason" "$WAIT_MAX"
        printf '.'
        sleep 2
        waited=$((waited + 2))
    done
    if [ "$waited" -gt 0 ]; then
        printf '\n'
        sleep 2   # 에이전트가 마지막으로 바꾼 입력 소스 설정이 저장될 시간
    fi
    info "로그인 초기화 완료 (${waited}초 대기)"
}

# ---------------------------------------------------------------- 1. fn 키

setup_fn_key() {
    # AppleFnUsageType: 0=아무 동작 안 함 1=입력 소스 변경 2=이모티콘 및 기호 3=받아쓰기
    step "1. fn 키를 누를 때 실행할 동작 -> 입력 소스 변경"
    defaults write com.apple.HIToolbox AppleFnUsageType -int 1
    info "AppleFnUsageType = 1"
}

# ---------------------------------------------------------------- 2. Caps Lock

# 연결된 키보드를 VendorID-ProductID-CountryCode 형식으로 출력한다.
# System Settings 가 쓰는 키 이름과 동일한 형식.
list_keyboards() {
    ioreg -r -c IOHIDInterface -l -w 0 2>/dev/null | awk '
        /^\+-o/               { flush(); v=""; p=""; c=""; kbd=0 }
        /"VendorID" =/        { v = $NF }
        /"ProductID" =/       { p = $NF }
        /"CountryCode" =/     { c = $NF }
        /"PrimaryUsage" = 6$/ { kbd = 1 }
        /"DeviceUsagePage"=1,"DeviceUsage"=6[},]/ { kbd = 1 }
        END { flush() }
        function flush() { if (kbd && v != "" && p != "") print v "-" p "-" (c == "" ? 0 : c) }
    ' | sort -u
}

# 매 로그인마다 hidutil 로 Caps Lock -> fn 을 다시 적용하는 사용자 LaunchAgent.
# ~/Library/LaunchAgents 는 사용자 소유라 관리자 권한이 필요 없다.
install_capslock_agent() {
    dir="$HOME/Library/LaunchAgents"
    plist="$dir/$CAPS_AGENT.plist"
    mkdir -p "$dir" || { warn "$dir 을 만들 수 없습니다"; return 1; }
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$CAPS_AGENT</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>$HIDUTIL_MAPPING</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$uid/$CAPS_AGENT" >/dev/null 2>&1
    if launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1; then
        info "로그인 에이전트 $CAPS_AGENT 등록 (매 로그인마다 재적용)"
    else
        warn "로그인 에이전트 등록 실패: $plist"
    fi
}

setup_capslock() {
    step "2. 보조 키: Caps Lock -> fn 기능"

    # System Settings 와 같은 형식으로 저장한다. 값은 반드시 정수여야 한다.
    # 예전처럼 "({Src=...;Dst=...;})" 문자열로 쓰면 숫자가 문자열로 저장되어
    # 시스템이 무시하고, 재로그인 뒤 매핑이 사라진다.
    pair="<dict><key>HIDKeyboardModifierMappingSrc</key><integer>$CAPS</integer><key>HIDKeyboardModifierMappingDst</key><integer>$FN</integer></dict>"

    kbds=$(list_keyboards)
    if [ -z "$kbds" ]; then
        warn "연결된 키보드를 찾지 못해 Apple Magic Keyboard 기본값으로 적용합니다"
        kbds="1452-591-0"
    fi
    for kbd in $kbds; do
        defaults -currentHost write -g "com.apple.keyboard.modifiermapping.$kbd" -array "$pair"
        info "modifiermapping.$kbd"
    done

    # 지금 바로 적용 (HID 레벨, 로그아웃 시 사라짐) + 로그인 에이전트로 매번 재적용
    if hidutil property --set "$HIDUTIL_MAPPING" >/dev/null 2>&1; then
        info "hidutil 즉시 적용 완료"
    else
        warn "hidutil 즉시 적용 실패 (로그아웃 후 다시 로그인하면 적용됩니다)"
    fi
    install_capslock_agent
}

# ---------------------------------------------------------------- 3. 입력 소스

# 입력 소스를 System Settings 와 같은 API(TISEnableInputSource)로 켠다.
# 지금 바로 메뉴에 나타나고, 다른 프로세스가 설정 파일을 덮어써도 살아남는다.
# swift 는 컴파일 지연과 개발자 도구 의존이 있어 JXA(osascript)로 호출한다.
#
#   tis status <id>  ->  enabled | disabled | notfound
#   tis enable <id>  ->  requested | already | notfound
#
# 켠 직후의 상태는 같은 프로세스 안에서는 갱신되어 보이지 않으므로
# 확인은 반드시 별도 프로세스(tis status)로 한다.
TIS_JS='
function run(argv) {
    ObjC.import("Carbon");
    var action = argv[0], id = argv[1];
    var filter = $.NSMutableDictionary.dictionary;
    filter.setObjectForKey($(id), ObjC.castRefToObject($.kTISPropertyInputSourceID));
    var list = ObjC.castRefToObject($.TISCreateInputSourceList(filter, true));
    if (!list || list.isNil() || !list.count) return "notfound";
    var src = list.objectAtIndex(0);
    var enabled = ObjC.castRefToObject($.TISGetInputSourceProperty(src, $.kTISPropertyInputSourceIsEnabled)).js;
    if (action === "status") return enabled ? "enabled" : "disabled";
    if (enabled) return "already";
    $.TISEnableInputSource(src);
    return "requested";
}'
tis() { osascript -l JavaScript -e "$TIS_JS" "$1" "$2" 2>/dev/null; }

# 로그인 시 읽는 저장 목록(com.apple.HIToolbox AppleEnabledInputSources)에도 넣어 둔다.
# TIS API 로 켠 것은 이 목록에 자동으로 기록되지 않는다.
hitoolbox_has() {
    defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null \
        | grep -q "\"Input Mode\" = \"$1\";"
}
hitoolbox_add() {
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add \
        "<dict><key>Bundle ID</key><string>$GUREUM_BUNDLE</string><key>Input Mode</key><string>$1</string><key>InputSourceKind</key><string>Input Mode</string></dict>"
}

setup_input_sources() {
    step "3. 입력 소스에 구름 입력기 추가"
    for m in "$@"; do
        case "$m" in "$GUREUM_BUNDLE".*) id="$m" ;; *) id="$GUREUM_BUNDLE.$m" ;; esac

        case "$(tis enable "$id")" in
            notfound)  warn "$id - 구름 입력기에 없는 모드입니다. --list 로 확인하세요."; continue ;;
            already)   info "$id (이미 켜져 있음)" ;;
            requested)
                # 반영까지 몇 초 걸릴 수 있어 최대 8초 동안 확인한다
                tries=0
                while [ "$tries" -lt 8 ] && [ "$(tis status "$id")" != "enabled" ]; do
                    sleep 1; tries=$((tries + 1))
                done
                if [ "$tries" -lt 8 ]; then
                    info "$id 켬 (즉시 적용)"
                else
                    warn "$id - 즉시 적용을 확인하지 못했습니다. 재로그인 후 적용됩니다"
                fi ;;
            *)         warn "$id - 즉시 적용 실패 (osascript 오류), 재로그인 후 적용됩니다" ;;
        esac

        if hitoolbox_has "$id"; then
            info "$id 저장 목록에 있음"
        elif hitoolbox_add "$id"; then
            info "$id 저장 목록에 추가 (재로그인 후에도 유지)"
        else
            warn "$id 저장 목록 추가 실패"
        fi
    done
}

# ---------------------------------------------------------------- main

main() {
    [ "$(uname -s)" = "Darwin" ] || die "이 스크립트는 macOS 전용입니다."
    uid=$(id -u)

    app=$(find_gureum) || die "구름 입력기(Gureum.app)가 설치되어 있지 않습니다.
관리자 설치가 어렵다면 관리자 권한 없이 사용자 영역에만 설치할 수 있습니다:
  mkdir -p ~/Library/Input\\ Methods
  # Gureum.app 을 ~/Library/Input Methods/ 로 복사한 뒤 로그아웃/로그인"

    if [ "${1:-}" = "--list" ]; then
        echo "설치 위치: $app"
        echo "사용 가능한 입력 모드:"
        $PB -c "Print :ComponentInputModeDict:tsInputModeListKey" "$app/Contents/Info.plist" \
            | sed -n 's/^    \('"$GUREUM_BUNDLE"'\.[A-Za-z0-9._-]*\) = Dict {/  \1/p' | sort
        return 0
    fi

    [ "$#" -eq 0 ] && set -- han2

    wait_for_login_init
    setup_fn_key
    setup_capslock
    setup_input_sources "$@"

    printf '\n\033[1m완료.\033[0m fn 키 동작, Caps Lock -> fn, 입력 소스 모두 지금 적용되었고\n'
    printf '재로그인 후에도 유지됩니다. 문제가 있으면 한 번 로그아웃 후 다시 로그인하세요.\n'
}

main "$@"
