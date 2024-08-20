#!/bin/bash

# 设置版本号
current_version=20240820001

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/flock/main/flock.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

# 部署训练节点
function install_training_node() {

    # 运行参数
    read -p "TASK_ID: " TASK_ID
    read -p "Flock API Key: " FLOCK_API_KEY
    read -p "Hugging Face Token: " HF_TOKEN
    read -p "Hugging Face Username: " HF_USERNAME
	
    echo "开始部署..."

    sudo apt update 
    sudo apt upgrade -y
    sudo apt install -y curl sudo python3-venv iptables build-essential wget jq make gcc nano git

    # 安装conda
    wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash miniconda.sh -b -p $HOME/miniconda
    $HOME/miniconda/bin/conda init
    echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> $HOME/.bashrc
    source $HOME/.bashrc

	# 克隆testnet-training-node-quickstart代码
    git clone https://github.com/FLock-io/testnet-training-node-quickstart.git
    cd testnet-training-node-quickstart
    
    # 部署conda环境
    $HOME/miniconda/bin/conda create -n training-node python==3.10 -y
    source "$HOME/miniconda/bin/activate" training-node
    pip install -r requirements.txt

    # 将变量添加到环境变量文件中
    echo "TASK_ID=\"$TASK_ID\"" >> ~/.env_training
    echo "FLOCK_API_KEY=\"$FLOCK_API_KEY\"" >> ~/.env_training
    echo "HF_TOKEN=\"$HF_TOKEN\"" >> ~/.env_training
    echo "HF_USERNAME=\"$HF_USERNAME\"" >> ~/.env_training

    # 使变量在当前会话中生效
    chmod 600 ~/.env_training

    sudo tee /lib/systemd/system/training.service > /dev/null <<EOF
[Unit]
Description=Training Node Service
After=network.target

[Service]
ExecStart=/bin/bash -c "source $HOME/miniconda/bin/activate training-node && exec python full_automation.py"
WorkingDirectory=$HOME/testnet-training-node-quickstart
User=$USER
EnvironmentFile=$HOME/.env_training
Restart=always

[Install]
WantedBy=multi-user.target

EOF

    sudo systemctl daemon-reload
    sudo systemctl enable training
    sudo systemctl start training
	echo "训练节点部署完成..."
}

# 查看训练节点状态
function view_training_status(){
    sudo systemctl status training
}

# 查看训练节点日志
function view_training_logs(){
	sudo journalctl -u training.service -f --no-hostname -o cat
}

# 停止训练节点
function stop_training_node(){
	sudo systemctl stop training
	echo "训练节点已停止"
}

# 启动训练节点
function start_training_node(){
    sudo systemctl start training
	echo "训练节点已启动"
}

