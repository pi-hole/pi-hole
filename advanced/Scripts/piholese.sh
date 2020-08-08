#!/bin/bash

yum install -y policycoreutils-python* 

cat << PIHOLESE > /tmp/pihole.te

module pihole 1.0;

require {
	type bin_t;
	type shadow_t;
	type systemd_logind_t;
	type httpd_t;
	type unreserved_port_t;
	type etc_t;
	type httpd_log_t;
	type var_t;
	class file { execmod getattr map open read write };
	class capability { audit_write sys_resource };
	class process setrlimit;
	class netlink_audit_socket nlmsg_relay;
	class dbus send_msg;
	class tcp_socket name_connect;
}

#============= httpd_t ==============
allow httpd_t bin_t:file execmod;
allow httpd_t etc_t:file write;
allow httpd_t httpd_log_t:file write;

#!!!! This avc can be allowed using one of the these booleans:
#     httpd_run_stickshift, httpd_setrlimit
allow httpd_t self:capability { audit_write sys_resource };

#!!!! This avc can be allowed using the boolean 'httpd_mod_auth_pam'
allow httpd_t self:netlink_audit_socket nlmsg_relay;

#!!!! This avc can be allowed using the boolean 'httpd_setrlimit'
allow httpd_t self:process setrlimit;
allow httpd_t shadow_t:file { getattr open read };
allow httpd_t systemd_logind_t:dbus send_msg;

#!!!! This avc can be allowed using one of the these booleans:
#     httpd_can_network_connect, nis_enabled
allow httpd_t unreserved_port_t:tcp_socket name_connect;

#!!!! This avc can be allowed using the boolean 'domain_can_mmap_files'
allow httpd_t var_t:file map;
allow httpd_t var_t:file { getattr open read };

#============= systemd_logind_t ==============
allow systemd_logind_t httpd_t:dbus send_msg;

PIHOLESE

checkmodule -M -m -o /tmp/pihole.mod /tmp/pihole.te
semodule_package -o /tmp/pihole.pp -m /tmp/pihole.mod

semodule -i /tmp/pihole.pp

/bin/rm /tmp/pihole*

