#!/bin/sh
#
# newids 개인용 실습 iMac 설정. iMac-setup.sh 와 setup.sh 를 하나로 합친 것.
# 대상: macOS Sequoia 15.7 + 구름 입력기 1.13. 관리자 권한·UI 조작·재로그인 불필요.
#
#   0. 로그인 초기화 대기                        iMac-setup.sh 와 같음
#   1. fn 키를 누를 때 실행할 동작 -> 입력 소스 변경   같음
#   2. Caps Lock -> fn                            같음
#   3. 입력 소스 -> 구름 세벌식 최종만            다름: 두벌식(han2)을 넣지 않는다 (아래 참고)
#   4. 핫 코너                                    좌상단 Mission Control, 우상단 응용 프로그램 윈도우,
#                                                 좌하단 잠금 화면, 우하단 빠른 메모
#   5. zsh 프롬프트                              setup.sh 의 zshrc 를 내장
#   6. ssh 키, known_hosts, ssh config, git 설정   setup.sh 와 같음. 키는 keys.zip.enc 를 받아 복호화
#   7. Discord 실행 시 본체 업데이트 건너뛰기      settings.json 에 SKIP_HOST_UPDATE
#   8. VS Code 업데이트 확인 끄기                  settings.json 에 update.mode = none
#   9. 터미널: Homebrew 프로파일, 글꼴 14, 90x45   기본·시작 프로파일로 지정
#  10. Claude Code 설치                           같음
#  11. 앱 실행: Discord, VS Code, Chrome           Chrome 은 새 창에 https://codyssey.kr
#
# 사용법:
#   curl -fsSL https://newids.github.io/imac-setup/iMac4newids.sh | sh
#
# 두벌식을 넣지 않는 것에 대해:
#   관리자가 설치한 로그인 에이전트(kr.codyssey.gureum.init)는 로그인할 때마다 구름 두벌식을 켜고
#   선택한다. 이 스크립트는 그 작업이 끝나기를 기다린 뒤 두벌식을 끄고 세벌식 최종만 남기므로
#   로그인할 때마다 다시 실행해야 한다. 목록에 두벌식이 없는 상태에서 에이전트가 두벌식을 켜면
#   "서드파티 입력 방법을 활성화하려고 합니다" 확인 창이 뜰 수 있다. 창은 닫고 이 스크립트를 실행하면 된다.
#
# ssh 키:
#   keys.zip 을 encrypt.sh(openssl aes-256-cbc + pbkdf2)로 암호화한 keys.zip.enc 를 이 스크립트와 같은
#   곳(BASE_URL)에 둔다. 실행 중 암호를 터미널(/dev/tty)에서 묻는다. 파일이 없거나 암호가 틀리면 그 단계만
#   건너뛴다. 암호화하지 않은 키를 공개 저장소나 GitHub Pages 에 두지 말 것.
#
# 나머지 설계 배경(저장 위치, TIS API 전파, 덤 배열)은 iMac-setup.sh 머리말과 docs/iMac-setup-notes.md 참고.
# /bin/sh(bash 3.2 POSIX 모드) 전용. 배열, 프로세스 치환, [[ ]] 금지. 전체를 main() 에 담고 마지막 줄에서 부른다.

set -u

BASE_URL="https://newids.github.io/imac-setup"

PB=/usr/libexec/PlistBuddy
GUREUM_BUNDLE="org.youknowone.inputmethod.Gureum"
MODES="han3final"                                     # 넣을 구름 배열. 두벌식(han2)은 넣지 않는다
ROMAN_MODE="system"                                   # 구름 로마자. macOS 가 멋대로 켜므로 덤 배열로 쓴다

LOGIN_AGENT="kr.codyssey.gureum.init"                 # 관리자가 설치한 로그인 에이전트
LOGIN_AGENT_PROCS='init_gureum\.sh|set_gureum_ime\.swift'
WAIT_MAX=180                                          # 초

OLD_CAPS_AGENT="local.imac-setup.capslock-fn"         # 이전 버전이 설치하던 사용자 에이전트 (제거)
CAPS=30064771129                                      # 0x700000039  Caps Lock
FN=1095216660483                                      # 0xFF00000003 fn(지구본)

