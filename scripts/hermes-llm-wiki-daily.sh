#!/bin/bash
# Hermes LLM Wiki 每日自检脚本
# 每天早上7点运行，检查 Robotics_Notebooks wiki 健康状态
# 使用环境变量配置文件：~/.hermes-daily-config.env

set -euo pipefail

# 配置加载
CONFIG_FILE="${HOME}/.hermes-daily-config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "警告：未找到配置文件 $CONFIG_FILE"
    echo "请创建配置文件并设置以下环境变量："
    echo "  FEISHU_HOME_CHANNEL - 飞书主频道ID"
    echo "  ROBOTICS_NOTEBOOKS_PATH - Robotics_Notebooks 仓库路径"
    exit 1
fi

# 必需的环境变量检查
: "${FEISHU_HOME_CHANNEL:?FEISHU_HOME_CHANNEL 未设置}"
: "${ROBOTICS_NOTEBOOKS_PATH:?ROBOTICS_NOTEBOOKS_PATH 未设置}"

# 日志文件
LOG_DIR="${HOME}/.hermes/cron/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/llm-wiki-daily-$(date +%Y%m%d).log"

# 开始日志
{
    echo "=== Hermes LLM Wiki 每日自检 $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "配置来源: $CONFIG_FILE"
    echo "目标仓库: $ROBOTICS_NOTEBOOKS_PATH"
    
    # 检查仓库是否存在
    if [[ ! -d "$ROBOTICS_NOTEBOOKS_PATH" ]]; then
        echo "错误：仓库路径不存在: $ROBOTICS_NOTEBOOKS_PATH"
        exit 1
    fi
    
    cd "$ROBOTICS_NOTEBOOKS_PATH"
    
    # 1. 运行健康检查脚本
    echo "1. 运行 wiki 健康检查..."
    if [[ -f "scripts/lint_wiki.py" ]]; then
        python3 scripts/lint_wiki.py 2>&1 || echo "警告：lint_wiki.py 执行有误"
    else
        echo "警告：未找到 lint_wiki.py 脚本"
    fi
    
    # 2. 检查 log.md 中的积压任务
    echo "2. 检查积压任务..."
    if [[ -f "log.md" ]]; then
        BACKLOG_COUNT=$(grep -c "计划但未执行" log.md || true)
        echo "积压任务数量: $BACKLOG_COUNT"
        
        if [[ $BACKLOG_COUNT -gt 0 ]]; then
            echo "警告：发现 $BACKLOG_COUNT 个积压任务"
            BACKLOG_ITEMS=$(grep -A2 "计划但未执行" log.md | head -20)
            echo "积压任务预览："
            echo "$BACKLOG_ITEMS"
        fi
    else
        echo "警告：未找到 log.md 文件"
    fi
    
    # 3. 运行页面目录生成
    echo "3. 生成页面目录..."
    if [[ -f "scripts/generate_page_catalog.py" ]]; then
        python3 scripts/generate_page_catalog.py 2>&1 || echo "警告：generate_page_catalog.py 执行有误"
    else
        echo "警告：未找到 generate_page_catalog.py 脚本"
    fi
    
    # 4. 检查 Git 状态
    echo "4. 检查 Git 状态..."
    git status --short 2>&1 || echo "警告：Git 状态检查失败"
    
    # 5. 生成报告
    echo "5. 生成报告..."
    REPORT="Robotics_Notebooks Wiki 健康检查报告 $(date '+%Y-%m-%d')
    
状态总结：
- 仓库路径：$ROBOTICS_NOTEBOOKS_PATH
- 检查时间：$(date '+%Y-%m-%d %H:%M:%S')
- 积压任务：$BACKLOG_COUNT 个"

    # 如果有积压任务，添加到报告
    if [[ $BACKLOG_COUNT -gt 0 ]]; then
        REPORT+="
⚠️ 注意：发现 $BACKLOG_COUNT 个积压任务需要处理"
    fi
    
    REPORT+="

详细日志已保存至：$LOG_FILE"

    echo "报告生成完成"
    
    # 6. 发送到飞书（通过 Hermes）
    echo "6. 发送报告到飞书..."
    hermes send_message --target "feishu:$FEISHU_HOME_CHANNEL" --message "$REPORT" 2>&1 || {
        echo "警告：发送到飞书失败"
        echo "报告内容："
        echo "$REPORT"
    }
    
    echo "=== 检查完成 ==="
    
} | tee -a "$LOG_FILE"

echo "日志已保存至: $LOG_FILE"