# 卸载训练节点
function uninstall_training_node() {
    echo "确定要卸载验证节点吗？[Y/N]"
    read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载验证节点..."
            stop_training_node
            sudo rm -f /etc/systemd/system/training.service
            rm -rf $HOME/testnet-training-node-quickstart
            rm -rf $HOME/miniconda
            rm -rf $HOME/miniconda.sh
            echo "验证节点卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 部署验证节点
function install_validator_node() {

    # 运行参数
    read -p "TASK_ID: " TASK_ID
    read -p "Flock API Key: " FLOCK_API_KEY
    read -p "Hugging Face Token: " HF_TOKEN

    # 是否使用GPU
    read -r -p "是否使用GPU运算？ " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "修改参数，使用GPU运行..."
            IS_GPU=1
            ;;
        *)
            echo "使用CPU运行..."
            IS_GPU=0
            ;;
    esac

    sudo apt update 
    sudo apt upgrade -y
    sudo apt install -y curl sudo python3-venv iptables build-essential wget jq make gcc nano git npm
    
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 版本: $(node -v)"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 版本: $(npm -v)"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi

    # 安装conda
    wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash miniconda.sh -b -p $HOME/miniconda
    $HOME/miniconda/bin/conda init
    echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> $HOME/.bashrc
    source $HOME/.bashrc

    # 克隆仓库
    git clone https://github.com/FLock-io/llm-loss-validator.git
    cd llm-loss-validator
    conda create -n llm-loss-validator python==3.10 -y
    source "$HOME/miniconda/bin/activate" llm-loss-validator
    # 安装依赖
    pip install -r requirements.txt
    
    # 启动节点
    cd $HOME/llm-loss-validator/src

    # 将变量添加到环境变量文件中
    echo "TASK_ID=\"$TASK_ID\"" >> ~/.env_validator
    echo "FLOCK_API_KEY=\"$FLOCK_API_KEY\"" >> ~/.env_validator
    echo "HF_TOKEN=\"$HF_TOKEN\"" >> ~/.env_validator
    if [ "$IS_GPU" -eq 1 ]; then
        echo "CUDA_VISIBLE_DEVICES=\"0\"" >> ~/.env_validator
    fi

    # 使变量在当前会话中生效
    chmod 600 ~/.env_validator

    sudo tee /lib/systemd/system/validator.service > /dev/null <<EOF
[Unit]
Description=Validator Node Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/llm-loss-validator/src
EnvironmentFile=$HOME/.env_validator
ExecStart=/bin/bash start.sh --hf_token $HF_TOKEN --flock_api_key $FLOCK_API_KEY --task_id $TASK_ID --validation_args_file validation_config.json.example --auto_clean_cache False
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

    sudo systemctl daemon-reload
    sudo systemctl enable validator
    sudo systemctl start validator

    #screen -dmS validator bash start.sh --task_id $TASK_ID --flock_api_key $FLOCK_API_KEY --hf_token $HF_TOKEN --validation_args_file validation_config.json.example --auto_clean_cache False

	echo "验证节点部署完成"
}

# 查看验证节点状态
function view_validator_status(){
    sudo systemctl status validator
}

# 查看验证节点日志
function view_validator_logs(){
	sudo journalctl -u validator.service -f --no-hostname -o cat
}

# 停止验证节点
function stop_validator_node(){
	sudo systemctl stop validator
	echo "训练节点已停止"
}

# 启动验证节点
function start_validator_node(){
    sudo systemctl start validator
    #screen -dmS validator bash start.sh --hf_token $HF_TOKEN --flock_api_key $FLOCK_API_KEY --task_id $TASK_ID --validation_args_file validation_config.json.example --auto_clean_cache False
	echo "验证节点已启动"
}

# 卸载验证节点
function uninstall_validator_node() {
    echo "确定要卸载验证节点吗？[Y/N]"
    read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载验证节点..."
            stop_validator_node
            sudo rm -f /etc/systemd/system/validator.service
            rm -rf $HOME/llm-loss-validator
            echo "验证节点卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================Flock一键部署脚本==================="
		echo "当前版本：$current_version"
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "推荐配置：12C24G300G;CPU核心越多越好"
	    echo "请选择要执行的操作:"
        echo "----------------------训练节点-----------------------"
	    echo "1. 部署训练节点 install_training_node"
	    echo "2. 训练节点日志 view_training_logs"
	    echo "3. 停止训练节点 stop_training_node"
	    echo "4. 启动训练节点 start_training_node"
	    echo "5. 训练节点状态 view_training_status"
	    echo "1618. 卸载训练节点 uninstall_training_node"
        echo "----------------------验证节点-----------------------"
	    echo "21. 部署验证节点 install_validator_node"
	    echo "23. 验证节点日志 view_validator_logs"
	    echo "23. 停止验证节点 stop_validator_node"
	    echo "24. 启动验证节点 start_validator_node"
	    echo "25. 卸载验证节点 uninstall_validator_node"
	    echo "2618. 卸载验证节点 uninstall_validator_node"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_training_node ;;
	    2) view_training_logs ;;
	    3) stop_training_node ;;
	    4) start_training_node ;;
	    5) view_training_status ;;
	    1618) uninstall_training_node ;;
	    21) install_validator_node ;;
	    22) view_validator_logs ;;
	    23) stop_validator_node ;;
	    24) start_validator_node ;;
	    25) view_validator_status ;;
	    2628) uninstall_validator_node ;;

	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 检查更新
update_script

# 显示主菜单
main_menu