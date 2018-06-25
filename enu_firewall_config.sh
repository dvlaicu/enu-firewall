#!/bin/bash
# ENU firewall configuration
# This script should be executed as root prefferably by cron.
# Use this with caution. I highly advice in setting a root cron rule 
# to wipe clean rules buit by this script in case of lockout.
# To do that please use crontab line:
# */10 * * * * bash /path/to/reset_fw.sh
# Dragos Vlaicu - 25.06.2018 - BP: dragosvlaicu

# Script needs to be executed at root otherwise iptables will fail to do anything
if [ "$EUID" -ne 0 ]
    then 
    log_all "Please run as root"
    exit 5
fi

# variables built with absolute path. Cron won't complain about not finding any in its path.
IPT='/sbin/iptables'
GREP='/bin/grep'
AWK='/usr/bin/awk'
HOST='/usr/bin/host'
ECHO='/bin/echo'
DATE='/bin/date'
ports='22 9000 8000'
SSH_PORT='22'
SSH_ALLOW='0.0.0.0/0'
IPT_LIST="$(${IPT} --line-numbers -nL INPUT)"
SCRIPT="$(readlink -f $0)"
BASEDIR="$(dirname ${SCRIPT})"
LIST="${BASEDIR}/enu_bp_nodes"
LOG="${BASEDIR}/log.txt"


function log_all(){
    if [[ ! -f ${LOG} ]]; then
        touch ${LOG}
        if [[ $? -ne 0 ]]; then
            echo "Unable to create the log file. Exiting..."
            exit 10
        fi
    fi
    
    MESSAGE=$@
    TIMESTAMP="$(${DATE} '+[%Y-%m-%d %H:%M:%S]')"
    echo "${TIMESTAMP} ${MESSAGE}" >> ${LOG}
}

# verify if it's an IP or hostname
function valid_ip()
{
    local BP=$1
    # Regex for checking the format numbers and dots
    if [[ $BP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($BP)
        IFS=$OIFS
        # check if the numbers are really under 256 and potentially be an IP part.
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        if [[ $? -eq 0 ]]; then 
            IP_BP=${BP}
        fi
    else
        # We are hoping for the best and moving along by checking the hostname.
        IP_BP="$(${HOST} ${BP} | ${AWK} 'NR==1 {print $4}')"
    fi
    echo "$IP_BP"
}

# !! WARNING !! The following lines will wipe every iptables rules that you might have.
# IF you use docker or any software that uses iptables comment them and make your own cleanup
# Accept traffic from loopback interface
LOStatus=$(${ECHO} "${IPT_LIST}" | ${AWK} '/Loopback Inteface/ {print $5}')
if [[ -z ${LOStatus} ]]; then
    ${IPT} -A INPUT -i lo -m comment --comment "Loopback Inteface" -j ACCEPT
    ${IPT} -A OUTPUT -o lo  -m comment --comment "Loopback Inteface" -j ACCEPT
    # Allow initiated traffic to pass thru
    ${IPT} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Add the allow rule for ssh port from everyone (this can pe tweaked later to accept access only from particular IPs)
    #${IPT} -A INPUT -s ${SSH_ALLOW} -p tcp --dport ${SSH_PORT} -m comment --comment "SSH Allow Rule from [${SSH_ALLOW}]" -j ACCEPT
    # Drop everything besides the ssh and p2p traffic that will be addded later on.
    ${IPT} -A INPUT -s 0.0.0.0/0 -m comment --comment "Drop any traffic outside the rules" -j DROP
fi

for PORT in ${ports}; do
    for BP in $(${GREP} -Ev "^$|^#" ${LIST} | ${AWK} -F "|" '{print $2}'); do
        # Grab the IP for the BP from the iptables rules
        IP_IPTABLES="$(${ECHO} "${IPT_LIST}" | ${AWK} '/'${PORT}_${BP}'/ {print $5}')"
        IP_GIT="$(${AWK} -F "|" '$2 == "'${BP}'" {print $1}' ${LIST})"
        # check if we're dealing with a hostname or IPv4 address
        IP_GIT=$(valid_ip "${IP_GIT}")
        
        if [[ -z ${IP_IPTABLES} ]]; then
            ${IPT} -I INPUT 1 -s ${IP_GIT} -p tcp --dport ${PORT} -m comment --comment "${PORT}_${BP}" -j ACCEPT
            log_all "The rule for [${BP} -> ${IP_GIT}] was added successfully."
        else
            if [[ "${IP_IPTABLES}" != "${IP_GIT}" ]]; then
                No_IPTABLES="$(${ECHO} "${IPT_LIST}" | ${AWK} '/'${BP}'/ {print $1}')"
                ${IPT} -R INPUT ${No_IPTABLES} -s ${IP_GIT} -p tcp --dport ${PORT} -m comment --comment "${PORT}_${BP}" -j ACCEPT
                log_all "The rule for [${BP} -> ${IP_GIT}] updated successfully."
            fi
        fi
    done
done
