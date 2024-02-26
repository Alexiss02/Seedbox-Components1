#!/bin/bash

## Text colors and styles
info() {
	tput sgr0; tput setaf 2; tput bold
	echo "$1"
	tput sgr0
}
info_2() {
	tput sgr0; tput setaf 2
	echo -n "	$1"
	tput sgr0
}
info_3() {
	tput sgr0; tput setaf 2
	echo -e -n "\r\e[K$1"
	tput sgr0
}
boring_text() {
	tput sgr0; tput setaf 7; tput dim
	echo "$1"
	tput sgr0
}
need_input() {
	tput sgr0; tput setaf 6 ; tput bold
	echo "$1" 1>&2
	tput sgr0
}
warn() {
	tput sgr0; tput setaf 3
	echo "$1" 1>&2
	tput sgr0
}
fail() {
	tput sgr0; tput setaf 1; tput bold
	echo "$1" 1>&2
	tput sgr0
}
fail_3() {
	tput sgr0; tput setab 1; tput setaf 7; tput bold
	echo -e -n  "\r\e[K$1" 1>&2
	tput sgr0
}
fail_exit() {
	tput sgr0; tput setaf 1; tput bold
	echo "$1" 1>&2
	tput sgr0
	exit 1
}
seperator() {
	echo -e "\n"
	echo $(printf '%*s' "$(tput cols)" | tr ' ' '=')
	echo -e "\n"
}


## System Update and Install Dependencies
update() {
    apt-get -y update && apt-get -y upgrade

    # Install Dependencies
	if [ -z $(which sudo) ]; then
		apt-get install sudo -y
		if [ $? -ne 0 ]; then
			fail_exit "Sudo Installation Failed"
		fi
	fi
	if [ -z $(which wget) ]; then
		apt-get install wget -y
		if [ $? -ne 0 ]; then
			fail_exit "Wget Installation Failed"
		fi
	fi
	if [ -z $(which curl) ]; then
		apt-get install curl -y
		if [ $? -ne 0 ]; then
			fail_exit "Curl Installation Failed"
		fi
	fi
	if [ -z $(which sysstat) ]; then
		apt-get install sysstat -y
		if [ $? -ne 0 ]; then
			fail_exit "Sysstat Installation Failed"
		fi
	fi
	if [ -z $(which psmisc) ]; then
		apt-get install psmisc -y
		if [ $? -ne 0 ]; then
			fail_exit "Psmisc Installation Failed"
		fi
	fi
	return 0
}

