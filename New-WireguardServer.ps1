param ([parameter(Mandatory = $true, HelpMessage = "IPv4 Address of Wireguard server without netmask.")][string] $IPv4ServerAddress,
    [parameter(Mandatory = $true, HelpMessage = "Netmask of the wireguard server.Accept values from 0 to 32")][Int32] $IPv4NetMask,
    [parameter(Mandatory = $true, HelpMessage = "IPv4 Address of the DNS server that will be forwarded to the VPN client")][string] $IPv4DNS,
    [parameter(Mandatory = $true, HelpMessage = "Port where Wireguard will listen. Don´t forget to open the port in your router!")][string] $IPv4UDPPort,
    [parameter(Mandatory = $true, HelpMessage = "The MTU for the wg adapter Make sure is the same used by your ISP.")][string] $MTU = "1420",
    [parameter(Mandatory = $true, HelpMessage = "Name of the interface of the machine where wireguard will route to. Eg: eth0")][string] $InterfaceName,
    [parameter(Mandatory = $true, HelpMessage = "External IPv4/FQDN for the VPN Server. Eg: vpn.somedomain.com")][string] $ServerEndpointName,
    [parameter(Mandatory = $true, HelpMessage = "Enter the number of config files for clients that you would like to generate")][Int32] $LicensesToGenerate,
    [parameter(ParameterSetName = 'Routing', HelpMessage = "If set, you will be allowed to enter the subnet desired for VPN routing using parameter -LANRoutingSubnet with CIDR format")][switch] $OnlyLANRouting,
    [parameter(ParameterSetName = 'Routing', HelpMessage = "Enter the subnet desired for VPN routing with CIDR format.Eg: 10.33.0.0/16")][string] $LANRoutingSubnet
)

# Dependencies

if (Get-Module -ListAvailable -Name Subnet) {
    Write-Host "Subnet Module exists on the system" -ForegroundColor Green
    Import-Module Subnet 
    
} 
else {
    Write-Host "Subnet module not present. Installing..." -ForegroundColor Yellow
    Install-Module Subnet -AllowClobber -Confirm:$False -Force
    Import-Module Subnet
}
if (Get-Module -ListAvailable -Name QRCodeSt) {
    Write-Host "Subnet Module exists on the system" -ForegroundColor Green
    Import-Module QRCodeSt
        
} 
else {
    Write-Host "QRCodeSt module not present. Installing..." -ForegroundColor Yellow
    Install-Module QRCodeSt -AllowClobber -Confirm:$False -Force
    Import-Module QRCodeSt
}

if ($IsLinux -and $PSVersionTable.OS -like "*Ubuntu*" -and $(Get-ChildItem Env:\USER).Value -eq "root") {
    apt install wireguard -y
}

#Calculate subnet
$networkInfo = Get-Subnet -IP $IPv4ServerAddress -MaskBits $IPv4NetMask

# Checks if parameters received are correct

## Checks that $IPv4ServerAddress, $IPv4NetMask and $IPv4DNS are actual IPv4 addresses 
$IPpattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
if ($IPv4ServerAddress -notmatch $IPpattern -or $IPv4DNS -notmatch $IPpattern) {
    Write-Error "Either $IPv4ServerAddress or $IPv4DNS dont comply with the IPv4 format. Exiting script..."
    Exit 
}

if ($IPv4NetMask -notin 0..32) {
    Write-Error "Incorrect Network Mask. Exiting script..." 
    Exit 
}

## Checks that there are enough IPs on the subnet for the number of licenses desired.

if ($LicensesToGenerate -gt $networkInfo.HostAddressCount) {
    Write-Error "The number of licenses to generate ($LicensesToGenerate) is higher than the available host address for the subnet ($($networkInfo.HostAddressCount)). Exiting script..."
    Exit
}



Write-Verbose "Generating qrcode for $($configFile.Name)"
if ($IsLinux) {
    # Public, Private and Preshare Key Generation - Server Side
    bash -c  "wg genkey > Sprivatekey.key"
    bash -c  "wg pubkey < Sprivatekey.key > Spublickey.pub"
    bash -c  "wg genpsk > sharedkey.key"
    # Creating Interface - Server Side
    bash -c  "wg genkey | tee wg-private.key | wg pubkey > wg-public.key"
}
elseif ($IsWindows) {
    # Public, Private and Preshare Key Generation - Server Side
    cmd /c  "wg genkey > Sprivatekey.key"
    cmd /c  "wg pubkey < Sprivatekey.key > Spublickey.pub"
    cmd /c  "wg genpsk > sharedkey.key"
    # Creating Interface - Server Side
    wg genkey | Tee-Object "wg-private.key" | wg pubkey | Out-File "wg-public.key"
}

# Create config file (if needed)
if (-Not (Test-Path "wg0.conf")) {
    New-Item "wg0.conf" -Force
}

