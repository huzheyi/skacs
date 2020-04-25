#! /bin/sh
### BEGIN INIT INFO
# Provides:          shadowsocks
# Required-Start:    $syslog $time $remote_fs
# Required-Stop:     $syslog $time $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Start shadowsocks daemon
### END INIT INFO

PATH=/bin:/usr/bin:/sbin:/usr/sbin
PROJECT=/config/skacs

#This source ip range will not go through shadowsocks
#BYPASS_RANGE=192.168.1.128/32
BYPASS_RANGES=(192.168.1.232 192.168.1.233 192.168.1.234 192.168.1.235)

#Your ISP dns or public dns, like 1.2.4.8, 114.114.114.114
ISPDNS=119.29.29.29

#Executable files path
DAEMON_KCPTUN=$PROJECT/bin/client_linux_mipsle
DAEMON_SS_LOCAL=$PROJECT/bin/ss-local
DAEMON_SS_REDIR=$PROJECT/bin/ss-redir
DAEMON_SMARTDNS=$PROJECT/bin/smartdns
DAEMON_CHINADNS=$PROJECT/bin/chinadns-ng
DAEMON_ADG=$PROJECT/bin/AdGuardHome

#Configuration files path
CONFIG_KCPTUN=$PROJECT/conf/kcp.json
CONFIG_SS=$PROJECT/conf/shadowsocks.json
CONFIG_SMARTDNS=$PROJECT/conf/smartdns.conf
CONFIG_ADG=$PROJECT/conf

#Process ID files path
PIDFILE_KCPTUN=/var/run/kcptun.pid
PIDFILE_SS_LOCAL=/var/run/ss-local.pid
PIDFILE_SS_REDIR=/var/run/ss-redir.pid
PIDFILE_SMARTDNS=/var/run/smartdns.pid
PIDFILE_CHINADNS=/var/run/chinadns.pid
PIDFILE_ADG=/var/run/adguardhome.pid

#Use iplist.sh to update files below
GFWLIST=$PROJECT/conf/gfwlist.txt
CHNROUTE=$PROJECT/conf/chnroute.txt
CHNROUTE6=$PROJECT/conf/chnroute6.txt

test -x $DAEMON_KCPTUN || exit 0
test -x $DAEMON_SS_LOCAL || exit 0
test -x $DAEMON_SS_REDIR || exit 0
test -x $DAEMON_SMARTDNS || exit 0
test -x $DAEMON_CHINADNS || exit 0
test -x $DAEMON_ADG || exit 0


. /lib/lsb/init-functions

#Test if network ready (pppoe)
test_network() {
	curl --retry 1 --silent --connect-timeout 2 -I www.baidu.com  > /dev/null
	if [ "$?" != "0" ]; then
		echo 'network not ready, wait for 5 seconds ...'
		sleep 5
	fi
}

get_server_ip() {
	ss_server_host=`grep -o "\"server\"\s*:\s*\"\?[-0-9a-zA-Z.]\+\"\?" $CONFIG_SS|sed -e 's/"//g'|awk -F':' '{print $2}'|sed -e 's/\s//g'`
	if [ -z $ss_server_host ];then
	  echo "Error : ss_server_host is empty"
	  exit 0
	fi

	#test if domain or ip
	if echo $ss_server_host | grep -q '^[^0-9]'; then
	  ss_server_ip=`getent hosts $ss_server_host | awk '{ print $1 }'`
	else
	  ss_server_ip=$ss_server_host
	fi

	if [ -z "$ss_server_ip" ];then
	  echo "Error : ss_server_ip is empty"
	  exit 0
	fi
}