install_autobrr_() {
	if [ -z $username ]; then	# return if $username is not Set
		fail "Username not set"
		return 1
	fi
if [ -z $(getent passwd $username) ]; then	# return if username does not exist
		fail "User does not exist"
		return 1
	fi
	## Install AutoBrr
	# Check CPU architecture
	if [ $(uname -m) == "x86_64" ]; then
		wget $(curl -s https://api.github.com/repos/autobrr/autobrr/releases/latest | grep download | grep linux_x86_64 | cut -d\" -f4)
	elif [ $(uname -m) == "aarch64" ]; then
		wget $(curl -s https://api.github.com/repos/autobrr/autobrr/releases/latest | grep download | grep linux_arm64.tar | cut -d\" -f4)
	else
		fail "AutoBrr download failed"
		return 1
	fi
	# Exit if download fail
	if [ ! -f autobrr*.tar.gz ]; then
		fail "AutoBrr download failed"
		return 1
	fi
	sudo tar -C /usr/bin -xzf autobrr*.tar.gz
	# Exit if extraction fail
	if [ $? -ne 0 ]; then
		fail "AutoBrr extraction failed"
		rm autobrr*.tar.gz
		return 1
	fi
	mkdir -p /home/$username/.config/autobrr
	secret_session_key=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)
	cat << EOF >/home/$username/.config/autobrr/config.toml
# Hostname / IP
#
# Default: "localhost"
#
host = "0.0.0.0"

# Port
#
# Default: 7474
#
port = 7474

# Base url
# Set custom baseUrl eg /autobrr/ to serve in subdirectory.
# Not needed for subdomain, or by accessing with the :port directly.
#
# Optional
#
#baseUrl = "/autobrr/"

# autobrr logs file
# If not defined, logs to stdout
#
# Optional
#
#logPath = "log/autobrr.log"

# Log level
#
# Default: "DEBUG"
#
# Options: "ERROR", "DEBUG", "INFO", "WARN", "TRACE"
#
logLevel = "DEBUG"

# Log Max Size
#
# Default: 50
#
# Max log size in megabytes
#
#logMaxSize = 50

# Log Max Backups
#
# Default: 3
#
# Max amount of old log files
#
#logMaxBackups = 3

# Check for updates
#
checkForUpdates = true

# Session secret
# Can be generated by running: head /dev/urandom | tr -dc A-Za-z0-9 | head -c16
sessionSecret = "$secret_session_key"

# Custom definitions
#
#customDefinitions = "/home/$YOUR_USER/.config/autobrr/definitions"
EOF
	chown -R $username /home/$username/.config/autobrr
	# Create AutoBrr service
	touch /etc/systemd/system/autobrr@.service
	cat << EOF >/etc/systemd/system/autobrr@.service
[Unit]
Description=autobrr service
After=syslog.target network-online.target

[Service]
Type=simple
User=$username
Group=$username
ExecStart=/usr/bin/autobrr --config=/home/$username/.config/autobrr/

[Install]
WantedBy=multi-user.target
EOF
	# Enable and start AutoBrr
	systemctl enable autobrr@$username
	systemctl start autobrr@$username
	# Clean up
	rm autobrr*.tar.gz
	
	# Check if AutoBrr is running
	if [ -z $(pgrep autobrr) ]; then
		fail "AutoBrr failed to start"
		return 1
	fi

	return 0
}

install_vertex_() {
	if [[ -z $username ]] || [ -z $password ]; then
		fail "Username or password not set"
		return 1
	fi
	#Check if docker is installed
	if [ -z $(which docker) ]; then
		curl -fsSL https://get.docker.com -o get-docker.sh
		# Check if download fail
		if [ ! -f get-docker.sh ]; then
			fail "Docker download failed"
			return 1
		fi
		sh get-docker.sh
		# Check if installation fail
		if [ $? -ne 0 ]; then
			fail "Docker installation failed"
			rm get-docker.sh
			return 1
		fi
	else
		#Check if Docker image vertex is installed
		if [ -n $(docker images | grep vertex | grep -v grep) ]; then
			fail "Vertex already installed"
			return 1
		fi
	fi
	## Install Vertex
	if [ -z $(which apparmor) ]; then
		apt-get -y install apparmor
		#Check if install is successful
		if [ $? -ne 0 ]; then
			fail "Apparmor Installation Failed"
			return 1
		fi
	fi
	if [ -z $(which apparmor-utils) ]; then
		apt-get -y install 
		#Check if install is successful
		if [ $? -ne 0 ]; then
			fail "Apparmor-utils Installation Failed"
			return 1
		fi
	fi
	timedatectl set-timezone Asia/Shanghai
	mkdir -p /root/vertex
	chmod 755 /root/vertex
	docker run -d --name vertex --restart unless-stopped --network host -v /root/vertex:/vertex -e TZ=Asia/Shanghai lswl/vertex:stable
	sleep 5s
	# Check if Vertex is running
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "running" ]; then
		fail "Vertex failed to start"
		return 1
	fi
	# Set username & password
	docker stop vertex
	sleep 5s
	# Confirm it is stopped
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "exited" ]; then
		fail "Vertex failed to stop"
		return 1
	fi
	# Set username & password
	vertex_pass=$(echo -n $password | md5sum | awk '{print $1}')
	cat << EOF >/root/vertex/data/setting.json
{
  "username": "$username",
  "password": "$vertex_pass"
}
EOF
	# Start Vertex
	docker start vertex
	sleep 5s
	# Check if Vertex has restarted
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "running" ]; then
		fail "Vertex failed to start"
		return 1
	fi
	# Clean up
	rm get-docker.sh
	return 0
}

