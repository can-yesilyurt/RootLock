        #!/bin/sh
        Address="172.20.0.2"
        Mask="255.255.255.240"
        Router="172.20.10.1"
        DNS="1.1.1.1"
        SOCKS_HOST="127.0.0.1"
        SOCKS_PORT="9001"
        BYPASS_DOMAINS=("localhost" "127.0.0.1" "*.local")
        set -euo pipefail
        main() {
            local str=$(/usr/sbin/networksetup -listnetworkserviceorder |grep -n iPhone | head -1)
            local svc="${str#* }"
            local Address="172.20.10.2"
            local Mask="255.255.255.240"
            local Router="172.20.10.1"
            local DNS="1.1.1.1"
            /usr/sbin/networksetup -setmanual "$svc" $Address $Mask $Router
            /usr/sbin/networksetup -setdnsservers "$svc" $DNS
            echo "Net:    $svc"
            echo "IP:     $Address"
            echo "Router: $Router"
            echo "Mask:   $Mask"
            echo "DNS:    $DNS"
        }
        main
