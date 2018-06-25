#!/bin/basAh
# Clean everything
if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit 5
fi

IPT='/sbin/iptables'
# !! WARNING !! The following lines will wipe every iptables rules that you might have.
# IF you use docker or any software that uses iptables comment them and make your own cleanup
${IPT} -F
${IPT} -t nat --flush
# Delete all chains that are not in default filter and nat table
${IPT} --delete-chain
${IPT} -t nat --delete-chain

