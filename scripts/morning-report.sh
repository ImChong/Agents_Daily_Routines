#!/bin/bash

# 早安报告脚本 - 获取系统状态并发送飞书消息
# 使用前请先填写下面这些配置，建议通过环境变量或本机私有配置文件注入，别把真实 secret 提交到仓库。

LOG_FILE="/path/to/morning-report.log"
FEISHU_USER="YOUR_FEISHU_OPEN_ID"                 # 例如: ou_xxx
FEISHU_APP_ID="YOUR_FEISHU_APP_ID"                # 例如: cli_xxx
FEISHU_APP_SECRET="YOUR_FEISHU_APP_SECRET"        # 例如: xxxx
PROXY="http://127.0.0.1:7890"                     # 如不需要代理可改为空

echo "========== $(date '+%Y-%m-%d %H:%M:%S') 早安报告 ==========" >> "$LOG_FILE"

# 获取飞书 access token
get_feishu_token() {
    local curl_args=(-s -X POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal
      -H "Content-Type: application/json"
      -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}")
    if [ -n "$PROXY" ]; then
        curl_args=(-x "$PROXY" "${curl_args[@]}")
    fi
    curl "${curl_args[@]}" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tenant_access_token',''))" 2>/dev/null
}

# 发送飞书 interactive card 消息 (markdown 格式)
send_feishu_card() {
    local token="$1"
    local payload="$2"
    local curl_args=(-s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id"
      -H "Authorization: Bearer $token"
      -H "Content-Type: application/json"
      -d "$payload")
    if [ -n "$PROXY" ]; then
        curl_args=(-x "$PROXY" "${curl_args[@]}")
    fi
    curl "${curl_args[@]}" >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"
}

# 1. 获取系统状态
echo "获取系统状态..." >> "$LOG_FILE"

# 电量 + 健康（自动找真实电池设备，跳过 DisplayDevice）
BAT_PATH=$(upower -e | grep battery | while read p; do
    state=$(upower -i "$p" 2>/dev/null | grep "power supply" | awk '{print $3}')
    [ "$state" = "yes" ] && echo "$p" && break
done)
BATTERY_PCT=$(upower -i "$BAT_PATH" 2>/dev/null | grep "percentage" | awk '{print $2}')
BATTERY_HEALTH_VAL=$(upower -i "$BAT_PATH" 2>/dev/null | grep "capacity:" | awk '{print $2}')

# CPU温度
CPU_TEMP=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' || echo "N/A")

# 内存
MEMORY_USED=$(free -h 2>/dev/null | grep Mem | awk '{print $3}')
MEMORY_TOTAL=$(free -h 2>/dev/null | grep Mem | awk '{print $2}')

# 硬盘
DISK_INFO=$(df -h / 2>/dev/null | tail -1)
DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
DISK_FREE=$(echo "$DISK_INFO" | awk '{print $4}')
DISK_PCT=$(echo "$DISK_INFO" | awk '{print $5}')

# GPU（检测驱动是否正常）
if nvidia-smi --query-gpu=name --format=csv,noheader &>/dev/null; then
    GPU_DISPLAY=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null | head -1)
else
    GPU_DISPLAY="驱动异常，nvidia-smi 不可用"
fi
[ -z "$GPU_DISPLAY" ] && GPU_DISPLAY="N/A"

echo "采集完成" >> "$LOG_FILE"

# 2. 构建 interactive card 消息
BATTERY_LINE="${BATTERY_PCT:-N/A}"
[ -n "$BATTERY_HEALTH_VAL" ] && BATTERY_LINE="$BATTERY_LINE，健康度 $BATTERY_HEALTH_VAL"

CARD_JSON=$(BATTERY_LINE="$BATTERY_LINE" CPU_TEMP="$CPU_TEMP" MEMORY_USED="$MEMORY_USED" \
  MEMORY_TOTAL="$MEMORY_TOTAL" DISK_PCT="$DISK_PCT" DISK_USED="$DISK_USED" \
  DISK_TOTAL="$DISK_TOTAL" DISK_FREE="$DISK_FREE" GPU_DISPLAY="$GPU_DISPLAY" \
  FEISHU_USER="$FEISHU_USER" python3 <<'PYEOF'
import json, os

battery = os.environ.get("BATTERY_LINE", "N/A")
cpu_temp = os.environ.get("CPU_TEMP", "N/A")
mem_used = os.environ.get("MEMORY_USED", "N/A")
mem_total = os.environ.get("MEMORY_TOTAL", "N/A")
disk_pct = os.environ.get("DISK_PCT", "N/A")
disk_used = os.environ.get("DISK_USED", "N/A")
disk_total = os.environ.get("DISK_TOTAL", "N/A")
disk_free = os.environ.get("DISK_FREE", "N/A")
gpu = os.environ.get("GPU_DISPLAY", "N/A")

lines = [
    "- 🔋 电池：" + battery,
    "- 🌡 CPU温度：" + cpu_temp,
    "- 💾 内存：" + mem_used + " / " + mem_total,
    "- 💿 硬盘：" + disk_pct + " 已用 " + disk_used + "/" + disk_total + "，剩余 " + disk_free,
    "- 🖥 GPU：" + gpu,
]

md_content = "\n".join(lines)

card = {
    "header": {
        "title": {
            "tag": "plain_text",
            "content": "🌅 早安！系统状态报告"
        }
    },
    "elements": [
        {
            "tag": "markdown",
            "content": md_content
        }
    ]
}

final = {
    "receive_id": os.environ.get("FEISHU_USER", ""),
    "msg_type": "interactive",
    "content": json.dumps(card, ensure_ascii=False)
}
print(json.dumps(final))
PYEOF
)

# 3. 发送
echo "发送飞书消息..." >> "$LOG_FILE"
FEISHU_TOKEN=$(get_feishu_token)
if [ -z "$FEISHU_TOKEN" ]; then
    echo "获取飞书 token 失败！" >> "$LOG_FILE"
else
    send_feishu_card "$FEISHU_TOKEN" "$CARD_JSON"
    echo "发送完成" >> "$LOG_FILE"
fi

echo "完成!" >> "$LOG_FILE"
echo "================================================" >> "$LOG_FILE"
