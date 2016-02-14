#!/usr/bin/env bash


IPv4dev=$(/sbin/ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++)if($i~/dev/)print $(i+1)}')
piholeIPCIDR=$(/sbin/ip -o -f inet addr show dev $IPv4dev | awk '{print $4}' | awk 'END {print}')
piholeIP=${piholeIPCIDR%/*}

adList=/etc/pihole/gravity.list
blackList=/etc/pihole/blacklist.txt
whiteList=/etc/pihole/whitelist.txt
goodListNames="google-public-dns-a.google.com google-public-dns-b.google.com"


# Function to resolve hostname and determine if IP is RFC1918, pi-hole, or internet address for the host.
# Accepts 1 argument which is a host to resolve.
verifyHostAddress() {
    status=""
    ip=`nslookup $1 | grep ^"Address:" | tail -1 | cut -d: -f2 | sed 's/ //g'`

    if [[ $ip == $piholeIP ]]; then
        status="pi-hole IP"
    elif [[ $ip =~ (^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.) ]]; then
        status="RFC1918"
    elif [[ "$ip" == "" ]]; then
        status="empty"
    else
        status=$ip
    fi
}


if [[ -r $adList ]];then
    adListNames=""
    numberOf=$(cat $adList | sed '/^\s*$/d' | wc -l)
    for n in `shuf -i 1-$numberOf -n 2`
    do
        adListNames="$adListNames `sed -n ${n}p $adList | cut -d\  -f2`"
    done
fi


if [[ -r $blackList ]];then
    blackListNames=""
    numberOf=$(cat $blackList | sed '/^\s*$/d' | wc -l)
    for n in `shuf -i 1-$numberOf -n 2`
    do
        blackListNames="$blackListNames `sed -n ${n}p $blackList`"
    done
fi


if [[ -r $whiteList ]];then
    whiteListNames=""
    numberOf=$(cat $whiteList | sed '/^\s*$/d' | wc -l)
    for n in `shuf -i 1-$numberOf -n 2`
    do
        whiteListNames="$whiteListNames `sed -n ${n}p $whiteList`"
    done
fi


echo -e "\nTesting known good websites."
for name in $goodListNames
do
    verifyHostAddress "$name"
    if [[ "$status" == "pi-hole IP" ]]; then
        echo -e "\tFailed - $name resolves to your pi-hole ($piholeIP)"
    elif [[ "$status" == "RFC1918" ]]; then
        echo -e "\tFailed - $name resolves to a non-routable address ($ip)"
    elif [[ "$status" == "empty" ]]; then
        echo -e "\tFailed - $name could not be resolved ($ip)"
    else
        echo -e "\tSuccess - $name resolves to a public IP address ($ip)"
    fi
done


echo -e "\nTesting websites from your $whiteList file."
for name in $whiteListNames
do
    verifyHostAddress "$name"
    if [[ "$status" == "pi-hole IP" ]]; then
        echo -e "\tFailed - $name resolves to your pi-hole ($piholeIP)"
    elif [[ "$status" == "RFC1918" ]]; then
        echo -e "\tFailed - $name resolves to a non-routable address ($ip)"
    elif [[ "$status" == "empty" ]]; then
        echo -e "\tFailed - $name could not be resolved ($ip)"
    else
        echo -e "\tSuccess - $name resolves to a public IP address ($ip)"
    fi
done


echo -e "\nTesting websites from your $adList file."
for name in $adListNames
do
    verifyHostAddress "$name"
    if [[ "$status" == "pi-hole IP" ]]; then
        echo -e "\tSuccess - $name resolves to your pi-hole ($ip)"
    elif [[ "$status" == "RFC1918" ]]; then
        echo -e "\tVerify - $name resolves to a non-routable address that is not your pi-hole server ($ip)"
    elif [[ "$status" == "empty" ]]; then
        echo -e "\tFailed - $name could not be resolved ($ip)"
    else
        echo -e "\tFailed - $name resolves to a public IP address ($ip)"
    fi
done


echo -e "\nTesting websites from your $blackList file."
for name in $blackListNames
do
    verifyHostAddress "$name"
    if [[ "$status" == "pi-hole IP" ]]; then
        echo -e "\tSuccess - $name resolves to your pi-hole ($ip)"
    elif [[ "$status" == "RFC1918" ]]; then
        echo -e "\tVerify - $name resolves to a non-routable address that is not your pi-hole server ($ip)"
    else
        echo -e "\tFailed - $name resolves to a public IP address ($ip)"
    fi
done