ZSHRC_MARK='# --- claude-docker zshrc ---'            # setup.sh 와 같은 표식. 둘 중 하나만 추가된다
GIT_EMAIL="newids@gmail.com"
GIT_NAME="Jeanseok Choi"
# GitHub 이 공개한 ed25519 호스트 키 지문
# https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
GITHUB_FP_ED25519="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

info() { printf '  \033[32m/\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

jxa() { js="$1"; shift; osascript -l JavaScript -e "$js" "$@" 2>/dev/null; }   # $1=스크립트, 나머지=argv

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
# 적용할 때와 같은 경로다. 출력: 적용한 키보드 서비스 수
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
# 목록은 com.apple.inputsources 에 쓰고, 실행 중인 앱에 전파하기 위해 쓰지 않는 구름 배열(덤 배열,
# 우선 구름 로마자)을 함께 켜 두었다가 TISDisableInputSource 로 끈다. 요청하지 않았는데 켜져 있는
# 구름 배열(덤 배열, macOS 가 자동으로 켠 로마자, 로그인 에이전트가 켠 두벌식)이 하나도 남지 않을
# 때까지 끄기를 되풀이한다. 자세한 이유는 iMac-setup.sh 3절 주석과 docs/iMac-setup-notes.md 참고.

# 지금 켜져 있는 입력 소스 중 인자로 받은 번들의 것을 모두 출력한다 (한 줄에 하나).
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
# 모두 켜졌는지 매초 한 줄씩 출력하고, 모두 켜지면 끝난다.
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
stray_modes() {
    for id in $(jxa "$ENABLED_JS" "$GUREUM_BUNDLE"); do
        case "$id" in "$GUREUM_BUNDLE".*) m=${id#"$GUREUM_BUNDLE".} ;; *) continue ;; esac
        case " $1 " in *" $m "*) ;; *) printf '%s\n' "$m" ;; esac
    done
}