install_autoremove-torrents_() {
	if [[ -z $username ]] || [ -z $password ]; then
		fail "Username or password not set"
		return 1
	fi
	#Check if autoremove-torrents is installed 
	if test -f /usr/local/bin/autoremove-torrents; then
		fail "Autoremove-torrents already installed"
		return 1
	fi
	## Install Autoremove-torrents
	if [ -z $(which pipx) ]; then
		apt-get install pipx -y
		#Check if install is successful
		if [ $? -ne 0 ]; then
			fail "Pipx Installation Failed"
			return 1
		fi
	fi
	su $username -s /bin/sh -c "pipx install autoremove-torrents"
	# Check if installation fail
	if [ $? -ne 0 ]; then
		fail "Autoremove-torrents installation failed"
		return 1
	fi
	su user -s /bin/sh -c "pipx ensurepath"
    # qBittorrent
	if test -f /usr/bin/qbittorrent-nox; then
		touch /home/$username/.config.yml && chown $username:$username /home/$username/.config.yml
        cat << EOF >>/home/$username/.config.yml
General-qb:          
  client: qbittorrent
  host: http://127.0.0.1:8080
  username: $username
  password: $password
  strategies:
    General:
      seeding_time: 3153600000
  delete_data: true
EOF
    fi
    mkdir -p /home/$username/.autoremove-torrents/log && chown -R $username /home/$username/.autoremove-torrents
	touch /home/$username/.autoremove-torrents/autoremove-torrents.sh && chown $username:$username /home/$username/.autoremove-torrents/autoremove-torrents.sh
	cat << EOF >/home/$username/.autoremove-torrents/autoremove-torrents.sh
#!/bin/bash
while true; do
	/home/user/.local/bin/autoremove-torrents --conf=/home/$username/.config.yml --log=/home/$username/.autoremove-torrents/log
	sleep 5s
done
EOF
	chmod +x /home/$username/.autoremove-torrents/autoremove-torrents.sh
	# Create Autoremove-torrents service
	touch /etc/systemd/system/autoremove-torrents@.service
	cat << EOF >/etc/systemd/system/autoremove-torrents@.service
[Unit]
Description=autoremove-torrents service
After=syslog.target network-online.target

[Service]
Type=simple
User=$username
Group=$username
ExecStart=/home/$username/.autoremove-torrents/autoremove-torrents.sh

[Install]
WantedBy=multi-user.target
EOF
	# Enable and start Autoremove-torrents
	systemctl enable autoremove-torrents@$username
	systemctl start autoremove-torrents@$username
	return 0
}

## System Tweaking

# Tuned
tuned_() {
    if [ -z $(which tuned) ]; then
		apt-get -qqy install tuned
		#Check if install is successful
		if [ $? -ne 0 ]; then
			fail "Tuned Installation Failed"
			return 1
		fi
	fi
	return 0
}

# Network
set_ring_buffer_() {
    interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which ethtool) ]; then
		apt-get -y install ethtool
		if [ $? -ne 0 ]; then
			fail "Ethtool Installation Failed"
			return 1
		fi
	fi
    ethtool -G $interface rx 1024
	if [ $? -ne 0 ]; then
		fail "Ring Buffer Setting Failed"
		return 1
	fi
    sleep 1
    ethtool -G $interface tx 2048
	if [ $? -ne 0 ]; then
		fail "Ring Buffer Setting Failed"
		return 1
	fi
    sleep 1
}
set_txqueuelen_() {
	interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which net-tools) ]; then
		apt-get -y install net-tools
		if [ $? -ne 0 ]; then
			fail "net-tools Installation Failed"
			return 1
		fi
	fi
    ifconfig $interface txqueuelen 10000
    sleep 1
}
set_initial_congestion_window_() {
    iproute=$(ip -o -4 route show to default)
    ip route change $iproute initcwnd 25 initrwnd 25
}
disable_tso_() {
	interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which ethtool) ]; then
		apt-get -y install ethtool
		if [ $? -ne 0 ]; then
			fail "Ethtool Installation Failed"
			return 1
		fi
	fi
	ethtool -K $interface tso off gso off gro off
	sleep 1
	return 0
}


