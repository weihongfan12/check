#!/bin/bash
# ============================================
# ai.xem8k5.top 自动签到脚本 (GitHub Actions)
# 凭据从环境变量读取，不硬编码密码
# ============================================

SITE="${SITE_URL:-https://ai.xem8k5.top}"
USERNAME="${CHECKIN_USERNAME}"
PASSWORD="${CHECKIN_PASSWORD}"
COOKIE_FILE="/tmp/checkin_cookies.txt"

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] === 开始签到流程 ==="

# Step 1: 登录获取 session
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

echo "✅ 登录成功, 用户ID: $USER_ID"

# Step 2: 签到
CHECKIN_RESP=$(curl -sL -b "$COOKIE_FILE" \
    -X POST "$SITE/api/user/checkin" \
    -H "Content-Type: application/json" \
    -H "New-Api-User: $USER_ID" 2>&1)

echo "签到响应: $CHECKIN_RESP"

# Step 3: 检查结果
if echo "$CHECKIN_RESP" | grep -q '"success":true'; then
    echo "🎉 签到成功！"
elif echo "$CHECKIN_RESP" | grep -q '今日已签到'; then
    echo "📅 今日已签到过"
else
    echo "⚠️ 签到异常: $CHECKIN_RESP"
    exit 1
fi

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] === 签到流程结束 ==="

# 清理
rm -f "$COOKIE_FILE"
