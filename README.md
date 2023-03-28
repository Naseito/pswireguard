# pswireguard

PowerShell helper script for creating wireguard VPN server and client configuration. Only for IPv4. Feel free to fork and adapt to your needs. As I wanted to be as simple as possible, the basic up and down rules are created with ufw.

## Basics

The script behave slightly different depending on the OS.

- **Windows:** Creates config files for server, clients and qr codes for the clients
- **Any Linux or Ubuntu with no root user:** Creates config files for server, clients and qr codes for the clients
- **Ubuntu with root user:** Creates config files for server, clients and qr codes for the clients. Installs wireguard, copy the config files to /etc/wireguard and enables/starts the service.

## Parameters

### Mandatory

- **IPv4ServerAddress:** [String] The address space (without netmask) for the wireguard virtual network. Eg: "10.44.0.0"
- **IPv4NetMask:** [Int] The netmask for the wireguard virtual network. Eg: 24
- **IPv4DNS:** [String] The IP address of your internal DNS server. Eg: "10.40.0.250"
- **IPv4UDPPort:** [String] The port where the wireguard server will listen to Eg: "51820"  
- **InterfaceName:** [String] Name of the interface of the machine where wireguard will route to. Eg: "eth0"
- **ServerEndpointName:** [String] Extermal IPv4/FQDN for the VPN Server. Eg: "vpn.somedomain.com"
- **LicensesToGenerate:** [Int] Enter the number of config files for clients that you would like to generate. Limited by the number of possible hosts with the IPv4ServerAddress/IPv4NetMask combination Eg: 10

### Optional

- **OnlyLANRouting:** [Switch] If this parameter is passed, LANRoutingSubnet will be used in the client config files to limit the cliens "Allowed Ips". If this is not passed all clients will be created with "Allowed Ips" set to 0.0.0.0/0.
- **LANRoutingSubnet:** [String] Enter the subnet desired for VPN routing with CIDR format. Requires OnlyLANRouting to be effective. Eg: "10.40.0.0/24"
- **Verbose:** For a better output of the script.

### Example

From a PowerShell terminal:

``` PowerShell
./Get-WireguardLicenses.ps1 -IPv4ServerAddress "10.44.0.0" -IPv4NetMask 24 -IPv4DNS "10.40.0.250" -IPv4UDPPort "51820" -ServerEndpointName "vpn.somedomain.com" -LicensesToGenerate 10 -OnlyLANRouting -LANRoutingSubnet "10.40.0.0/24" -Verbose
```

### Resulting files

| File | Description |
| ----------- | ----------- |
| client*.conf | These are the files that you will later need to import to your clients. |
| client*.png | QR codes with client configuration in png format for easy sharing. |
| wg0.conf | This file has the configuration of the wireguard server. In Ubuntu it should be place in /etc/wireguard/ -- Also the name of the file will be used later for enabling/start/stop/restart the service (Eg: systemctl start wg-quick@wg0.service)|
| up.sh | The script that will be run when starting the wireguard server. In Ubuntu it should be place in /etc/wireguard/ -- Read the routing section of this readme file for more information. |
| down.sh | The script that will be run when stopping the wireguard server. In Ubuntu it should be place in /etc/wireguard/ -- Read the routing section of this readme file for more information. |
| .pub and .key | The public and private certificates used for generating the configuration. Please store them safely. |

## Routing

### Default routing

If you are using ubuntu and running the script as root, everything necessary to do the basic routing will be done automatically. In case you are running it in another Linux distro or another user than root, here is what you need to do:

- Uncomment the line #net.ipv4.ip_forward=1 on /etc/sysctl.conf
- Copy up.sh and down.sh to a location of your desire. Change in wg0.conf the path for the scripts and don´t forget to give execution permissions to the scripts.

>chmod +x /etc/wireguard/up.sh && chmod +x /etc/wireguard/down.sh

- Enable and start the service:

>systemctl enable wg-quick@wg0.service && systemctl start wg-quick@wg0.service

The default routing will allow all traffic between the host interface and the wireguard interface:

`ufw route insert 1 allow in on wg0 out on eth0`

`ufw route insert 1 allow in on eth0 out on wg0`

### Advance routing

With ufw is quite easy to create custom routing rules. You may want some clients to have full access (your LAN + Internet), others to have only restricted access to some of your LAN services, and maybe others with Internet redirection but no access to the LAN. I will provide some examples, but the most important thing is the order of the rules. Rules are executed by order, if the order is not correct the routing may fail (that´s the reason why I use ufw route insert 1, to always put the rule in the first place).

**Put the rules in up.sh in reverse order**  (the first ones in up.sh will be the last to be checked on ufw rule list)

The first two rules should be:

Allow all routing from host interface to wireguard interface:

`ufw route insert 1 allow in on eth0 out on wg0`

Deny all routing from wireguard interface to host interface:

`ufw route insert 1 deny in on wg0 out on eth0`

Allow all wireguard clients to communicate with the DNS server (10.40.0.250):

`ufw route insert 1 allow in on wg0 out on enp3s0 to 10.40.0.250 port 53 from 10.44.0.0/24`

Allow one client (10.44.0.3) to communicate with the LAN and also routing internet:

`ufw route insert 1 allow in on wg0 out on eth0 to any from 10.44.0.3`

Allow a specific client (10.44.0.2) to access a NAS with SMB (10.40.0.4) and then block the rest of the routing to the LAN.

`ufw route insert 1 deny in on wg0 out on eth0 to 10.40.0.0/24`

`ufw route insert 1 allow in on wg0 out on eth0 to 10.40.0.4 port 445 from 10.44.0.2`

Then copy the same rules on down.sh replacing **"insert 1"** by **"delete"**.