# Drive
set_disk_scheduler_() {
    i=1
    drive=()
    #List out all the available drives
    disk=$(lsblk -nd --output NAME)
	#Check if the disk is Set
	if [[ -z $disk ]]; then
		fail "Disk not found"
		return 1
	fi
    #Count the number of drives
    diskno=$(echo $disk | awk '{print NF}')
    #Putting the device name in an array to loop through later
    while [ $i -le $diskno ]
    do
	    device=$(echo $disk | awk -v i=$i '{print $i}')
	    drive+=($device)
	    i=$(( $i + 1 ))
    done
    i=1 x=0
    #Changing the scheduler per disk depending on whether they are HDD or SSD
    while [ $i -le $diskno ]
    do
	    diskname=$(eval echo ${drive["$x"]})
	    disktype=$(cat /sys/block/$diskname/queue/rotational)
	    if [ "${disktype}" == 0 ]; then		
		    echo kyber > /sys/block/$diskname/queue/scheduler
	    else
		    echo mq-deadline > /sys/block/$diskname/queue/scheduler
	    fi
    i=$(( $i + 1 )) x=$(( $x + 1 ))
    done
	return 0
}


# File Open Limit
set_file_open_limit_() {
	# return if $username is not Set
	if [[ -z $username ]]; then
		fail "Username not set"
		return 1
	fi
    cat << EOF >>/etc/security/limits.conf
## Hard limit for max opened files
$username        hard nofile 1048576
## Soft limit for max opened files
$username        soft nofile 1048576
EOF
	return 0
}


# Kernel Settings
kernel_settings_() {
	memory_size=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	#Define upper limit for TCP memory
	tcp_mem_min_cap=262144 #1GB
	tcp_mem_pressure_cap=2097152 #8GB
	tcp_mem_max_cap=4194304 #16GB

	if [ -n $memory_size ]; then
		#memory_size in terms of 4K pages
		memory_4k=$(( $memory_size / 4 ))
		#Calculate the TCP memory values
		if [ $memory_4k -gt  2000000 ]; then			#If memory is greater than 8GB
			tcp_mem_min=$(( $memory_4k / 16 )) && tcp_mem_pressure=$(( $memory_4k / 6 )) && tcp_mem_max=$(( $memory_4k / 6 ))
			rmem_max=536870912 && wmem_max=536870912 && win_scale=-2
		elif [ $memory_4k -gt 1000000 ]; then			#If memory is greater than 4GB
			tcp_mem_min=$(( $memory_4k / 16 )) && tcp_mem_pressure=$(( $memory_4k / 8 )) && tcp_mem_max=$(( $memory_4k / 8 ))
			rmem_max=268435456 && wmem_max=268435456 && win_scale=1
		elif [ $memory_4k -gt 250000 ]; then			#If memory is greater than 1GB
			tcp_mem_min=$(( $memory_4k / 32 )) && tcp_mem_pressure=$(( $memory_4k / 16 )) && tcp_mem_max=$(( $memory_4k / 8 ))
			rmem_max=67108864 && wmem_max=67108864 && win_scale=1
		elif [ $memory_4k -gt 125000 ]; then			#If memory is greater than 512MB
			tcp_mem_min=$(( $memory_4k / 32 )) && tcp_mem_pressure=$(( $memory_4k / 16 )) && tcp_mem_max=$(( $memory_4k / 8 ))
			rmem_max=16777216 && wmem_max=16777216 && win_scale=2
		else											#If memory is less than 512MB
			tcp_mem_min=$(( $memory_4k / 32 )) && tcp_mem_pressure=$(( $memory_4k / 16 )) && tcp_mem_max=$(( $memory_4k / 8 ))
			rmem_max=12582912 && wmem_max=12582912 && win_scale=2
		fi
		#Check if the calculated values are greater than the cap
		if [ $tcp_mem_min -gt $tcp_mem_min_cap ]; then
			tcp_mem_min=$tcp_mem_min_cap
		fi
		if [ $tcp_mem_pressure -gt $tcp_mem_pressure_cap ]; then
			tcp_mem_pressure=$tcp_mem_pressure_cap
		fi
		if [ $tcp_mem_max -gt $tcp_mem_max_cap ]; then
			tcp_mem_max=$tcp_mem_max_cap
		fi
		tcp_mem="$tcp_mem_min $tcp_mem_pressure $tcp_mem_max"
	else
		fail "Memory size not found"
		tcp_mem=$(cat /proc/sys/net/ipv4/tcp_mem)
		tcp_rmem=$(cat /proc/sys/net/ipv4/tcp_rmem)
		tcp_wmem=$(cat /proc/sys/net/ipv4/tcp_wmem)
		rmem_max=$(cat /proc/sys/net/core/rmem_max)
		wmem_max=$(cat /proc/sys/net/core/wmem_max)
		win_scale=$(cat /proc/sys/net/ipv4/tcp_adv_win_scale)
    fi
	#Set the values
	rmem_default=262144 && wmem_default=16384
	tcp_rmem="8192 $rmem_default $rmem_max" && tcp_wmem="4096 $wmem_default $wmem_max"
	#Check if all the variables are Set
	if [ -z $tcp_mem ]] || [[ -z $tcp_rmem ]] || [[ -z $tcp_wmem ]] || [ -z $rmem_max ] || [ -z $wmem_max ] || [ -z $win_scale ]; then
		fail "Kernel settings not set"
		return 1
	fi
    cat << EOF >/etc/sysctl.conf
