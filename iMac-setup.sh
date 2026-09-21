#!/bin/sh
#
# macOS 키보드 실습 환경 자동 설정 (관리자 권한 불필요, UI 조작 불필요, 재로그인 불필요)
# 대상: macOS Sequoia 15.7 + 구름 입력기 1.13
#
#   0. 로그인 초기화 대기
#      관리자가 설치한 로그인 에이전트(kr.codyssey.gureum.init)가 구름 입력기를 띄우고
#      두벌식을 강제 선택하는 작업이 끝날 때까지 기다린다. 이 작업과 동시에 설정을
#      바꾸면 나중에 끝나는 쪽이 입력 소스 목록을 덮어쓴다.
#   1. 키보드 > fn 키를 누를 때 실행할 동작   -> 입력 소스 변경
#   2. 키보드 단축키 > 보조 키 > Caps Lock 키 -> fn 기능
#   3. 텍스트 입력 > 입력 소스                -> 구름 입력기 (두벌식 + 요청한 배열)
#      요청하지 않은 구름 배열, 특히 구름 로마자(system)는 끈다. 3. 입력 소스 절 참고.
#
# 사용법:
#   curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh                    # 두벌식
#   curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- han3final    # 세벌식 최종
#   curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- --list       # 배열 목록
#
# Sequoia 에서 설정이 저장되는 곳 (System Settings 가 쓰는 것과 동일하게 맞춘다):
#   - fn 키 동작:        com.apple.HIToolbox  AppleFnUsageType
#   - Caps Lock 매핑:    ByHost .GlobalPreferences  com.apple.keyboard.modifiermapping.<VID>-<PID>-<CC>
#                        (정수 값. 즉시 적용은 HID 이벤트 시스템에 HIDKeyboardModifierMappingPairs 를 직접 넣는다)
#   - 구름 입력 소스:    com.apple.inputsources  AppleEnabledThirdPartyInputSources
#                        (서드파티 입력기는 여기. com.apple.HIToolbox AppleEnabledInputSources 에도
#                         넣으면 설정 화면에 같은 항목이 여러 개 나타난다. 파일만 고치면 실행 중인
#                         앱은 모르므로 TIS API 호출로 전파한다. 3. 입력 소스 절 참고)
#
# curl | sh 로 중간에 끊겨도 부분 실행되지 않도록 전체를 main() 에 담고
# 마지막 줄에서 호출한다. /bin/sh(bash 3.2 POSIX 모드)에서 동작하도록
# 배열과 프로세스 치환은 쓰지 않는다. 시스템 API 는 swift 대신 JXA(osascript)로
# 부른다. swift 는 컴파일 지연이 있고, TISEnableInputSource 는 서드파티 입력기에 대해
# System Settings 밖에서는 무시되거나 "서드파티 입력 방법을 활성화하려고 합니다" 확인
# 창을 띄우므로 쓰지 않는다.

set -u

PB=/usr/libexec/PlistBuddy
GUREUM_BUNDLE="org.youknowone.inputmethod.Gureum"
DEFAULT_MODE="han2"                                   # 항상 포함. 로그인 에이전트가 강제 선택하는 배열
ROMAN_MODE="system"                                   # 구름 로마자. macOS 가 멋대로 켜므로 덤 배열로 쓴다

LOGIN_AGENT="kr.codyssey.gureum.init"                 # 관리자가 설치한 로그인 에이전트
LOGIN_AGENT_PROCS='init_gureum\.sh|set_gureum_ime\.swift'
WAIT_MAX=180                                          # 초

OLD_CAPS_AGENT="local.imac-setup.capslock-fn"         # 이전 버전이 설치하던 사용자 에이전트 (제거)
CAPS=30064771129                                      # 0x700000039  Caps Lock
FN=1095216660483                                      # 0xFF00000003 fn(지구본)