setup_input_sources() {
    app="$1"
    step "3. 입력 소스: 구름 세벌식 최종만"

    modes="$MODES"
    for m in $modes; do
        $PB -c "Print :ComponentInputModeDict:tsInputModeListKey:$GUREUM_BUNDLE.$m" \
            "$app/Contents/Info.plist" >/dev/null 2>&1 \
            || die "$m - 설치된 구름 입력기에 없는 배열입니다."
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

    # (b) 서드파티 입력 소스 목록을 구름 입력기 + 배열(+ 덤 배열)로 다시 쓴다
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

    # (c) 전파와 정리: 요청하지 않았는데 켜져 있는 구름 배열을 TIS API 로 끈다. 두벌식도 여기서 꺼진다.
    [ -n "$dummy" ] || warn "전파용 배열이 없습니다. 로그아웃 후 다시 로그인하세요"
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

# ---------------------------------------------------------------- 4. 핫 코너
#
# 데스크탑 및 Dock > 핫 코너. com.apple.dock 의 wvous-<tl|tr|bl|br>-corner 값:
#   0/1 없음  2 Mission Control  3 응용 프로그램 윈도우  4 데스크탑  5 화면 보호기 시작  6 화면 보호기 끔
#   10 디스플레이 잠자기  11 Launchpad  12 알림 센터  13 잠금 화면  14 빠른 메모
# -modifier 는 함께 눌러야 하는 보조 키(0 = 없음). Dock 을 다시 띄워야 바로 적용된다.

set_hot_corner() {
    defaults write com.apple.dock "wvous-$1-corner" -int "$2"
    defaults write com.apple.dock "wvous-$1-modifier" -int 0
    info "$3 -> $4"
}

setup_hot_corners() {
    step "4. 핫 코너"
    set_hot_corner tl 2  좌상단 "Mission Control"
    set_hot_corner tr 3  우상단 "응용 프로그램 윈도우"
    set_hot_corner bl 13 좌하단 "잠금 화면"
    set_hot_corner br 14 우하단 "빠른 메모"
    if killall Dock 2>/dev/null; then
        info "Dock 다시 시작 (즉시 적용)"
    else
        warn "Dock 을 다시 띄우지 못했습니다. 로그아웃 후 다시 로그인하면 적용됩니다"
    fi
}

# ---------------------------------------------------------------- 5. zsh

setup_zsh() {
    step "5. zsh 프롬프트"
    if grep -qF "$ZSHRC_MARK" "$HOME/.zshrc" 2>/dev/null; then
        info "~/.zshrc 에 이미 있음"
        return 0
    fi
    {
        printf '\n%s\n' "$ZSHRC_MARK"
        cat <<'EOF'
alias l='ls -l'
alias ll='ls -alF'

# 1. vcs_info 모듈 로드 및 초기화
autoload -Uz vcs_info
precmd() { vcs_info }

# 2. Git 브랜치 표시 형식 설정
# %b: 브랜치 이름, %u: 스테이징되지 않은 변경사항, %c: 스테이징된 변경사항
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%F{yellow}(%b%u%c)%f'
zstyle ':vcs_info:git:*' actionformats '%F{red}(%b|%a)%f'

# 3. 변경사항 상태 기호 설정
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '%F{red}*%f'    # 수정한 파일이 있을 때 *
zstyle ':vcs_info:git:*' stagedstr '%F{green}+%f'      # git add된 파일이 있을 때 +

# 4. PROMPT 변수에 $vcs_info_msg_0_ 포함하기
setopt prompt_subst
PROMPT='%F{cyan}%n@%m%f:%F{blue}%1~%f ${vcs_info_msg_0_} %# '
EOF
    } >> "$HOME/.zshrc"
    info "~/.zshrc 에 프롬프트 설정 추가"
}

# ---------------------------------------------------------------- 6. ssh, git

# 터미널이 붙어 있는가. [ -r /dev/tty ] 는 제어 터미널이 없어도 참이므로 실제로 열어 본다.
has_tty() { ( : < /dev/tty ) 2>/dev/null; }
# 대화형 명령에 줄 stdin. curl | sh 로 실행 중이면 stdin 은 스크립트 본문이므로 터미널을 직접 쓴다.
tty_in() { if has_tty; then echo /dev/tty; else echo /dev/null; fi; }

# BASE_URL/keys.zip.enc 를 받아 복호화하고 id_* 파일을 ~/.ssh 에 넣는다.
# 암호는 KEYS_PASS 환경 변수가 있으면 그것을, 없으면 openssl 이 터미널에서 직접 묻는다.
# 실패하면 이 단계만 건너뛴다.
install_ssh_keys() {
    tmp=$(mktemp -d -t keys) || die "임시 디렉터리를 만들 수 없습니다"
    if ! curl -fsSL "$BASE_URL/keys.zip.enc" -o "$tmp/keys.zip.enc"; then
        warn "$BASE_URL/keys.zip.enc 를 받지 못했습니다. ssh 키는 건너뜁니다"
        rm -rf "$tmp"; return 0
    fi
    if [ -n "${KEYS_PASS:-}" ]; then
        openssl enc -d -aes-256-cbc -salt -pbkdf2 -pass env:KEYS_PASS \
            -in "$tmp/keys.zip.enc" -out "$tmp/keys.zip" 2>/dev/null
    elif has_tty; then
        printf '  keys.zip.enc 암호를 입력하세요\n'
        openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -in "$tmp/keys.zip.enc" -out "$tmp/keys.zip" < /dev/tty 2>/dev/null
    else
        warn "터미널이 없어 암호를 물을 수 없습니다 (KEYS_PASS 환경 변수로 줄 수 있음). ssh 키는 건너뜁니다"
        rm -rf "$tmp"; return 0
    fi || {
        warn "복호화에 실패했습니다 (암호가 틀림). ssh 키는 건너뜁니다"
        rm -rf "$tmp"; return 0
    }
    if ! (cd "$tmp" && unzip -oq keys.zip < "$(tty_in)"); then
        warn "keys.zip 을 풀지 못했습니다. ssh 키는 건너뜁니다"
        rm -rf "$tmp"; return 0
    fi
    # keys/ 안에 있든 최상위에 있든 id_* 만 옮긴다
    n=0
    for f in $(find "$tmp" -type f -name 'id_*'); do
        mv -f "$f" "$HOME/.ssh/" && n=$((n + 1))
    done
    rm -rf "$tmp"
    chmod 600 "$HOME"/.ssh/id_* 2>/dev/null
    chmod 644 "$HOME"/.ssh/id_*.pub 2>/dev/null
    if [ "$n" -gt 0 ]; then
        info "ssh 키 ${n}개 설치"
    else
        warn "keys.zip 안에 id_* 파일이 없습니다"
    fi
}

# github.com 호스트 키를 미리 넣는다. 받아 온 키의 지문을 GitHub 이 공개한 값과 대조하므로
# "묻지 않고 그냥 믿기"(StrictHostKeyChecking=no)와는 다르다. known_hosts 가 없으면 첫 접속에서
# 호스트 키 확인을 묻는데 비대화형 셸에서는 대답할 수 없어 푸시가 그냥 실패한다.
setup_known_hosts() {
    if ssh-keygen -F github.com >/dev/null 2>&1; then
        info "known_hosts 에 github.com 이미 있음"
    else
        hostkey=$(mktemp -t hostkey) || die "임시 파일을 만들 수 없습니다"
        ssh-keyscan -t ed25519 github.com > "$hostkey" 2>/dev/null
        fp=$(ssh-keygen -lf "$hostkey" 2>/dev/null | awk '{print $2}')
        if [ "$fp" = "$GITHUB_FP_ED25519" ]; then
            cat "$hostkey" >> "$HOME/.ssh/known_hosts"
            info "known_hosts 에 github.com 추가"
        else
            warn "github.com 호스트 키 지문이 공개된 값과 다릅니다 (${fp:-받지 못함}). 직접 확인하세요"
        fi
        rm -f "$hostkey"
    fi
    touch "$HOME/.ssh/known_hosts" && chmod 644 "$HOME/.ssh/known_hosts"
}

# ssh config. 키 이름이 기본값이 아니어도, 다른 키가 먼저 시도되어도 이 키를 쓴다.
setup_ssh_config() {
    if grep -q '^Host github\.com' "$HOME/.ssh/config" 2>/dev/null; then
        info "~/.ssh/config 에 github.com 이미 있음"
    else
        {
            echo "Host github.com"
            echo "  HostName github.com"
            echo "  User git"
            echo "  IdentityFile ~/.ssh/id_ed25519"
            echo "  IdentitiesOnly yes"
            echo "  AddKeysToAgent yes"
            echo "  UseKeychain yes"
        } >> "$HOME/.ssh/config"
        info "~/.ssh/config 에 github.com 항목 추가"
    fi
    chmod 600 "$HOME/.ssh/config"
}

setup_git() {
    git config --global user.email "$GIT_EMAIL"
    git config --global user.name "$GIT_NAME"
    git config --global init.defaultBranch main
    # 이미 받아 둔 저장소의 원격 주소가 https 여도 ssh 키로 푸시되게 한다. https 로 푸시하면
    # 사용자명과 토큰을 묻는데 비대화형 셸에서는 대답할 수 없어 실패한다.
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    info "git 사용자: $GIT_NAME <$GIT_EMAIL>, github https -> ssh"

    # ssh -T 는 성공해도 종료 코드가 1 이므로 출력으로 판단한다.
    if ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 | grep -q 'successfully authenticated'; then
        info "GitHub ssh 인증 확인"
    else
        warn "GitHub ssh 인증 실패. 공개키(~/.ssh/id_ed25519.pub)를 GitHub 계정에 등록했는지 확인하세요"
    fi
}

setup_ssh_and_git() {
    step "6. ssh 키, known_hosts, ssh config, git"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    install_ssh_keys
    setup_known_hosts
    setup_ssh_config
    setup_git
}

# ---------------------------------------------------------------- 7. Discord
#
# Discord 는 실행할 때마다 앱 본체 업데이트를 내려받는데, /Applications/Discord.app 이 관리자 소유라
# 설치하지 못하고 다음 실행에서 되풀이한다. 앱 코드(app.asar)가 settings.json 의 SKIP_HOST_UPDATE 를 읽어
# 본체 업데이트를 건너뛴다(0.0.411 에서 확인). 모듈 업데이트(SKIP_MODULE_UPDATE)는 사용자 폴더에 받아
# 문제가 없고 처음 한 번은 꼭 받아야 하므로 막지 않는다. Discord 는 종료할 때 settings.json 을 다시
# 쓰므로 실행 중이면 고치지 않는다. python 이 없을 수 있어 JSON 은 JXA 로 다룬다.

DISCORD_SETTINGS="$HOME/Library/Application Support/discord/settings.json"

# JSON 파일의 최상위 키 하나를 정한다. 파일이 없으면 만든다. 8절 VS Code 에서도 쓴다.
# 인자: <파일> <키> <값(JSON)>   출력: ok | already | invalid | error
SET_JSON_JS='
function run(argv) {
    ObjC.import("Foundation");
    var path = argv[0], key = argv[1], value = JSON.parse(argv[2]);
    var fm = $.NSFileManager.defaultManager, obj = {};
    if (fm.fileExistsAtPath(path)) {
        var text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, $());
        try { obj = JSON.parse(text.js); } catch (e) { return "invalid"; }
        if (!obj || typeof obj !== "object" || Array.isArray(obj)) return "invalid";
    }
    if (JSON.stringify(obj[key]) === JSON.stringify(value)) return "already";
    obj[key] = value;
    var dir = path.replace(/\/[^\/]*$/, "");
    fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), $());
    var ok = $(JSON.stringify(obj, null, 2) + "\n").writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, $());
    return ok ? "ok" : "error";
}'

