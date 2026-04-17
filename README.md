# Agents Daily Routines

每日定时任务脚本集合，用于自动化日常工作和提醒。

## 已包含的脚本

### 1. morning-report.sh
- **功能**：生成每日晨报
- **运行时间**：每天早上7:00
- **依赖**：需要配置相关环境变量

### 2. paper-reminder.sh
- **功能**：论文阅读提醒
- **运行时间**：每天早上7:00
- **依赖**：需要配置相关环境变量

### 3. hermes-llm-wiki-daily.sh
- **功能**：Robotics_Notebooks Wiki 每日健康检查
- **运行时间**：每天早上7:00
- **依赖**：需要配置 `~/.hermes-daily-config.env` 文件

## 配置说明

### 通用配置
所有脚本都使用环境变量进行配置，避免在脚本中硬编码敏感信息。

### Hermes LLM Wiki 检查专用配置
1. 复制示例配置文件：
   ```bash
   cp scripts/hermes-daily-config.example.env ~/.hermes-daily-config.env
   ```

2. 编辑配置文件：
   ```bash
   vim ~/.hermes-daily-config.env
   ```
   
   需要配置的变量：
   - `FEISHU_HOME_CHANNEL`: 飞书主频道ID
   - `ROBOTICS_NOTEBOOKS_PATH`: Robotics_Notebooks 仓库本地路径

3. 设置文件权限：
   ```bash
   chmod 600 ~/.hermes-daily-config.env
   ```

## 设置定时任务

### 使用 crontab
```bash
# 编辑当前用户的crontab
crontab -e

# 添加以下行（每天早上7点运行）
0 7 * * * /path/to/Agents_Daily_Routines/scripts/hermes-llm-wiki-daily.sh

# 如果需要同时运行多个脚本
0 7 * * * /path/to/Agents_Daily_Routines/scripts/morning-report.sh
0 7 * * * /path/to/Agents_Daily_Routines/scripts/paper-reminder.sh
```

### 使用 Hermes 内置定时任务
```bash
# 创建 Hermes 定时任务
hermes cron create --name "llm-wiki-daily" --schedule "0 7 * * *" --prompt "运行 Robotics_Notebooks Wiki 健康检查"

# 或使用脚本文件
hermes cron create --name "llm-wiki-daily" --schedule "0 7 * * *" --script /path/to/Agents_Daily_Routines/scripts/hermes-llm-wiki-daily.sh
```

## 安全注意事项

1. **敏感信息保护**：
   - 所有敏感配置（API密钥、频道ID等）都应放在环境变量文件中
   - 环境变量文件应添加到 `.gitignore` 避免误提交
   - 设置适当的文件权限（600）

2. **日志管理**：
   - 脚本会自动生成日志文件到 `~/.hermes/cron/logs/`
   - 定期清理旧日志文件

3. **错误处理**：
   - 脚本使用 `set -euo pipefail` 进行严格的错误检查
   - 关键步骤都有错误处理和警告提示

## 脚本功能详情

### hermes-llm-wiki-daily.sh
该脚本执行以下检查：
1. **Wiki 健康检查**：运行 `lint_wiki.py` 检查wiki结构
2. **积压任务检查**：检查 `log.md` 中的"计划但未执行"任务
3. **页面目录生成**：运行 `generate_page_catalog.py` 更新目录
4. **Git 状态检查**：检查仓库是否有未提交的更改
5. **报告生成和发送**：生成检查报告并发送到飞书

## 故障排除

### 常见问题
1. **脚本权限问题**：
   ```bash
   chmod +x scripts/*.sh
   ```

2. **环境变量未设置**：
   - 检查 `~/.hermes-daily-config.env` 文件是否存在
   - 检查文件中的变量是否正确设置

3. **Hermes 命令找不到**：
   - 确保 Hermes 已正确安装并添加到 PATH
   - 或在脚本中指定完整路径：`/usr/local/bin/hermes`

4. **飞书发送失败**：
   - 检查飞书频道ID是否正确
   - 检查 Hermes 的飞书配置是否正确

### 日志查看
```bash
# 查看最新日志
tail -f ~/.hermes/cron/logs/llm-wiki-daily-$(date +%Y%m%d).log

# 列出所有日志文件
ls -la ~/.hermes/cron/logs/
```

## 贡献指南
欢迎提交新的每日任务脚本。请确保：
1. 脚本有清晰的注释说明
2. 使用环境变量进行配置
3. 包含错误处理和日志记录
4. 更新 README.md 文档