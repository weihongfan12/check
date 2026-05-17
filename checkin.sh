#!/bin/bash

SITE="${SITE_URL:-https://ai.xem8k5.top}"
USERNAME="${CHECKIN_USERNAME}"
PASSWORD="${CHECKIN_PASSWORD}"
COOKIE_FILE="/tmp/checkin_cookies.txt"

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "❌ 缺少 CHECKIN_USERNAME 或 CHECKIN_PASSWORD"
    exit 1
fi

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] === 开始签到流程 ==="

LOGIN_RESP=$(curl -sL -c "$COOKIE_FILE" \
    -X POST "$SITE/api/user/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" 2>&1)

SUCCESS=$(echo "$LOGIN_RESP" | grep -o '"success":true')
USER_ID=$(echo "$LOGIN_RESP" | grep -oP '"id":\K[0-9]+')

if [ -z "$SUCCESS" ]; then
    echo "❌ 登录失败: $LOGIN_RESP"
    exit 1
fi

if [ -z "$USER_ID" ]; then
    echo "❌ 登录成功但未获取到用户ID: $LOGIN_RESP"
    exit 1
fi

if [ ! -s "$COOKIE_FILE" ]; then
    echo "❌ 登录成功但未写入会话 Cookie"
    exit 1
fi

echo "✅ 登录成功, 用户ID: $USER_ID"

CHECKIN_RESP=$(curl -sL -b "$COOKIE_FILE" \
    -X POST "$SITE/api/user/checkin" \
    -H "Content-Type: application/json" \
    -H "New-Api-User: $USER_ID" 2>&1)

echo "签到响应: $CHECKIN_RESP"

TODAY=$(date +%F)
MONTH=$(date +%Y-%m)
STATUS_RESP=$(curl -sL -b "$COOKIE_FILE" \
    -X GET "$SITE/api/user/checkin?month=$MONTH" \
    -H "New-Api-User: $USER_ID" 2>&1)

if echo "$CHECKIN_RESP" | grep -q '"success":true' && echo "$STATUS_RESP" | grep -q "\"checkin_date\":\"$TODAY\""; then
    echo "🎉 签到成功！"
elif echo "$CHECKIN_RESP" | grep -q '今日已签到'; then
    echo "📅 今日已签到过"
else
    echo "❌ 签到异常: $CHECKIN_RESP"
    echo "❌ 状态校验: $STATUS_RESP"
    exit 1
fi

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] === 签到流程结束 ==="

rm -f "$COOKIE_FILE"
