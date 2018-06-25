# Enumivo firewall script

WARNING: The script wipes all existing rules and add SSH (22) plus BP IPs in ACCEPT rule. Please
add reset_fw.sh script into crontab to be executed every x minutes in case you get locked out.
ALL script should be executed as root otherwise will exit.
crontab rule executed every 10th minute: 
*/10 * * * bash /path/to/reset_fw.sh

Firewall script that automatically configures iptables rules. Based on provided list the script
creates rules for each entry or updates them accordingly.
The list should have the following format (delimiter is | ):
BP_IP|BP_NAME

Changelog:
- Implemented IPv4 / Hostname verification
- Multiple ports are now parsed and rules are added accordingly. Every host will have an ACCEPT
rule for each port.