Add-Content -Path "wg0.conf" -Value "[Interface]"
Add-Content -Path "wg0.conf" -Value "Address = $IPv4ServerAddress/$IPv4NetMask"
Add-Content -Path "wg0.conf" -Value "MTU = $MTU"
Add-Content -Path "wg0.conf" -Value "SaveConfig = true"
Add-Content -Path "wg0.conf" -Value 'PostUp = /etc/wireguard/up.sh'
Add-Content -Path "wg0.conf" -Value 'PostDown = /etc/wireguard/down.sh'
Add-Content -Path "wg0.conf" -Value "ListenPort = $IPv4UDPPort"
Add-Content -Path "wg0.conf" -Value $("PrivateKey = " + $(Get-Content  -Path "Sprivatekey.key"))
Add-Content -Path "wg0.conf" -Value "#"

For ($i = 1; $i -le $LicensesToGenerate + 1; $i++) {
    Write-Verbose "Generating license number $($i+1)"
    
    #Generate keys for client interface
    Write-Verbose "Generating qrcode for $($configFile.Name)"
    if ($IsLinux -eq $true) {
        bash -c "wg genkey > Cprivatekey.key"
        bash -c "wg pubkey < Cprivatekey.key > Cpublickey.pub"
    }
    elseif ($IsWindows -eq $true) {
        cmd /c "wg genkey > Cprivatekey.key"
        cmd /c "wg pubkey < Cprivatekey.key > Cpublickey.pub"
    }


    #Adding peer to server config file
    Add-Content -Path "wg0.conf" -Value "[Peer]"
    Add-Content -Path "wg0.conf" -Value "# client $i"
    Add-Content -Path "wg0.conf" -Value $("PublicKey = " + $(Get-Content Cpublickey.pub))
    Add-Content -Path "wg0.conf" -Value $("PresharedKey = " + $(Get-Content sharedkey.key))
    Add-Content -Path "wg0.conf" -Value $("AllowedIPs = " + "$($networkInfo.HostAddresses[$i])/32")
    Add-Content -Path "wg0.conf" -Value "#"       
    Add-Content -Path "wg0.conf" -Value "#"

    #Client config generation
    New-Item -Path "client$($i+1).conf" -Force
    Add-Content -Path "client$($i+1).conf" -Value "[Interface]"
    Add-Content -Path "client$($i+1).conf" -Value $("Address =" + "$($networkInfo.HostAddresses[$i])/$IPv4NetMask")
    Add-Content -Path "client$($i+1).conf" -Value $("PrivateKey = " + $(Get-Content Cprivatekey.key))
    Add-Content -Path "client$($i+1).conf" -Value "MTU = $MTU"
    Add-Content -Path "client$($i+1).conf" -Value $("DNS = " + $IPv4DNS)
    Add-Content -Path "client$($i+1).conf" -Value "#"
    Add-Content -Path "client$($i+1).conf" -Value "[Peer]"
    Add-Content -Path "client$($i+1).conf" -Value $("PublicKey = " + $(Get-Content Spublickey.pub))
    Add-Content -Path "client$($i+1).conf" -Value $("PresharedKey = " + $(Get-Content sharedkey.key))
    if ($OnlyLANRouting) {
        Add-Content -Path "client$($i+1).conf" -Value "AllowedIPs = $LANRoutingSubnet"
    }
    else {
        Add-Content -Path "client$($i+1).conf" -Value "AllowedIPs = 0.0.0.0/0"
    }
    Add-Content -Path "client$($i+1).conf" -Value "Endpoint = $($ServerEndpointName):$($IPv4UDPPort)"
    Add-Content -Path "client$($i+1).conf" -Value "#"
}

# Create QR codes for each client config file
$configFiles = Get-ChildItem | Where-Object { $_.Name -like "client*" }
foreach ($configFile in $configFiles) {
    Write-Verbose "Generating qrcode for $($configFile.Name)"
    New-QRCodeSt -Info $($(Get-Content $configFile.FullName | Out-String)) -OutPath "$(Get-Location)\$($configFile.Name).png"  
}

# Create up and down files (if needed)
if (-Not (Test-Path "up.sh")) {
    New-Item "up.sh" -Force
}
if (-Not (Test-Path "down.sh")) {
    New-Item "down.sh" -Force
}
Add-Content -Path "up.sh" -Value "ufw route insert 1 allow in on wg0 out on $InterfaceName"
Add-Content -Path "up.sh" -Value "ufw route insert 1 allow in on $InterfaceName out on wg0"
Add-Content -Path "down.sh" -Value "ufw route delete allow in on wg0 out on $InterfaceName"
Add-Content -Path "down.sh" -Value "ufw route delete allow in on $InterfaceName out on wg0"

# If you are on a Ubuntu machine/vm, copy the files and enable the service. Needs root user.
if ($IsLinux -and $PSVersionTable.OS -like "*Ubuntu*" -and $(Get-ChildItem Env:\USER).Value -eq "root") {
    Copy-Item -Path "up.sh" -Destination "/etc/wireguard/" -Force
    Copy-Item -Path "down.sh" -Destination "/etc/wireguard/" -Force
    Copy-Item -Path "wg0.conf" -Destination "/etc/wireguard/" -Force
    chmod +x /etc/wireguard/up.sh
    chmod +x /etc/wireguard/down.sh
    (Get-Content -Path /etc/sysctl.conf) | ForEach-Object { $_ -replace '^#\s*net.ipv4.ip_forward=1', 'net.ipv4.ip_forward=1' } | Set-Content -Path /etc/sysctl.conf
    systemctl enable wg-quick@wg0.service
    systemctl start wg-quick@wg0.service
}