info() { printf '  \033[32m/\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

jxa() { osascript -l JavaScript -e "$1" "$2" "${3:-}" 2>/dev/null; }

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

# 로그인 시 시스템이 ByHost 설정을 읽어 키보드 서비스에 넣는 속성
# (HIDKeyboardModifierMappingPairs)을 지금 바로 넣는다. System Settings 가 즉시
# 적용할 때와 같은 경로다. hidutil 은 다른 종류의 클라이언트를 써서 이 속성을
# 넣지 못하고, hidutil UserKeyMapping 으로 fn 을 만들면 입력 소스 전환이 되지 않는다.
# 출력: 적용한 키보드 서비스 수
HID_JS='
function run(argv) {
    ObjC.import("IOKit"); ObjC.import("Foundation");
    ObjC.bindFunction("IOHIDEventSystemClientCreateWithType", ["void *", ["void *", "int", "void *"]]);
    ObjC.bindFunction("IOHIDEventSystemClientSetMatching", ["void", ["void *", "id"]]);
    ObjC.bindFunction("IOHIDEventSystemClientCopyServices", ["id", ["void *"]]);
    ObjC.bindFunction("IOHIDServiceClientSetProperty", ["bool", ["void *", "id", "id"]]);
    var pairs = $([{HIDKeyboardModifierMappingSrc: parseInt(argv[0]), HIDKeyboardModifierMappingDst: parseInt(argv[1])}]);
    var client = $.IOHIDEventSystemClientCreateWithType($(), 1, $());   // 1 = monitor
    $.IOHIDEventSystemClientSetMatching(client, $({PrimaryUsagePage: 1, PrimaryUsage: 6}));
    var services = $.IOHIDEventSystemClientCopyServices(client);
    if (!services || services.isNil()) return "0";
    var ok = 0;
    for (var i = 0; i < services.count; i++) {
        var svc = ObjC.castObjectToRef(services.objectAtIndex(i));
        if ($.IOHIDServiceClientSetProperty(svc, $("HIDKeyboardModifierMappingPairs"), pairs)) ok++;
    }
    return String(ok);
}'

setup_capslock() {
    step "2. 보조 키: Caps Lock -> fn 기능"

    # 저장 (재로그인 후 유지). System Settings 와 같은 위치, 같은 형식. 값은 반드시 정수.
    # 문자열로 저장되면 시스템이 무시한다.
    pair="<dict><key>HIDKeyboardModifierMappingSrc</key><integer>$CAPS</integer><key>HIDKeyboardModifierMappingDst</key><integer>$FN</integer></dict>"
    kbds=$(list_keyboards)
    if [ -z "$kbds" ]; then
        warn "연결된 키보드를 찾지 못해 Apple Magic Keyboard 기본값으로 저장합니다"
        kbds="1452-591-0"
    fi
    for kbd in $kbds; do
        defaults -currentHost write -g "com.apple.keyboard.modifiermapping.$kbd" -array "$pair"
        info "modifiermapping.$kbd 저장"
    done

    # 즉시 적용
    n=$(jxa "$HID_JS" "$CAPS" "$FN")
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
        info "키보드 ${n}대에 즉시 적용"
    else
        warn "즉시 적용 실패. 로그아웃 후 다시 로그인하면 적용됩니다"
    fi

    # 이전 버전이 남긴 hidutil UserKeyMapping 과 로그인 에이전트 정리
    hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1
    if [ -f "$HOME/Library/LaunchAgents/$OLD_CAPS_AGENT.plist" ]; then
        launchctl bootout "gui/$uid/$OLD_CAPS_AGENT" >/dev/null 2>&1
        rm -f "$HOME/Library/LaunchAgents/$OLD_CAPS_AGENT.plist"
        info "이전 버전의 로그인 에이전트 $OLD_CAPS_AGENT 제거"
    fi
}

# ---------------------------------------------------------------- 3. 입력 소스
#
# 서드파티 입력 소스 목록은 com.apple.inputsources 에 저장되지만, 파일만 고쳐서는 이미
# 실행 중인 프로세스(앱, 메뉴 막대, System Settings)가 목록을 다시 읽지 않는다. 배포 알림
# (AppleEnabledInputSourcesChangedNotification)이나 Darwin 알림(TISNotify...)을 직접
# 보내도, TextInputMenuAgent 를 다시 띄워도 마찬가지다(Sequoia 15.7 에서 확인). 그 상태로
# 메뉴에서 구름을 고르면 앞 앱은 "켜지지 않은 소스"로 보고 무시해서 아이콘이 바뀌지 않는다.
# System Settings 에서 아무 입력 소스나 추가했다 지우면 그때부터 동작하는 이유가 이것이다.
#
# 실행 중인 프로세스까지 갱신하는 것은 TIS API 호출뿐이다. 그런데 TISEnableInputSource 는
# 서드파티 배열에 대해 System Settings 밖에서는 조용히 무시되거나 확인 창을 띄우고,
# TISDisableInputSource 는 그냥 동작한다. 그래서 목록을 저장할 때 쓰지 않는 구름 배열
# 하나를 덤으로 넣어 두고 API 로 끈다. 끄는 순간 모든 프로세스가 목록 전체를 다시 읽는다.
#
# 덤 배열은 반드시 "지금 켜져 있는" 것이어야 한다. 이미 꺼진 배열에 TISDisableInputSource 를
# 부르면 0 을 돌려주지만 아무 일도 일어나지 않는다(전파 없음). 그래서 덤 배열도 파일에 먼저
# 켜서 써 둔다.
#
# 덤 배열로는 구름 로마자(system)를 먼저 고른다. Gureum.app Info.plist 에서
# tsInputModeDefaultStateKey 가 참인 배열은 han2(두벌식)와 system(로마자) 둘뿐이고,
# 로그인 에이전트가 TISEnableInputSource 로 구름 입력기를 켜면 macOS 가 이 둘을 자동으로
# 켠다. 구름 로마자는 smRoman + primaryInScript 라서 켜져 있으면 ABC 자리를 가로채
# 메뉴 막대에 "로마자"가 뜨고 앱의 입력 소스 전환이 어긋난다. 어차피 꺼야 하는 것이므로
# 전파용으로 같이 쓴다. 마지막에는 요청하지 않았는데 켜져 있는 구름 배열이 하나도 남지
# 않을 때까지 끄기를 되풀이한다.

# 지금 켜져 있는 입력 소스 중 인자로 받은 번들의 것을 모두 출력한다 (한 줄에 하나).
# TISCreateInputSourceList 의 두 번째 인자가 false 면 켜진 것만 돌려준다.
ENABLED_JS='
function run(argv) {
    ObjC.import("Carbon");
    var filter = $.NSMutableDictionary.dictionary;
    filter.setObjectForKey($(argv[0]), ObjC.castRefToObject($.kTISPropertyBundleID));
    var list = ObjC.castRefToObject($.TISCreateInputSourceList(filter, false));
    if (!list || list.isNil()) return "";
    var out = [];
    for (var i = 0; i < list.count; i++) {
        var id = ObjC.castRefToObject($.TISGetInputSourceProperty(list.objectAtIndex(i), $.kTISPropertyInputSourceID)).js;
        if (id) out.push(id);
    }
    return out.join("\n");
}'

# 입력 소스가 지금 켜져 있는지 (새 프로세스라 저장 파일 기준의 최신 상태가 보인다)
# 출력: enabled | disabled | notfound
TIS_JS='
function run(argv) {
    ObjC.import("Carbon");
    var filter = $.NSMutableDictionary.dictionary;
    filter.setObjectForKey($(argv[0]), ObjC.castRefToObject($.kTISPropertyInputSourceID));
    var list = ObjC.castRefToObject($.TISCreateInputSourceList(filter, true));
    if (!list || list.isNil() || !list.count) return "notfound";
    var on = ObjC.castRefToObject($.TISGetInputSourceProperty(list.objectAtIndex(0), $.kTISPropertyInputSourceIsEnabled)).js;
    return on ? "enabled" : "disabled";
}'

# 입력 소스를 TIS API 로 끈다. 목록이 바뀌었다는 사실이 실행 중인 모든 프로세스에 전파된다.
# 출력: ok | notfound | error <status>
DISABLE_JS='
function run(argv) {
    ObjC.import("Carbon"); ObjC.import("Foundation");
    var filter = $.NSMutableDictionary.dictionary;
    filter.setObjectForKey($(argv[0]), ObjC.castRefToObject($.kTISPropertyInputSourceID));
    var list = ObjC.castRefToObject($.TISCreateInputSourceList(filter, true));
    if (!list || list.isNil() || !list.count) return "notfound";
    var st = $.TISDisableInputSource(list.objectAtIndex(0));
    $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(1));
    return st == 0 ? "ok" : "error " + st;
}'

