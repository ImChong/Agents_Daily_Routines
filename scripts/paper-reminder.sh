#!/bin/bash

# 每日论文提醒脚本 - 每天 7:00 AM 触发
# 使用前请先填写下面这些配置，建议通过环境变量或本机私有配置文件注入，别把真实 secret 提交到仓库。

PROGRESS_FILE="/path/to/progress.json"
FEISHU_USER="YOUR_FEISHU_OPEN_ID"                 # 例如: ou_xxx
FEISHU_APP_ID="YOUR_FEISHU_APP_ID"                # 例如: cli_xxx
FEISHU_APP_SECRET="YOUR_FEISHU_APP_SECRET"        # 例如: xxxx
PROXY="http://127.0.0.1:7890"                     # 如不需要代理可改为空
LOG_FILE="/path/to/paper-reminder.log"
PAPER_BASE="/path/to/Humanoid_Robot_Learning_Paper_Notebooks"
SITE_URL="https://your-site.example.com"

echo "========== $(date '+%Y-%m-%d %H:%M:%S') 论文提醒 ==========" >> "$LOG_FILE"

# 获取飞书 token
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

# 发送飞书 interactive card 消息 (支持 markdown bullet point 和超链接)
send_feishu_card() {
    local token="$1"
    local card_json="$2"
    local payload
    payload=$(python3 -c "
import json, sys
card = sys.argv[1]
payload = {
    'receive_id': '$FEISHU_USER',
    'msg_type': 'interactive',
    'content': card
}
print(json.dumps(payload))
" "$card_json")

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

# 根据论文标题查找笔记的 GitHub Pages URL
get_note_url() {
    python3 - "$PAPER_BASE" "$SITE_URL" "$PROGRESS_FILE" <<'PYEOF'
import json, sys, os, glob

paper_base = sys.argv[1]
site_url = sys.argv[2]
progress_file = sys.argv[3]

with open(progress_file) as f:
    d = json.load(f)

paper = d['papers'][d['current_paper_index']]
note_file = paper['note_file']

candidates = [note_file, note_file.replace('__', '_')]
md_files = glob.glob(os.path.join(paper_base, "papers/**/*.md"), recursive=True)

for md in md_files:
    fname = os.path.basename(md)
    if fname in candidates:
        rel = os.path.relpath(md, paper_base).replace('.md', '.html')
        print(f"{site_url}/{rel}")
        sys.exit(0)

stem = note_file.replace('.md', '').replace('__', '_')
for md in md_files:
    if stem in md:
        rel = os.path.relpath(md, paper_base).replace('.md', '.html')
        print(f"{site_url}/{rel}")
        sys.exit(0)

print("")
PYEOF
}

# 读取当前论文状态
CONFIRMED=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); print(d['confirmed'])" 2>/dev/null)
TITLE=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p['title'])" 2>/dev/null)
TITLE_CN=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p.get('title_cn',''))" 2>/dev/null)
ARXIV=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p['arxiv'])" 2>/dev/null)
NOTE_URL=$(get_note_url)

echo "当前论文: $TITLE | confirmed=$CONFIRMED" >> "$LOG_FILE"

if [ "$CONFIRMED" = "True" ]; then
    python3 - <<'EOF' "$PROGRESS_FILE"
import json, sys
from datetime import datetime

path = sys.argv[1]
with open(path) as f:
    d = json.load(f)

idx = d['current_paper_index']
today = datetime.now().strftime('%Y-%m-%d')

d['papers'][idx]['status'] = 'done'
d['papers'][idx]['done_date'] = today

next_idx = None
for i, p in enumerate(d['papers']):
    if p['status'] == 'pending':
        next_idx = i
        break

if next_idx is not None:
    d['papers'][next_idx]['status'] = 'reading'
    d['papers'][next_idx]['start_date'] = today
    d['current_paper_index'] = next_idx
    d['confirmed'] = False

with open(path, 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
EOF

    TITLE=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p['title'])" 2>/dev/null)
    TITLE_CN=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p.get('title_cn',''))" 2>/dev/null)
    ARXIV=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); p=d['papers'][d['current_paper_index']]; print(p['arxiv'])" 2>/dev/null)
    NOTE_URL=$(get_note_url)

    echo "推送新论文: $TITLE" >> "$LOG_FILE"
    HEADER="📚 今日新论文！"
    FOOTER="读完后回复「理解了」，我会记录要点并推送下一篇 💪"
else
    echo "提醒继续: $TITLE" >> "$LOG_FILE"
    HEADER="📚 今日论文提醒"
    FOOTER="读完后回复「理解了」～"
fi

CARD_JSON=$(python3 - "$HEADER" "$TITLE" "$TITLE_CN" "$NOTE_URL" "$ARXIV" "$FOOTER" <<'PYEOF'
import json, sys

header, title, title_cn, note_url, arxiv, footer = sys.argv[1:7]
lines = []

title_text = title
if title_cn:
    title_text = title + "（" + title_cn + "）"
lines.append("- " + title_text)

if note_url:
    lines.append("- 📖 笔记：[" + title + "](" + note_url + ")")

if arxiv:
    lines.append("- 🔗 论文：[" + title + "](" + arxiv + ")")

lines.append("")
lines.append(footer)

md_content = "\n".join(lines)

card = {
    "header": {
        "title": {
            "tag": "plain_text",
            "content": header
        }
    },
    "elements": [
        {
            "tag": "markdown",
            "content": md_content
        }
    ]
}

print(json.dumps(card, ensure_ascii=False))
PYEOF
)

FEISHU_TOKEN=$(get_feishu_token)
if [ -z "$FEISHU_TOKEN" ]; then
    echo "获取飞书 token 失败！" >> "$LOG_FILE"
else
    send_feishu_card "$FEISHU_TOKEN" "$CARD_JSON"
    echo "发送完成" >> "$LOG_FILE"
fi
