#!/usr/bin/env bash
set -u

SITE="${SITE_URL2:-https://api.denxio.top}"
USERNAME="${CHECKIN_USERNAME2:-}"
PASSWORD="${CHECKIN_PASSWORD2:-}"
COOKIE_FILE="${RUNNER_TEMP:-/tmp}/checkin2_cookies.txt"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"
}

json_get() {
    python3 -c 'import json,sys
path=sys.argv[1]
try:
    data=json.load(sys.stdin)
    cur=data
    for p in path.split("."):
        if p == "":
            continue
        if isinstance(cur, dict):
            cur=cur.get(p)
        else:
            cur=None
            break
    if cur is None:
        sys.exit(1)
    if isinstance(cur, bool):
        print(str(cur).lower())
    else:
        print(cur)
except Exception:
    sys.exit(1)' "$1"
}

check_status() {
    local month="$1"
    curl -sS -L -b "$COOKIE_FILE" \
        -H "Accept: application/json" \
        -H "New-API-User: $USER_ID" \
        ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        "$SITE/api/user/checkin?month=$month" 2>&1
}

verify_checked_today() {
    local status_resp="$1"
    local today_cst
    today_cst=$(TZ=Asia/Shanghai date +%F)

    STATUS_RESP="$status_resp" python3 - "$today_cst" <<'PY'
import json, os, sys

today = sys.argv[1]
text = os.environ.get("STATUS_RESP", "")
try:
    obj = json.loads(text)
except Exception:
    print("invalid_json")
    sys.exit(2)

if not obj.get("success"):
    print("status_api_failed")
    sys.exit(3)

data = obj.get("data") or {}
stats = data.get("stats") or {}
records = stats.get("records") or []
checked = bool(stats.get("checked_in_today"))
has_record = any((r or {}).get("checkin_date") == today for r in records)

if checked or has_record:
    print("checked")
    sys.exit(0)

print("not_checked")
sys.exit(1)
PY
}

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "❌ [Site2] 缺少 CHECKIN_USERNAME2 或 CHECKIN_PASSWORD2"
    exit 1
fi

rm -f "$COOKIE_FILE"
log "=== [Site2] 开始签到流程 ==="
log "站点: $SITE"
log "北京时间日期: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')"

LOGIN_RESP=$(curl -sS -L -c "$COOKIE_FILE" \
    -X POST "$SITE/api/user/login" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" 2>&1)

SUCCESS=$(echo "$LOGIN_RESP" | json_get 'success' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | json_get 'data.id' 2>/dev/null || true)
TOKEN=$(echo "$LOGIN_RESP" | json_get 'data.token' 2>/dev/null || true)

if [ "$SUCCESS" != "true" ]; then
    echo "❌ [Site2] 登录失败: $LOGIN_RESP"
    exit 1
fi

if [ -z "$USER_ID" ]; then
    echo "❌ [Site2] 登录成功但未获取到用户ID: $LOGIN_RESP"
    exit 1
fi

AUTH_HEADER=""
if [ -n "$TOKEN" ]; then
    AUTH_HEADER="Authorization: Bearer $TOKEN"
fi

echo "✅ [Site2] 登录成功, 用户ID: $USER_ID"
if [ -n "$TOKEN" ]; then
    echo "✅ [Site2] 已获取 token，将同时使用 Authorization + Cookie + New-API-User"
else
    echo "ℹ️ [Site2] 登录响应没有 token，将使用 Cookie + New-API-User"
fi

MONTH=$(TZ=Asia/Shanghai date +%Y-%m)
STATUS_BEFORE=$(check_status "$MONTH")
echo "[Site2] 签到前状态: $STATUS_BEFORE"

VERIFY_BEFORE=$(verify_checked_today "$STATUS_BEFORE" || true)
if [ "$VERIFY_BEFORE" = "checked" ]; then
    echo "📅 [Site2] 状态接口确认：今日已经签到"
    log "=== [Site2] 签到流程结束 ==="
    rm -f "$COOKIE_FILE"
    exit 0
fi

CHECKIN_RESP=$(curl -sS -L -b "$COOKIE_FILE" \
    -X POST "$SITE/api/user/checkin" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "New-API-User: $USER_ID" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} 2>&1)

echo "[Site2] 签到响应: $CHECKIN_RESP"

STATUS_AFTER=$(check_status "$MONTH")
echo "[Site2] 签到后状态: $STATUS_AFTER"

VERIFY_AFTER=$(verify_checked_today "$STATUS_AFTER" || true)
if [ "$VERIFY_AFTER" = "checked" ]; then
    if echo "$CHECKIN_RESP" | grep -q '"success":true'; then
        echo "🎉 [Site2] 签到成功，并已通过状态接口确认"
    else
        echo "📅 [Site2] 今日已签到，并已通过状态接口确认"
    fi
    log "=== [Site2] 签到流程结束 ==="
    rm -f "$COOKIE_FILE"
    exit 0
fi

if echo "$CHECKIN_RESP" | grep -qi 'Turnstile'; then
    echo "❌ [Site2] 签到失败：站点要求 Turnstile，人机验证无法用纯 GitHub Actions curl 绕过"
else
    echo "❌ [Site2] 签到失败：接口响应未能让状态变为今日已签到"
fi

echo "❌ [Site2] 状态校验结果: $VERIFY_AFTER"
rm -f "$COOKIE_FILE"
exit 1
