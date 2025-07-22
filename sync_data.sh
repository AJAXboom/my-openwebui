#!/bin/bash

# 检查必要的环境变量
if [ -z "$G_NAME" ] || [ -z "$G_TOKEN" ]; then
    echo "缺少必要的环境变量 G_NAME 或 G_TOKEN"
    exit 1
fi

# 解析仓库名和用户名
# IFS='/' read -r GITHUB_USER GITHUB_REPO <<< "$G_NAME" # 这行其实没用到，可以省略

# 构建 GitHub 仓库的克隆 URL，包含令牌
REPO_URL="https://${G_TOKEN}@github.com/${G_NAME}.git"
mkdir -p ./data/github_data

# 克隆仓库
echo "正在克隆仓库……"
git clone --depth 1 "$REPO_URL" ./data/github_data || {
    echo "克隆失败，请检查 G_NAME 和 G_TOKEN 是否正确。"
    exit 1
}

if [ -f ./data/github_data/webui.db ]; then
    cp ./data/github_data/webui.db ./data/webui.db
    echo "从 GitHub 仓库中拉取 webui.db 成功"
else
    echo "GitHub 仓库中未找到 webui.db，将在首次同步时创建并推送"
fi

# 定义同步函数
sync_data() {
    while true; do
        # 1. 同步到 GitHub
        echo "======== 开始新一轮同步检查 ========"
        
        # 检查 webui.db 是否存在
        if [ ! -f "./data/webui.db" ]; then
            echo "数据库 ./data/webui.db 尚未由 Open WebUI 初始化，跳过本次同步。"
        else
            # 进入仓库目录
            cd ./data/github_data
            
            # 比较文件是否有差异
            if cmp -s ../webui.db ./webui.db; then
                echo "GitHub: 数据库文件无变化，无需同步。"
            else
                echo "GitHub: 检测到数据库变化，开始同步..."
                # 配置 Git 用户信息
                git config user.name "AutoSync Bot"
                git config user.email "autosync@bot.com"

                # 确保在正确的分支
                git checkout main || git checkout master

                # 复制最新的数据库文件
                cp ../webui.db ./webui.db

                # 添加所有变更
                git add webui.db
                # 提交变更
                git commit -m "Auto sync webui.db $(date '+%Y-%m-%d %H:%M:%S')"
                # 推送到远程仓库
                git push origin HEAD && {
                    echo "GitHub 推送成功"
                } || {
                    echo "推送失败，等待10秒后重试..."
                    sleep 10
                    git push origin HEAD || echo "重试失败，放弃本次推送到 GitHub。"
                }
            fi
            # 返回项目根目录
            cd ../..

            # 2. 同步到 WebDAV
            if [ -z "$WEBDAV_URL" ] || [ -z "$WEBDAV_USERNAME" ] || [ -z "$WEBDAV_PASSWORD" ]; then
                echo "WebDAV: 环境变量缺失，跳过同步。"
            else
                echo "WebDAV: 开始同步..."
                FILENAME="webui_$(date +'%Y_%m_%d').db" # 每天覆盖当天的备份
                curl -T ./data/webui.db --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$WEBDAV_URL/$FILENAME" && {
                    echo "WebDAV 上传成功: $FILENAME"
                } || {
                    echo "WebDAV 上传失败，等待10秒后重试..."
                    sleep 10
                    curl -T ./data/webui.db --user "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$WEBDAV_URL/$FILENAME" || echo "重试失败，放弃本次 WebDAV 上传。"
                }
            fi
        fi

        # 3. 等待统一的时间间隔
        SYNC_INTERVAL=${SYNC_INTERVAL:-7200}  # 默认间隔2小时
        echo "当前时间 $(date '+%Y-%m-%d %H:%M:%S')"
        echo "等待 ${SYNC_INTERVAL} 秒后进行下一次同步..."
        echo "========================================"
        sleep $SYNC_INTERVAL
    done
}

# 后台启动同步进程
sync_data &

