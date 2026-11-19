#!/bin/sh

CONF_FILE="/etc/tailscale/tailscale_up.conf"
PARAMS_LIST="--accept-dns:flag:接受来自管理面板的 DNS 配置（默认 true）
--accept-risk:value:接受风险类型并跳过确认（lose-ssh、mac-app-connector、linux-strict-rp-filter、all）
--accept-routes:flag:接受其他 Tailscale 节点通告的路由（默认 false）
--advertise-connector:flag:将此节点宣告为应用连接器（默认 false）
--advertise-exit-node:flag:提供此节点作为出口节点以转发互联网流量（默认 false）
--advertise-routes:value:向其他节点通告的路由（逗号分隔，例如 10.0.0.0/8,192.168.0.0/24），空字符串表示不通告
--advertise-tags:value:请求的 ACL 标签（逗号分隔），每个必须以 tag: 开头
--auth-key:value:节点授权密钥；如果以 file: 开头则为包含密钥的文件路径
--client-id:value:用于通过工作负载身份联合生成授权密钥的 Client ID
--client-secret:value:用于通过 OAuth 生成授权密钥的 Client Secret；以 file: 开头则为包含密钥的文件路径
--exit-node:value:Tailscale 出口节点（IP、基本名称或 auto:any），空字符串表示不使用出口节点
--exit-node-allow-lan-access:flag:通过出口节点路由时允许直接访问本地局域网（默认 false）
--force-reauth:flag:强制重新认证（警告：会断开 Tailscale 连接，不应在 SSH 或 RDP 远程执行）（默认 false）
--hostname:value:使用此主机名而不是操作系统提供的名称
--id-token:value:从身份提供商获取的 ID token，用于与控制服务器交换以进行工作负载身份联合；以 file: 开头则为文件路径
--json:flag:以 JSON 格式输出（警告：格式可能变更）（默认 false）
--login-server:value:控制服务器的基础 URL（默认 https://controlplane.tailscale.com）
--netfilter-mode:value:netfilter 模式（on、nodivert、off 之一）（默认 on）
--operator:value:允许无需 sudo 操作 tailscaled 的 Unix 用户名
--qr:flag:显示登录 URL 的二维码（默认 false）
--qr-format:value:二维码格式（small 或 large，默认 small）
--reset:flag:将未指定的设置重置为默认值（默认 false）
--shields-up:flag:不允许传入连接（默认 false）
--snat-subnet-routes:flag:对通过 --advertise-routes 通告的本地路由进行源 NAT（默认 true）
--ssh:flag:运行 SSH 服务器，允许根据 tailnet 管理员声明的策略访问（默认 false）
--stateful-filtering:flag:对转发的数据包应用有状态过滤（子网路由器、出口节点等）（默认 false）
--timeout:value:等待 tailscaled 进入 Running 状态的最长时间；默认 0s 表示永远等待"

# 历史格式每行 --key="value"。引号内的内容始终按字面值传递。
run_up() {
    local action=$1 arg
    set -- up
    if [ -f "$CONF_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in --*=*) ;; *) continue ;; esac
            key=${line%%=*}
            case "$key" in *[!a-z-]*) continue ;; esac
            case "
$PARAMS_LIST" in *"
$key:"*) ;; *) continue ;; esac
            value=${line#*=}
            case "$value" in \"*\") value=${value#\"}; value=${value%\"} ;; esac
            set -- "$@" "$key=$value"
        done < "$CONF_FILE"
    fi
    if [ "$action" = run ]; then
        tailscale "$@"
        return $?
    fi

    printf 'tailscale up'
    shift
    for arg do
        case "$arg" in --auth-key=*|--client-secret=*|--id-token=*) arg="${arg%%=*}=••••" ;; esac
        printf " '"
        # 将单引号编码为 shell 命令行中的 '\\''。
        while [ "${arg#*\'}" != "$arg" ]; do
            printf '%s%s' "${arg%%\'*}" "'\\''"
            arg=${arg#*\'}
        done
        printf "%s'" "$arg"
    done
    printf '\n'
}

get_value() {
    [ -f "$CONF_FILE" ] || return 0
    awk -v key="$1" 'index($0, key "=") == 1 {
        value=substr($0, length(key)+2)
        if (value ~ /^".*"$/) value=substr(value, 2, length(value)-2)
    } END { print value }' "$CONF_FILE"
}

edit_param() (
    local key=$1 type=$2 value tmp
    if [ "$type" = flag ]; then
        lock_config || return 1
        value=$(get_value "$key")
        case "$value" in true) value=false ;; false) value="" ;; *) value=true ;; esac
    else
        printf '%s 的新值（直接回车清除）：' "$key"
        IFS= read -r value || return 1
        lock_config || return 1
    fi

    tmp=$(mktemp "$CONF_FILE.XXXXXX") || return 1
    if [ -f "$CONF_FILE" ]; then
        awk -v key="$key" 'index($0,key "=") != 1' "$CONF_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    if [ -n "$value" ]; then
        printf '%s="%s"\n' "$key" "$value" >> "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    mv "$tmp" "$CONF_FILE"
)

show_menu() {
    local number=0 key type description value
    while IFS=: read -r key type description; do
        number=$((number + 1))
        value=$(get_value "$key")
        case "$key" in --auth-key|--client-secret|--id-token) [ -z "$value" ] || value='••••' ;; esac
        printf '%2d) %s = [%s]  %s\n' "$number" "$key" "${value:-默认}" "$description"
    done <<EOF
$PARAMS_LIST
EOF
    printf '0) 退出   g) 预览并执行 tailscale up   输入编号修改参数：'
}

case "${1:-}" in
    --list) printf '%s\n' "$PARAMS_LIST"; exit 0 ;;
    --run) run_up run; exit $? ;;
    '') . /etc/tailscale/tools.sh ;;
    *) exit 1 ;;
esac

while :; do
    show_menu
    IFS= read -r choice || exit 0
    case "$choice" in
        0) exit 0 ;;
        g)
            run_up preview
            printf '立即执行？[Y/n] '
            IFS= read -r answer || exit 0
            case "$answer" in ''|y|Y) run_up run; exit $? ;; esac
            ;;
        ''|*[!0-9]*) ;;
        *)
            param=$(printf '%s\n' "$PARAMS_LIST" | sed -n "${choice}p")
            [ -n "$param" ] || continue
            key=${param%%:*}
            rest=${param#*:}
            edit_param "$key" "${rest%%:*}" || exit 1
            ;;
    esac
done