###/proc/sys/fs/
##https://www.kernel.org/doc/Documentation/admin-guide/sysctl/fs.rst

# Maximum number of file-handles that the Linux kernel will allocate
fs.file-max = 1048576

# Maximum number of file-handles a process can allocate
fs.nr_open = 1048576







###/proc/sys/net/core - Network core options:
##https://www.kernel.org/doc/Documentation/admin-guide/sysctl/net.rst


# NOTE: Difference in polling and interrupt
#		-Interrupt: Interrupt is a hardware mechanism in which, the device notices the CPU that it requires its attention./
#			Interrupt can take place at any time. So when CPU gets an interrupt signal trough the indication interrupt-request line,/
#			CPU stops the current process and respond to the interrupt by passing the control to interrupt handler which services device.
#	    -Polling: In polling is not a hardware mechanism, its a protocol in which CPU steadily checks whether the device needs attention./
#			Wherever device tells process unit that it desires hardware processing, #in polling process unit keeps asking the I/O device whether or not it desires CPU processing./
#			The CPU ceaselessly check every and each device hooked up thereto for sleuthing whether or not any device desires hardware attention.
#	    The Linux kernel uses the interrupt-driven mode by default and only switches to polling mode when the flow of incoming packets exceeds "net.core.dev_weight" number of data frames
# The maximum number of packets that kernel can handle on a NAPI interrupt, it's a Per-CPU variable
#net.core.dev_weight = 64
# Scales the maximum number of packets that can be processed during a RX softirq cycle. Calculation is based on dev_weight (dev_weight * dev_weight_rx_bias)
#net.core.dev_weight_rx_bias = 1
# Scales the maximum number of packets that can be processed during a TX softirq cycle. Calculation is based on dev_weight (dev_weight * dev_weight_tx_bias)
#net.core.dev_weight_tx_bias = 1

# NOTE: If the second column of "cat /proc/net/softnet_stat" is huge, there are frame drops and it might be wise to increase the value of net.core.netdev_max_backlog/
#If the third column increases, there are SoftIRQ Misses and it might be wise to increase either or both net.core.netdev_budget and net.core.netdev_budget_usecs
# Maximum number of packets taken from all interfaces in one polling cycle (NAPI poll).
net.core.netdev_budget = 50000
# Maximum number of microseconds in one polling cycle (NAPI poll).
# NOTE: Could reduce if you have a CPU with high single core performance, NIC that supports RSS
# NOTE: Setting a high number might cause CPU to stall and end in poor overall performance
net.core.netdev_budget_usecs = 8000
# Maximum number  of  packets,  queued  on  the  INPUT  side, when the interface receives packets faster than kernel can process them
net.core.netdev_max_backlog = 100000

# Low latency busy poll timeout for socket reads
# NOTE: Not supported by most NIC
#net.core.busy_read=50
# Low latency busy poll timeout for poll and select
# NOTE: Not supported by most NIC
#net.core.busy_poll=50


# Receive socket buffer size
net.core.rmem_default = $rmem_default
net.core.rmem_max = $rmem_max

# Send socket buffer size
net.core.wmem_default = $wmem_default 
net.core.wmem_max = $wmem_max

# Maximum ancillary buffer size allowed per socket
# NOTE:Setting this value too high can lead to excessive kernel memory allocation for sockets, which might not be needed and could potentially waste system resources. 
# net.core.optmem_max = 20480







## IP
# System IP port limits
net.ipv4.ip_local_port_range = 1024 65535

# Allow Path MTU Discovery
net.ipv4.ip_no_pmtu_disc = 0




## ARP table settings
# The maximum number of bytes which may be used by packets queued for each unresolved address by other network layers
net.ipv4.neigh.default.unres_qlen_bytes = 16777216