# 설정을 바꾸기 전에 띄워 두는 감시 프로세스. 자기 캐시 기준으로 인자로 받은 입력 소스가
# 모두 켜졌는지 매초 한 줄씩 출력하고, 모두 켜지면 끝난다. 새 프로세스의 확인(TIS_JS)은
# 저장 파일만 보여 주므로 "이미 떠 있던 프로세스에 전파되었는가"는 이것으로만 알 수 있다.
# 인자: <최대 초> <입력 소스 ID>...   출력: ok | pending <아직 안 켜진 ID>...
WATCH_JS='
function run(argv) {
    ObjC.import("Carbon"); ObjC.import("Foundation");
    var out = $.NSFileHandle.fileHandleWithStandardOutput;
    var secs = parseInt(argv.shift());
    for (var i = 0; i < secs; i++) {
        var missing = argv.filter(function (id) {
            var filter = $.NSMutableDictionary.dictionary;
            filter.setObjectForKey($(id), ObjC.castRefToObject($.kTISPropertyInputSourceID));
            var list = ObjC.castRefToObject($.TISCreateInputSourceList(filter, true));
            if (!list || list.isNil() || !list.count) return true;
            return !ObjC.castRefToObject($.TISGetInputSourceProperty(list.objectAtIndex(0), $.kTISPropertyInputSourceIsEnabled)).js;
        });
        var line = missing.length ? "pending " + missing.join(" ") : "ok";
        out.writeData($(line + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
        if (!missing.length) return "";
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(1));
    }
    return "";
}'

# 구름 입력기 배열 이름 목록 (han2 han3final ...)
gureum_modes() {
    $PB -c "Print :ComponentInputModeDict:tsInputModeListKey" "$1/Contents/Info.plist" \
        | sed -n 's/^    '"$GUREUM_BUNDLE"'\.\([A-Za-z0-9._-]*\) = Dict {/\1/p' | sort
}

# 배열 배열(plist 의 dict 배열)에서 구름 입력기 항목을 모두 지운다. $1=plist $2=키
delete_gureum_entries() {
    i=0; n=0
    while $PB -c "Print :$2:$i" "$1" >/dev/null 2>&1; do
        if $PB -c "Print :$2:$i:'Bundle ID'" "$1" 2>/dev/null | grep -q "^$GUREUM_BUNDLE\$"; then
            $PB -c "Delete :$2:$i" "$1"; n=$((n + 1))
        else
            i=$((i + 1))
        fi
    done
    echo "$n"
}

# 서드파티 목록 끝에 구름 배열 항목을 추가한다. $1=plist $2=배열 이름
add_gureum_mode() {
    n=0
    while $PB -c "Print :AppleEnabledThirdPartyInputSources:$n" "$1" >/dev/null 2>&1; do
        n=$((n + 1))
    done
    $PB -c "Add :AppleEnabledThirdPartyInputSources:$n dict" \
        -c "Add :AppleEnabledThirdPartyInputSources:$n:'Bundle ID' string '$GUREUM_BUNDLE'" \
        -c "Add :AppleEnabledThirdPartyInputSources:$n:'Input Mode' string '$GUREUM_BUNDLE.$2'" \
        -c "Add :AppleEnabledThirdPartyInputSources:$n:InputSourceKind string 'Input Mode'" \
        "$1" >/dev/null
}

# 요청 목록($1, 공백 구분)에 없는데 지금 켜져 있는 구름 배열 이름들을 출력한다.
# 새 프로세스로 물으므로 저장 파일 기준의 최신 상태가 보인다.
stray_modes() {
    for id in $(jxa "$ENABLED_JS" "$GUREUM_BUNDLE"); do
        case "$id" in "$GUREUM_BUNDLE".*) m=${id#"$GUREUM_BUNDLE".} ;; *) continue ;; esac
        case " $1 " in *" $m "*) ;; *) printf '%s\n' "$m" ;; esac
    done
}