# $1=파일 $2=키 $3=값(JSON). 결과를 출력하고 파일이 JSON 이 아니거나 쓰지 못하면 경고한다.
set_json_key() {
    case "$(jxa "$SET_JSON_JS" "$1" "$2" "$3")" in
        ok)      info "$(basename "$1") 에 $2 = $3 저장" ;;
        already) info "$2 = $3 이미 설정됨" ;;
        invalid) warn "$(basename "$1") 이 JSON 이 아닙니다 (주석이나 끝 쉼표가 있으면 안 됩니다). 직접 확인하세요: $1" ;;
        *)       warn "$(basename "$1") 을 쓰지 못했습니다: $1" ;;
    esac
}

setup_discord() {
    step "7. Discord 실행 시 본체 업데이트 건너뛰기"
    if pgrep -qx Discord; then
        warn "Discord 가 실행 중입니다. 종료한 뒤 이 스크립트를 다시 실행하면 설정합니다"
        return 0
    fi
    set_json_key "$DISCORD_SETTINGS" SKIP_HOST_UPDATE true
}

# ---------------------------------------------------------------- 8. VS Code
#
# VS Code 도 실행할 때마다 업데이트를 확인하는데 /Applications/Visual Studio Code.app 이 관리자 소유라
# 설치하지 못하고 알림만 되풀이한다. 사용자 settings.json 의 update.mode 를 none 으로 두면 확인 자체를
# 하지 않는다. VS Code 는 설정 파일을 사용자가 설정을 바꿀 때만 다시 쓰므로 실행 중이어도 고쳐도 된다.
# 다시 실행할 때부터 적용된다.

VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"

setup_vscode() {
    step "8. VS Code 업데이트 확인 끄기"
    set_json_key "$VSCODE_SETTINGS" update.mode '"none"'
}

# ---------------------------------------------------------------- 9. 터미널
#
# Terminal.app 프로파일은 com.apple.Terminal "Window Settings" 에 저장되지만 글꼴이 NSFont 아카이브라
# defaults 로는 못 고친다. Terminal 의 스크립팅 사전(settings set)으로 바꾸면 Terminal 이 저장까지 한다.
# 이 스크립트는 Terminal 안에서 실행되므로 자기 자신에게 보내는 이벤트라 자동화 권한 확인 창은 뜨지 않는다.
# 열려 있는 창은 그대로이고 새 창(⌘N)부터 적용된다. 마지막에 새 창을 하나 연다.

TERMINAL_PROFILE="Homebrew"
TERMINAL_FONT_SIZE=14
TERMINAL_COLUMNS=90
TERMINAL_ROWS=45

# 인자: 프로파일 글꼴크기 열 행   출력: <글꼴> <크기> <열> <행> <기본 프로파일>
TERMINAL_JS='
function run(argv) {
    var T = Application("Terminal");
    var s = T.settingsSets.byName(argv[0]);
    s.fontSize = parseInt(argv[1]);
    s.numberOfColumns = parseInt(argv[2]);
    s.numberOfRows = parseInt(argv[3]);
    T.defaultSettings = s;
    T.startupSettings = s;
    return [s.fontName(), s.fontSize(), s.numberOfColumns(), s.numberOfRows(), T.defaultSettings().name()].join(" ");
}'

