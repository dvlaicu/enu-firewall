#!/bin/bash
# ENU firewall configuration
# This script should be executed as root prefferably by cron.
# Use this with caution. I highly advice in setting a root cron rule 
# to wipe clean rules buit by this script in case of lockout.
# To do that please use crontab line:
# */10 * * * * bash /path/to/reset_fw.sh
# Dragos Vlaicu - 25.06.2018 - BP: dragosvlaicu

IPT='/sbin/iptables'
GREP='/bin/grep'
AWK='/usr/bin/awk'
ECHO='/bin/echo'
DATE='/bin/date'
P2P_PORT='9000'
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

if [ "$EUID" -ne 0 ]
    then 
    log_all "Please run as root"
    exit 5
fi

# Clean everything
# !! WARNING !! The following lines will wipe every iptables rules that you might have.
# IF you use docker or any software that uses iptables comment them and make your own cleanup
${IPT} -F
${IPT} -t nat --flush
# Delete all chains that are not in default filter and nat table
${IPT} --delete-chain
${IPT} -t nat --delete-chain
# Accept traffic from loopback interface
${IPT} -A INPUT -i lo -m comment --comment "Loopback Inteface" -j ACCEPT
${IPT} -A OUTPUT -o lo  -m comment --comment "Loopback Inteface" -j ACCEPT
# Allow initiated traffic to pass thru
${IPT} -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT



# Add the allow rule for ssh port from everyone (this can pe tweaked later to accept access only from particular IPs)
${IPT} -A INPUT -s ${SSH_ALLOW} -p tcp --dport ${SSH_PORT} -m comment --comment "SSH Allow Rule from [${SSH_ALLOW}]" -j ACCEPT
# Drop everything besides the ssh and p2p traffic that will be addded later on.
${IPT} -A INPUT -s 0.0.0.0/0 -m comment --comment "Drop any traffic outside the rules" -j DROP

for BP in $(${GREP} -Ev "^$|^#" ${LIST} | ${AWK} -F "|" '{print $2}'); do
    # Grab the IP for the BP from the iptables rules
    IP_IPTABLES="$(${ECHO} "${IPT_LIST}" | ${AWK} '/'${BP}'/ {print $5}')"
    IP_GIT="$(${AWK} -F "|" '$2 == "'${BP}'" {print $1}' ${LIST})"
    
    if [[ -z ${IP_IPTABLES} ]]; then
        ${IPT} -I INPUT 1 -s ${IP_GIT} -p tcp --dport ${P2P_PORT} -m comment --comment "${BP}" -j ACCEPT
        log_all "The rule for [${BP} -> ${IP_GIT}] was added successfully."
    else
        if [[ "${IP_IPTABLES}" != "${IP_GIT}" ]]; then
            No_IPTABLES="$(${ECHO} "${IPT_LIST}" | ${AWK} '/'${BP}'/ {print $1}')"
            ${IPT} -R INPUT ${No_IPTABLES} -s ${IP_GIT} -p tcp --dport ${P2P_PORT} -m comment --comment "${BP}" -j ACCEPT
            log_all "The rule for [${BP} -> ${IP_GIT}] updated successfully."
        fi
    fi
done