gen_chnroute() {
	cat <<-EOF
		0.0.0.0/8
		10.0.0.0/8
		100.64.0.0/10
		127.0.0.0/8
		169.254.0.0/16
		172.16.0.0/12
		192.0.0.0/24
		192.0.2.0/24
		192.88.99.0/24
		192.168.0.0/16
		198.18.0.0/15
		198.51.100.0/24
		203.0.113.0/24
		224.0.0.0/4
		240.0.0.0/4
		255.255.255.255/32
		$ss_server_ip
		$(cat ${CHNROUTE:=/dev/null} 2>/dev/null)
EOF
}

gen_chnroute6() {
	cat <<-EOF
		::/128
		::1/128
		::ffff:0:0/96
		::ffff:0:0:0/96
		64:ff9b::/96
		100::/64
		2001::/32
		2001:20::/28
		2001:db8::/32
		2002::/16
	 	fc00::/7
		fe80::/10
		ff00::/8
		$(cat ${CHNROUTE6:=/dev/null} 2>/dev/null)
EOF
}


rules_add() {
	ipset -! -R <<-EOF || return 1
		create chnroute hash:net family inet
		$(gen_chnroute | sed -e "s/^/add chnroute /")
EOF
	iptables -t nat -N SHADOWSOCKS && \
	iptables -t nat -A SHADOWSOCKS -m set --match-set chnroute dst -j RETURN && \
	iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports 1081 && \
	iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS && \
	iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to 192.168.1.1 &&\
	iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
	if [ "$BYPASS_RANGE" ]; then
		iptables -t nat -I SHADOWSOCKS -s $BYPASS_RANGE -j RETURN
	fi
	if [ "$BYPASS_RANGES" ]; then
		for i in "${BYPASS_RANGES[@]}"
		do
			iptables -t nat -I SHADOWSOCKS -s ${i} -j RETURN
		done
	fi
	
	return $?
}

rules_add6() {
	ipset -! -R <<-EOF || return 1
		create chnroute6 hash:net family inet6
		$(gen_chnroute6 | sed -e "s/^/add chnroute6 /")
EOF

	return $?
}


rules_flush() {
	iptables -t nat -F SHADOWSOCKS
	iptables -t nat -D PREROUTING -p udp --dport 53 -j DNAT --to 192.168.1.1
	iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS
	iptables -t nat -D OUTPUT -p tcp -j SHADOWSOCKS
	iptables -t nat -X SHADOWSOCKS
	ipset -X chnroute
	return $?
}

rules_flush6() {
	ipset -X chnroute6
}