setup_input_sources() {
    app="$1"; shift
    step "3. 입력 소스: 구름 입력기"

    # 요청한 배열 검증 + 두벌식은 항상 포함 (로그인 에이전트가 두벌식을 켜려 할 때
    # 목록에 없으면 "서드파티 입력 방법을 활성화하려고 합니다" 확인 창이 뜬다)
    modes="$DEFAULT_MODE"
    for m in "$@"; do
        case "$m" in "$GUREUM_BUNDLE".*) m=${m#"$GUREUM_BUNDLE".} ;; esac
        if ! $PB -c "Print :ComponentInputModeDict:tsInputModeListKey:$GUREUM_BUNDLE.$m" \
                 "$app/Contents/Info.plist" >/dev/null 2>&1; then
            warn "$m - 구름 입력기에 없는 배열입니다. --list 로 확인하세요."
            continue
        fi
        case " $modes " in *" $m "*) ;; *) modes="$modes $m" ;; esac
    done

    # 전파용 덤 배열: 구름 로마자를 먼저, 없으면 쓰지 않는 배열 아무거나 하나
    all_modes=$(gureum_modes "$app")
    dummy=""
    for m in $(printf '%s\n' "$all_modes" | grep -x "$ROMAN_MODE") $all_modes; do
        case " $modes " in *" $m "*) ;; *) dummy="$m"; break ;; esac
    done

    # 전파 확인용 감시 프로세스. 설정을 바꾸기 전에 띄워야 "예전 상태를 기억하는 프로세스"가 된다.
    ids=""
    for m in $modes; do ids="$ids $GUREUM_BUNDLE.$m"; done
    watch_out=$(mktemp -t watch) || die "임시 파일을 만들 수 없습니다"
    # shellcheck disable=SC2086
    osascript -l JavaScript -e "$WATCH_JS" 15 $ids > "$watch_out" 2>/dev/null &
    watch_pid=$!

    # (a) 예전 방식으로 HIToolbox 에 들어간 구름 항목 제거 (설정 화면 중복의 원인)
    pl=$(mktemp -t HIToolbox) || die "임시 파일을 만들 수 없습니다"
    defaults export com.apple.HIToolbox "$pl" 2>/dev/null || printf '{}\n' > "$pl"
    n=$(delete_gureum_entries "$pl" AppleEnabledInputSources)
    if [ "$n" -gt 0 ]; then
        defaults import com.apple.HIToolbox "$pl"
        info "HIToolbox 에 잘못 들어간 구름 항목 ${n}개 제거"
    fi
    rm -f "$pl"

    # (b) 서드파티 입력 소스 목록을 구름 입력기 + 배열들(+ 덤 배열)로 다시 쓴다
    #     (다른 서드파티 입력기 항목은 그대로 둔다)
    pl=$(mktemp -t inputsources) || die "임시 파일을 만들 수 없습니다"
    defaults export com.apple.inputsources "$pl" 2>/dev/null || printf '{}\n' > "$pl"
    $PB -c "Print :AppleEnabledThirdPartyInputSources" "$pl" >/dev/null 2>&1 \
        || $PB -c "Add :AppleEnabledThirdPartyInputSources array" "$pl" >/dev/null
    delete_gureum_entries "$pl" AppleEnabledThirdPartyInputSources >/dev/null
    count=0
    while $PB -c "Print :AppleEnabledThirdPartyInputSources:$count" "$pl" >/dev/null 2>&1; do
        count=$((count + 1))
    done
    $PB -c "Add :AppleEnabledThirdPartyInputSources:$count dict" \
        -c "Add :AppleEnabledThirdPartyInputSources:$count:'Bundle ID' string '$GUREUM_BUNDLE'" \
        -c "Add :AppleEnabledThirdPartyInputSources:$count:InputSourceKind string 'Keyboard Input Method'" \
        "$pl" >/dev/null
    for m in $modes $dummy; do add_gureum_mode "$pl" "$m"; done
    defaults import com.apple.inputsources "$pl"
    rm -f "$pl"
    info "저장: $modes"

    # (c) 전파와 정리: 요청하지 않았는데 켜져 있는 구름 배열(덤 배열, 그리고 macOS 가
    #     자동으로 켠 구름 로마자)을 TIS API 로 끈다. 이 호출만이 목록 변경을 실행 중인
    #     모든 프로세스에 전파한다. 하나도 남지 않을 때까지 되풀이한다.
    [ -n "$dummy" ] || warn "전파용 배열이 없습니다 (모든 배열을 요청함). 로그아웃 후 다시 로그인하세요"
    round=0
    while :; do
        strays=$(stray_modes "$modes")
        [ -n "$strays" ] || break
        round=$((round + 1))
        if [ "$round" -gt 4 ]; then
            warn "요청하지 않은 배열이 계속 켜집니다:$(printf ' %s' $strays)
    System Settings > 키보드 > 입력 소스에서 지우거나, 로그아웃 후 다시 로그인하세요"
            break
        fi
        for m in $strays; do
            r=$(jxa "$DISABLE_JS" "$GUREUM_BUNDLE.$m")
            if [ "$r" = "ok" ]; then
                info "요청하지 않은 배열 $m 끔"
            else
                warn "$m 을(를) 끄지 못했습니다 (${r:-osascript 오류})"
            fi
        done
    done

    # (d) 확인 1: 저장 파일 기준 (새 프로세스)
    for m in $modes; do
        id="$GUREUM_BUNDLE.$m"
        case "$(jxa "$TIS_JS" "$id")" in
            enabled) info "$id 켜짐" ;;
            *)       warn "$id - 아직 켜지지 않았습니다. 로그아웃 후 다시 로그인하세요" ;;
        esac
    done

    # (d) 확인 2: 이미 떠 있던 프로세스에 전파되었는가 (감시 프로세스 기준)
    wait "$watch_pid" 2>/dev/null
    case "$(grep -v '^$' "$watch_out" | tail -1)" in
        ok) info "실행 중인 앱과 메뉴 막대에도 반영됨" ;;
        *)  warn "실행 중인 앱에는 아직 반영되지 않았습니다. System Settings > 키보드 > 입력 소스에서
    아무 입력 소스나 추가했다 지우거나, 로그아웃 후 다시 로그인하세요" ;;
    esac
    rm -f "$watch_out"
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
        echo "사용 가능한 배열 (이름만 쓰면 됩니다. 예: han3final):"
        gureum_modes "$app" | sed 's/^/  /'
        echo "system(로마자)과 hanroman(한글 로마자)은 영문 입력용이 아닙니다. 영문은 ABC 를 쓰세요."
        return 0
    fi

    wait_for_login_init
    setup_fn_key
    setup_capslock
    setup_input_sources "$app" "$@"

    printf '\n\033[1m완료.\033[0m 세 항목 모두 지금 적용되었고 재로그인 후에도 유지됩니다.\n'
    printf 'Caps Lock 을 눌러 ABC 와 구름 입력기 사이를 전환해 보세요.\n'
}

main "$@"
