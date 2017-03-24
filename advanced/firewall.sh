#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Sets the firewall rules after Pi-hole reboot
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

set -e
setupVars=/etc/pihole/setupVars.conf

source ${setupVars}

# Allow HTTP and DNS traffic
if firewall-cmd --state &> /dev/null; then
    firewall-cmd --permanent --add-service=http --add-service=dns
    firewall-cmd --reload
    return 0
    # Check for proper kernel modules to prevent failure
elif modinfo ip_tables &> /dev/null && command -v iptables &> /dev/null; then
    # If chain Policy is not ACCEPT or last Rule is not ACCEPT
    # then check and insert our Rules above the DROP/REJECT Rule.
    if iptables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || iptables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
	# Check chain first, otherwise a new rule will duplicate old ones
	iptables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
	iptables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
	iptables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
	# Reject https to avoid timeout issues for blocked https adds
	iptables -C INPUT -p tcp -m tcp --dport 443 -j REJECT &> /dev/null || iptables -I INPUT 1 -p tcp -m tcp --dport 443 -j REJECT
    fi
    
    if [[ ! -z "${IPV6_ADDRESS}" ]]; then
	# Configure IPv6 firewall
	if ip6tables -S INPUT | head -n1 | grep -qv '^-P.*ACCEPT$' || ip6tables -S INPUT | tail -n1 | grep -qv '^-\(A\|P\).*ACCEPT$'; then
	    # Check chain first, otherwise a new rule will duplicate old ones
	    ip6tables -C INPUT -p tcp -m tcp --dport 80 -j ACCEPT &> /dev/null || ip6tables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT
	    ip6tables -C INPUT -p tcp -m tcp --dport 53 -j ACCEPT &> /dev/null || ip6tables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT
	    ip6tables -C INPUT -p udp -m udp --dport 53 -j ACCEPT &> /dev/null || ip6tables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT
	    # Reject https to avoid timeout issues for blocked https adds
	    ip6tables -C INPUT -p tcp -m tcp --dport 443 -j REJECT &> /dev/null || ip6tables -I INPUT 1 -p tcp -m tcp --dport 443 -j REJECT
	fi
    fi
fi