case "$1" in
  start)
	test_network
	get_server_ip

	#log_daemon_msg "Establishing kcptun" "client_linux_mipsle"
	#start-stop-daemon -S -p $PIDFILE_KCPTUN --oknodo -b -m $PIDFILE_KCPTUN --startas $DAEMON_KCPTUN  -- -c $CONFIG_KCPTUN
	#log_end_msg $?
	
	log_daemon_msg "Starting ss-local" "ss-local"
	start-stop-daemon -S -p $PIDFILE_SS_LOCAL --oknodo --startas $DAEMON_SS_LOCAL -- -u -l 1080 -c $CONFIG_SS -f $PIDFILE_SS_LOCAL
	log_end_msg $?

	log_daemon_msg "Starting ss-redir" "ss-redir"
	start-stop-daemon -S -p $PIDFILE_SS_REDIR --oknodo --startas $DAEMON_SS_REDIR -- -u -l 1081 -c $CONFIG_SS -f $PIDFILE_SS_REDIR
	log_end_msg $?

	log_daemon_msg "Starting SmartDNS" "smartdns"
	start-stop-daemon -S -p $PIDFILE_SMARTDNS --oknodo --startas $DAEMON_SMARTDNS -- -c $CONFIG_SMARTDNS -p $PIDFILE_SMARTDNS
	log_end_msg $?

	log_daemon_msg "Starting ChinaDNS-NG" "chinadns-ng"
	start-stop-daemon -S -p $PIDFILE_CHINADNS --oknodo -b -m $PIDFILE_CHINADNS --startas $DAEMON_CHINADNS -- -l 5301 -c $ISPDNS -t '127.0.0.1#5302' -g $GFWLIST 
	log_end_msg $?

	log_daemon_msg "Starting AdGuardHome" "AdGuardHome"
	start-stop-daemon -S -p $PIDFILE_ADG --oknodo --background --startas $DAEMON_ADG -- -w $CONFIG_ADG --pidfile $PIDFILE_ADG
	log_end_msg $?

	log_daemon_msg "Adding iptables rules, ss_server_ip" `for i in $ss_server_ip; do p=$p$i","; done; echo ${p%,}`
	rules_add
	rules_add6
	log_end_msg $?

	log_daemon_msg "Updating DNS configuration" "dnsmasq"
	sed -i s/server=$ISPDNS/server=127.0.0.1#5300/ /etc/dnsmasq.d/my.conf
	[ 0 == `grep "^server" /etc/dnsmasq.d/my.conf|wc -l` ] && echo server=127.0.0.1#5300 >> /etc/dnsmasq.d/my.conf
	[ 0 == `grep "^no-resolv" /etc/dnsmasq.d/my.conf|wc -l` ] && echo no-resolv >> /etc/dnsmasq.d/my.conf
	service dnsmasq restart
	log_end_msg $?

    ;;

  stop)
	#log_daemon_msg "Destroying kcptun" "client_linux_mipsle"
	#start-stop-daemon -K -p $PIDFILE_KCPTUN --oknodo
	#log_end_msg $?

	log_daemon_msg "Stopping ss-local" "ss-local"
	start-stop-daemon -K -p $PIDFILE_SS_LOCAL --oknodo
	log_end_msg $?

	log_daemon_msg "Stopping ss-redir" "ss-redir"
	start-stop-daemon -K -p $PIDFILE_SS_REDIR --oknodo
	log_end_msg $?

	log_daemon_msg "Stopping AdGuardHome" "AdGuardHome"
	start-stop-daemon -K -p $PIDFILE_ADG --oknodo
	log_end_msg $?

	log_daemon_msg "Stopping ChinaDNS-NG" "ChinaDNS-NG"
	start-stop-daemon -K -p $PIDFILE_CHINADNS --oknodo
	log_end_msg $?

	log_daemon_msg "Stopping SmartDNS" "SmartDNS"
	start-stop-daemon -K -p $PIDFILE_SMARTDNS --oknodo
	log_end_msg $?

	log_daemon_msg "Deleting iptables rules" "rules_flush"
	rules_flush
	rules_flush6
	log_end_msg $?

	log_daemon_msg "Updating DNS configuration" "dnsmasq"
	sed -i s/server=127.0.0.1#5300/server=$ISPDNS/ /etc/dnsmasq.d/my.conf
	[ 0 == `grep "^server" /etc/dnsmasq.d/my.conf|wc -l` ] && echo server=$ISPDNS >> /etc/dnsmasq.d/my.conf
	service dnsmasq restart
	log_end_msg $?
    ;;

  force-reload|restart)
    $0 stop
    $0 start
    ;;

  status)
    #status_of_proc -p $PIDFILE_KCPTUN $DAEMON_KCPTUN client_linux_mipsle
    status_of_proc -p $PIDFILE_SS_REDIR $DAEMON_SS_REDIR ss-redir
    status_of_proc -p $PIDFILE_SS_LOCAL $DAEMON_SS_LOCAL ss-local
    status_of_proc -p $PIDFILE_SMARTDNS $DAEMON_SMARTDNS SmartDNS
    status_of_proc -p $PIDFILE_CHINADNS $DAEMON_CHINADNS ChinaDNS-NG
    status_of_proc -p $PIDFILE_ADG $DAEMON_ADG AdGuardHome
    ;;

  *)
    echo "Usage: $PROJECT/start-all.sh {start|stop|restart|force-reload|status}"
    exit 1
    ;;
esac

exit 0