# The maximum number of packets which may be queued for each unresolved address by other network layers
# NOTE: Deprecated in Linux 3.3 : use unres_qlen_bytes instead
#net.ipv4.neigh.default.unres_qlen = 1024




## TCP variables
# Maximum queue length of completely established sockets waiting to be accepted
net.core.somaxconn = 10000

#Maximum queue length of incomplete sockets i.e. half-open connection
#NOTE: THis value should not be above "net.core.somaxconn", since that is also a hard open limit of maximum queue length of incomplete sockets/
#Kernel will take the lower one out of two as the maximum queue length of incomplete sockets
net.ipv4.tcp_max_syn_backlog = 10000

# Recover and handle all requests instead of resetting them when system is overflowed with a burst of new connection attempts
net.ipv4.tcp_abort_on_overflow = 0

# Maximal number of TCP sockets not attached to any user file handle (i.e. orphaned connections), held by system.
# NOTE: each orphan eats up to ~64K of unswappable memory
net.ipv4.tcp_max_orphans = 131072

# Maximal number of time-wait sockets held by system simultaneously
net.ipv4.tcp_max_tw_buckets = 5000


# Enable TCP Packetization-Layer Path, and use initial MSS of tcp_base_mss
net.ipv4.tcp_mtu_probing = 2

# Starting MSS used in Path MTU discovery
net.ipv4.tcp_base_mss = 1460

#  Minimum MSS used in connection, cap it to this value even if advertised ADVMSS option is even lower
net.ipv4.tcp_min_snd_mss = 536


# Enable selective acknowledgments 
net.ipv4.tcp_sack = 1
# Send SACK more frequently
net.ipv4.tcp_comp_sack_delay_ns = 250000

# Allows TCP to send "duplicate" SACKs
net.ipv4.tcp_dsack = 1

# Enable Early Retransmit. ER lowers the threshold for triggering fast retransmit when the amount of outstanding data is small and when no previously unsent data can be transmitted
net.ipv4.tcp_early_retrans = 3

# Disable ECN
net.ipv4.tcp_ecn = 0

# Enable Forward Acknowledgment
# NOTE: This is a legacy option, it has no effect anymore
# net.ipv4.tcp_fack = 1


# TCP buffer size
# Values are measured in memory pages. Size of memory pages can be found by "getconf PAGESIZE". Normally it is 4096 bytes
# Vector of 3 INTEGERs: min, pressure, max
#	min: below this number of pages TCP is not bothered about its
#	memory appetite.
#
#	pressure: when amount of memory allocated by TCP exceeds this number
#	of pages, TCP moderates its memory consumption and enters memory
#	pressure mode, which is exited when memory consumption falls
#	under "min".
#
#	max: number of pages allowed for queuing by all TCP sockets
net.ipv4.tcp_mem = $tcp_mem

# TCP sockets receive buffer
# Vector of 3 INTEGERs: min, default, max
#	min: Minimal size of receive buffer used by TCP sockets.
#	It is guaranteed to each TCP socket, even under moderate memory
#	pressure.
#
#	default: initial size of receive buffer used by TCP sockets.
#	This value overrides net.core.rmem_default used by other protocols.
#
#	max: maximal size of receive buffer allowed for automatically
#	selected receiver buffers for TCP socket. This value does not override
#	net.core.rmem_max.  Calling setsockopt() with SO_RCVBUF disables
#	automatic tuning of that socket's receive buffer size, in which
#	case this value is ignored.
net.ipv4.tcp_rmem = $tcp_rmem

# Enable receive buffer auto-tuning
net.ipv4.tcp_moderate_rcvbuf = 1

# Distribution of socket receive buffer space between TCP window size(this is the size of the receive window advertised to the other end), and application buffer/
#The overhead (application buffer) is counted as bytes/2^tcp_adv_win_scale i.e. Setting this 2 would mean we use 1/4 of socket buffer space as overhead
# NOTE: Overhead reduces the effective window size, which in turn reduces the maximum possible data in flight which is window size*RTT
# NOTE: Overhead helps isolating the network from scheduling and application latencies
net.ipv4.tcp_adv_win_scale = $win_scale