setup_terminal() {
    step "9. 터미널: $TERMINAL_PROFILE 프로파일, 글꼴 $TERMINAL_FONT_SIZE, ${TERMINAL_COLUMNS}x${TERMINAL_ROWS}"
    r=$(osascript -l JavaScript -e "$TERMINAL_JS" "$TERMINAL_PROFILE"             "$TERMINAL_FONT_SIZE" "$TERMINAL_COLUMNS" "$TERMINAL_ROWS" 2>/dev/null)
    case "$r" in
        *" $TERMINAL_PROFILE") info "적용: $r"; terminal_ok=1 ;;
        *) warn "Terminal 설정을 바꾸지 못했습니다 (${r:-osascript 오류}). Terminal.app 에서 실행했는지 확인하세요"; terminal_ok=0 ;;
    esac
}

open_terminal_window() {
    [ "${terminal_ok:-0}" -eq 1 ] || return 0
    osascript -l JavaScript -e 'Application("Terminal").doScript("")' >/dev/null 2>&1 \
        && info "새 터미널 창을 열었습니다"
}

# ---------------------------------------------------------------- 10. Claude Code

setup_claude_code() {
    step "10. Claude Code"
    if curl -fsSL https://claude.ai/install.sh | bash; then
        info "Claude Code 설치"
    else
        warn "Claude Code 설치에 실패했습니다. 나중에 다시 실행하세요: curl -fsSL https://claude.ai/install.sh | bash"
    fi
    grep -qF '.local/bin' "$HOME/.zshrc" 2>/dev/null \
        || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
}

# ---------------------------------------------------------------- 11. 앱 실행
#
# 설정이 끝난 뒤 자주 쓰는 앱을 연다. -g 로 앞에 나오지 않게 열고 마지막에 여는 터미널 창이 앞에 온다.
# Chrome 은 이미 떠 있으면 --args 가 무시되므로 -n 으로 새 인스턴스에 넘긴다. 새 인스턴스는 실행 중인
# Chrome 에 인자를 전달하고 끝나므로 결과는 "실행 중인 Chrome 에 새 창"이다. 앱이 없으면 경고만 한다.

CHROME_URL="https://codyssey.kr"

# $1=앱 이름, 나머지=open 에 줄 추가 인자
launch_app() {
    name="$1"; shift
    if open -ga "$name" "$@" 2>/dev/null; then
        info "$name 실행"
    else
        warn "$name 을(를) 열지 못했습니다. 설치되어 있는지 확인하세요"
    fi
}

launch_apps() {
    step "11. 앱 실행: Discord, VS Code, Chrome"
    launch_app Discord
    launch_app "Visual Studio Code"
    if open -gna "Google Chrome" --args --new-window "$CHROME_URL" 2>/dev/null; then
        info "Google Chrome 새 창: $CHROME_URL"
    else
        warn "Google Chrome 을 열지 못했습니다. 설치되어 있는지 확인하세요"
    fi
}

# ---------------------------------------------------------------- main

main() {
    [ "$(uname -s)" = "Darwin" ] || die "이 스크립트는 macOS 전용입니다."
    uid=$(id -u)

    app=$(find_gureum) || die "구름 입력기(Gureum.app)가 설치되어 있지 않습니다.
관리자 설치가 어렵다면 관리자 권한 없이 사용자 영역에만 설치할 수 있습니다:
  mkdir -p ~/Library/Input\\ Methods
  # Gureum.app 을 ~/Library/Input Methods/ 로 복사한 뒤 로그아웃/로그인"

    wait_for_login_init
    setup_fn_key
    setup_capslock
    setup_input_sources "$app"
    setup_hot_corners
    setup_zsh
    setup_ssh_and_git
    setup_discord
    setup_vscode
    setup_terminal
    setup_claude_code
    launch_apps

    printf '\n\033[1m완료.\033[0m 키보드·핫 코너·Discord·VS Code·터미널 설정은 지금 적용되었고 재로그인 후에도 유지됩니다.\n'
    printf 'Caps Lock 으로 ABC 와 구름 세벌식 최종 사이를 전환해 보세요. 로그인할 때마다 다시 실행하세요.\n'
    printf '새 터미널 창에서 프롬프트·PATH·%s 프로파일이 적용됩니다.\n\n\tclaude --dangerously-skip-permissions\n\n' "$TERMINAL_PROFILE"
    open_terminal_window
}

main "$@"
