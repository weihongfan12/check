#!/usr/bin/env bash
set -u

SITE="${SITE_URL2:-https://api.denxio.top}"
USERNAME="${CHECKIN_USERNAME2:-}"
PASSWORD="${CHECKIN_PASSWORD2:-}"
COOKIE_FILE="${RUNNER_TEMP:-$HOME}/checkin2_cookies.txt"
SITE_LABEL="站点2(api.denxio.top)"

log() {
    echo "[$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S CST')] [$SITE_LABEL] $*"
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

curl_retry() {
    local attempt=1
    local max=3
    local resp=""
    while [ "$attempt" -le "$max" ]; do
        resp=$(curl -sS -L --connect-timeout 20 --max-time 60 "$@" 2>&1)
        local code=$?
        if [ "$code" -eq 0 ]; then
            printf '%s' "$resp"
            return 0
        fi
        log "curl 第 ${attempt}/${max} 次失败: $resp"
        attempt=$((attempt + 1))
        sleep 5
    done
    printf '%s' "$resp"
    return 1
}

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "❌ [$SITE_LABEL] 缺少 CHECKIN_USERNAME2 或 CHECKIN_PASSWORD2"
    exit 1
fi

rm -f "$COOKIE_FILE"
log "=== 开始签到流程 ==="
log "站点: $SITE"
log "北京时间日期: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')"

# Step 1: 登录 (POST /api/v1/auth/login)
LOGIN_BODY=$(python3 -c "import json; print(json.dumps({'email': '$USERNAME', 'password': '$PASSWORD'}, ensure_ascii=False))")
LOGIN_RESP=$(curl_retry -c "$COOKIE_FILE" \
    -X POST "$SITE/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$LOGIN_BODY")

log "登录响应: $(echo "$LOGIN_RESP" | head -c 200)"

TOKEN=$(echo "$LOGIN_RESP" | json_get 'data.token' 2>/dev/null || true)
USER_ID=$(echo "$LOGIN_RESP" | json_get 'data.id' 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
    # 尝试其他可能的 token 字段名
    TOKEN=$(echo "$LOGIN_RESP" | json_get 'data.access_token' 2>/dev/null || true)
fi

if [ -z "$TOKEN" ]; then
    echo "❌ [$SITE_LABEL] 登录失败，未获取到 token: $LOGIN_RESP"
    exit 1
fi

log "✅ 登录成功, 用户ID: $USER_ID"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# Step 2: 检查签到状态 (GET /api/v1/tbe-sponsor-checkin/status)
STATUS_RESP=$(curl_retry \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" \
    "$SITE/api/v1/tbe-sponsor-checkin/status?timezone=Asia/Shanghai")

log "签到状态: $(echo "$STATUS_RESP" | head -c 300)"

# 检查是否今日已签到
CHECKED=$(echo "$STATUS_RESP" | json_get 'data.checked_in_today' 2>/dev/null || echo "false")
if [ "$CHECKED" = "true" ]; then
    echo "📅 [$SITE_LABEL] 今日已经签到，跳过"
    log "=== 签到流程结束 ==="
    exit 0
fi

# Step 3: 开始签到 (POST /api/v1/tbe-sponsor-checkin/normal/begin)
BEGIN_RESP=$(curl_retry \
    -X POST "$SITE/api/v1/tbe-sponsor-checkin/normal/begin" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" \
    -d '{"timezone":"Asia/Shanghai"}')

log "begin 响应: $(echo "$BEGIN_RESP" | head -c 300)"

CLAIM_TOKEN=$(echo "$BEGIN_RESP" | json_get 'data.token' 2>/dev/null || true)

if [ -z "$CLAIM_TOKEN" ]; then
    # 检查是否已签到
    MSG=$(echo "$BEGIN_RESP" | json_get 'message' 2>/dev/null || echo "")
    if echo "$MSG" | grep -qi 'already\|已签\|签到过'; then
        echo "📅 [$SITE_LABEL] 今日已经签到 (begin 返回已签到)"
        log "=== 签到流程结束 ==="
        exit 0
    fi
    echo "❌ [$SITE_LABEL] begin 失败，未获取到 claim token: $BEGIN_RESP"
    exit 1
fi

log "获取到 claim token: ${CLAIM_TOKEN:0:20}..."

# Step 3.5: 等待 wait_seconds (begin 返回的倒计时)
WAIT_SECONDS=$(echo "$BEGIN_RESP" | python3 -c '
import json, sys
from datetime import datetime, timezone
try:
    data = json.load(sys.stdin).get("data") or {}
    ws = data.get("wait_seconds")
    if ws is not None and ws > 0:
        print(int(ws))
        sys.exit(0)
    avail = data.get("available_at")
    if avail:
        dt = datetime.fromisoformat(avail.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = int((dt - now).total_seconds())
        print(max(0, diff))
        sys.exit(0)
    print(0)
except Exception:
    print(0)
' 2>/dev/null || echo "0")

if [ "$WAIT_SECONDS" -gt 0 ] 2>/dev/null; then
    # 最多等 120 秒，防止异常值
    if [ "$WAIT_SECONDS" -gt 120 ]; then
        log "等待时间过长 ($WAIT_SECONDS 秒)，跳过"
        WAIT_SECONDS=10
    fi
    log "需要等待 $WAIT_SECONDS 秒后才能 claim..."
    sleep "$WAIT_SECONDS"
fi

# Step 4: 领取签到奖励 (POST /api/v1/tbe-sponsor-checkin/normal/claim)
CLAIM_RESP=$(curl_retry \
    -X POST "$SITE/api/v1/tbe-sponsor-checkin/normal/claim" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" \
    -d "{\"token\":\"$CLAIM_TOKEN\",\"timezone\":\"Asia/Shanghai\"}")

log "claim 响应: $(echo "$CLAIM_RESP" | head -c 300)"

CLAIM_SUCCESS=$(echo "$CLAIM_RESP" | json_get 'success' 2>/dev/null || echo "")
CLAIM_CODE=$(echo "$CLAIM_RESP" | json_get 'code' 2>/dev/null || echo "")
if [ "$CLAIM_SUCCESS" = "true" ] || [ "$CLAIM_CODE" = "0" ]; then
    AMOUNT=$(echo "$CLAIM_RESP" | json_get 'data.record.amount' 2>/dev/null || echo "?")
    BALANCE=$(echo "$CLAIM_RESP" | json_get 'data.new_balance' 2>/dev/null || echo "?")
    echo "🎉 [$SITE_LABEL] 签到成功！获得 ${AMOUNT} token，余额 ${BALANCE}"
    log "=== 签到流程结束 ==="
    exit 0
fi

# 再次检查状态确认
STATUS_AFTER=$(curl_retry \
    -H "Accept: application/json" \
    -H "$AUTH_HEADER" \
    "$SITE/api/v1/tbe-sponsor-checkin/status?timezone=Asia/Shanghai")

CHECKED_AFTER=$(echo "$STATUS_AFTER" | json_get 'data.checked_in_today' 2>/dev/null || echo "false")
if [ "$CHECKED_AFTER" = "true" ]; then
    echo "🎉 [$SITE_LABEL] 签到成功（通过状态接口确认）"
    log "=== 签到流程结束 ==="
    exit 0
fi

echo "❌ [$SITE_LABEL] 签到失败：claim 响应未能确认签到成功"
echo "❌ claim 响应: $CLAIM_RESP"
rm -f "$COOKIE_FILE"
exit 1