# Max reserved byte of TCP window for application buffer. The value will be between window/2^tcp_app_win and mss
# See "https://www.programmersought.com/article/75001203063/" for more detail about tcp_app_win & tcp_adv_win_scale
# NOTE: This application buffer is different from the one assigned by tcp_adv_win_scale
# Default
# net.ipv4.tcp_app_win = 31

# TCP sockets send buffer
# Vector of 3 INTEGERs: min, default, max
#	min: Amount of memory reserved for send buffers for TCP sockets.
#	Each TCP socket has rights to use it due to fact of its birth.
#
#	default: initial size of send buffer used by TCP sockets.  This
#	value overrides net.core.wmem_default used by other protocols.
#	It is usually lower than net.core.wmem_default.
#
#	max: Maximal amount of memory allowed for automatically tuned
#	send buffers for TCP sockets. This value does not override
#	net.core.wmem_max.  Calling setsockopt() with SO_SNDBUF disables
#	automatic tuning of that socket's send buffer size, in which case
#	this value is ignored.
net.ipv4.tcp_wmem = $tcp_wmem


# Reordering level of packets in a TCP stream
# NOTE: Reordering is costly but it happens quite a lot. Instead of declaring packet lost and requiring retransmit, try harder to reorder first
# Initial reordering level of packets in a TCP stream. TCP stack can then dynamically adjust flow reordering level between this initial value and tcp_max_reordering
net.ipv4.tcp_reordering = 10
# Maximal reordering level of packets in a TCP stream
net.ipv4.tcp_max_reordering = 600


# Number of times SYNACKs for a passive TCP connection attempt will be retransmitted
net.ipv4.tcp_synack_retries = 10
# Number of times initial SYNs for an active TCP connection attempt	will be retransmitted
net.ipv4.tcp_syn_retries = 7

# In seconds, time default value for connections to keep alive
net.ipv4.tcp_keepalive_time = 7200
# How many keepalive probes TCP sends out, until it decides that the connection is broken
net.ipv4.tcp_keepalive_probes = 15
# In seconds, how frequently the probes are send out
net.ipv4.tcp_keepalive_intvl = 60

# Number of retries before killing a TCP connection
# Time, after which TCP decides, that something is wrong due to unacknowledged RTO retransmissions,	and reports this suspicion to the network layer.
net.ipv4.tcp_retries1 = 3
# Time, after which TCP decides to timeout the TCP connection, when RTO retransmissions remain unacknowledged
net.ipv4.tcp_retries2 = 10

# How many times to retry to kill connections on the other side before killing it on our own side
net.ipv4.tcp_orphan_retries = 2

#Disable TCP auto corking, as it needlessly increasing latency when the application doesn't expect to send more data
net.ipv4.tcp_autocorking = 0

# Disables Forward RTO-Recovery, since we are not operating on a lossy wireless network
net.ipv4.tcp_frto = 0

# Protect Against TCP TIME-WAIT Assassination
net.ipv4.tcp_rfc1337 = 1

# Avoid falling back to slow start after a connection goes idle
net.ipv4.tcp_slow_start_after_idle = 0

# Enable both client support & server support of TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Disable timestamps
net.ipv4.tcp_timestamps = 0

# Keep sockets in the state FIN-WAIT-2 for ultra short period if we were the one closing the socket, because this gives us no benefit and eats up memory
net.ipv4.tcp_fin_timeout = 5

# Enable cache metrics on closing connections
net.ipv4.tcp_no_metrics_save = 0

# Enable reuse of TIME-WAIT sockets for new connections
net.ipv4.tcp_tw_reuse = 1


# Allows the use of a large window (> 64 kB) on a TCP connection
net.ipv4.tcp_window_scaling = 1

# Set maximum window size to MAX_TCP_WINDOW i.e. 32767 in times there is no received window scaling option
net.ipv4.tcp_workaround_signed_windows = 1


# The maximum amount of unsent bytes in TCP socket write queue, this is on top of the congestion window
net.ipv4.tcp_notsent_lowat = 131072

# Controls the amount of data in the Qdisc queue or device queue
net.ipv4.tcp_limit_output_bytes = 3276800

# Controls a per TCP socket cache of one socket buffer
# Use Huge amount of memory
#net.ipv4.tcp_rx_skb_cache = 1

# Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
	return 0
}


# BBR
install_bbrx_() {
	#Check if $OS is Set
	if [[ -z $OS ]]; then
		# Linux Distro Version check
		if [ -f /etc/os-release ]; then
			. /etc/os-release
			OS=$NAME
		elif type lsb_release >/dev/null 2>&1; then
			OS=$(lsb_release -si)
		elif [ -f /etc/lsb-release ]; then
			. /etc/lsb-release
			OS=$DISTRIB_ID
		elif [ -f /etc/debian_version ]; then
			OS=Debian
		else
			OS=$(uname -s)
			VER=$(uname -r)
		fi
	fi
	if [[ "$OS" =~ "Debian" ]]; then
		if [ $(uname -m) == "x86_64" ]; then
			apt-get -y install linux-image-amd64 linux-headers-amd64
			if [ $? -ne 0 ]; then
				fail "BBR installation failed"
				return 1
			fi
		elif [ $(uname -m) == "aarch64" ]; then
			apt-get -y install linux-image-arm64 linux-headers-arm64
			if [ $? -ne 0 ]; then
				fail "BBR installation failed"
				return 1
			fi
		fi
	elif [[ "$OS" =~ "Ubuntu" ]]; then
		apt-get -y install linux-image-generic linux-headers-generic
		if [ $? -ne 0 ]; then
			fail "BBR installation failed"
			return 1
		fi
	else
		fail "Unsupported OS"
		return 1
	fi
	wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRx/BBRx.sh && chmod +x BBRx.sh
	# Check if download fail
	if [ ! -f BBRx.sh ]; then
		fail "BBR download failed"
		return 1
	fi
    ## Install tweaked BBR automatically on reboot
    cat << EOF > /etc/systemd/system/bbrinstall.service
[Unit]
Description=BBRinstall
After=network.target

[Service]
Type=oneshot
ExecStart=/root/BBRx.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable bbrinstall.service
	return 0
}

install_bbrv3_() {
	if [ $(uname -m) == "x86_64" ]; then
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-headers-6.4.0+-amd64.deb
		if [ ! -f linux-headers-6.4.0+-amd64.deb ]; then
			fail "BBRv3 download failed"
			return 1
		fi
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-image-6.4.0+-amd64.deb
		if [ ! -f linux-image-6.4.0+-amd64.deb ]; then
			fail "BBRv3 download failed"
			rm linux-headers-6.4.0+-amd64.deb
			return 1
		fi
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-libc-dev_-6.4.0-amd64.deb
		if [ ! -f linux-libc-dev_-6.4.0-amd64.deb ]; then
			fail "BBRv3 download failed"
			rm linux-headers-6.4.0+-amd64.deb linux-image-6.4.0+-amd64.deb
			return 1
		fi
		apt install ./linux-headers-6.4.0+-amd64.deb ./linux-image-6.4.0+-amd64.deb ./linux-libc-dev_-6.4.0-amd64.deb
		# Clean up
		rm linux-headers-6.4.0+-amd64.deb linux-image-6.4.0+-amd64.deb linux-libc-dev_-6.4.0-amd64.deb
	elif [ $(uname -m) == "aarch64" ]; then
		fail "ARM is Not supported for now"
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-headers-6.4.0+-arm64.deb
		if [ ! -f linux-headers-6.4.0+-arm64.deb ]; then
			fail "BBRv3 download failed"
			return 1
		fi
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-image-6.4.0+-arm64.deb
		if [ ! -f linux-image-6.4.0+-arm64.deb ]; then
			fail "BBRv3 download failed"
			rm linux-headers-6.4.0+-arm64.deb
			return 1
		fi
		wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-libc-dev_6.4.0-arm64.deb
		if [ ! -f linux-libc-dev_-6.4.0-amd64.deb ]; then
			fail "BBRv3 download failed"
			rm linux-headers-6.4.0+-arm64.deb linux-image-6.4.0+-arm64.deb
			return 1
		fi
		apt install ./linux-headers-6.4.0+-arm64.deb ./linux-image-6.4.0+-arm64.deb ./linux-libc-dev_6.4.0-arm64.deb
		# Clean up
		rm linux-headers-6.4.0+-arm64.deb linux-image-6.4.0+-arm64.deb linux-libc-dev_-6.4.0-amd64.deb
	else
		fail "$(uname -m) is not supported"
	fi
	return 0
}



