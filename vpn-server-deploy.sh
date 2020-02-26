#!/bin/bash

#Disclaimer
echo "Note that this will require sudo. If you are running this on an AWS EC2 instance, it should not ask for a password."

sleep 5

#Dependancies
sudo apt update
sudo apt install openvpn openssl -y

#Install EasyRSA
cd || exit
wget -P ~/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
tar xvf EasyRSA-unix-v3.0.6.tgz
file=EasyRSA-v3.0.6

cd $file

#CA handling
echo "This will install the CA on the SAME machine. This is a big security risk, but if you are the single user on your VPN, it should be fine. If you do not want to install the CA here, you will have to do it manually."
echo "Type \"yes\" to install the CA here."
read -r answer
if [[ "$answer" == "yes" ]]
then
	cp vars.example vars
	./easyrsa init-pki
	echo "You will need to confirm data about your CA. This is not necessarily relevant, enter whatever."
	echo "It is recommanded to put a passphrase on your CA. Would you like one? You may have to type it several times during the script."
	read -r answer
	if [[ "$answer" == "yes" ]]
	then
		./easyrsa build-ca
	else
		./easyrsa build-ca nopass
	fi
	
	#Server request
	./easyrsa gen-req server nopass
	sudo cp ~/$file/pki/private/server.key /etc/openvpn
	./easyrsa sign-req server server
	sudo cp ~/$file/pki/issued/server.crt /etc/openvpn
	sudo cp ~/$file/pki/ca.crt /etc/openvpn

	#Diffie-Hellmann key
	./easyrsa gen-dh
	openvpn --genkey --secret ta.key
	sudo cp ~/$file/ta.key /etc/openvpn
	sudo cp ~/$file/pki/dh.pem /etc/openvpn

	#Client certificate
	mkdir -p ~/client-configs/keys
	chmod -R 700 ~/client-configs
	echo "Choose a name for your client."
	read -r clientname
	./easyrsa gen-req "$clientname" nopass
	cp ~/$file/pki/private/$clientname.key ~/client-configs/keys/
	./easyrsa sign-req client "$clientname"
	cp ~/$file/pki/issued/$clientname.crt ~/client-configs/keys/
	cp ~/$file/ta.key ~/client-configs/keys/
	sudo cp /etc/openvpn/ca.crt ~/client-configs/keys/

	#OVPN service conf
	sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/
	sudo gzip -d /etc/openvpn/server.conf.gz

	#Edit /etc/openvpn/server.conf

	sudo sed -i "s/;tls-auth ta.key 0/tls-auth ta.key 0/" /etc/openvpn/server.conf
	sudo sed -i "/cipher AES-256-CBC/ a auth SHA256" /etc/openvpn/server.conf
	sudo sed -i "s/dh dh2048.pem/dh dh.pem/" /etc/openvpn/server.conf
	sudo sed -i "s/;user nobody/user nobody/" /etc/openvpn/server.conf
	sudo sed -i "s/;group nogroup/group nogroup/" /etc/openvpn/server.conf
	sudo sed -i 's/;push "redirect-gateway def1 bypass-dhcp"/push "redirect-gateway def1 bypass-dhcp"/' /etc/openvpn/server.conf
	sudo sed -i 's/;push "dhcp-option DNS 208.67.222.222"/push "dhcp-option DNS 208.67.222.222"/' /etc/openvpn/server.conf
	sudo sed -i 's/;push "dhcp-option DNS 208.67.220.220"/push "dhcp-option DNS 208.67.220.220"/' /etc/openvpn/server.conf

	#Port adjustment
	echo "You will have to select a port and protocol for the VPN. Popular choices include port udp/1194 (but might require port-forwarding on your router) or tcp/443 (default value in this script). If you do not know what you are doing, go for tcp/443. Otherwise, you can select your own protocol with \"proto\"/\"port\" and the script will use this."
	read -r protoport
	if [[ "${protoport:3:1}" != "/" ]]
	then
		echo "Empty variable or bad structure, using default."
		port="443"
		proto="tcp"
	else
		proto=${protoport:0:3}
		port=${protoport:4}
	fi
	if [[ "$proto" != "tcp" ]] && [[ "$proto" != "udp" ]]
	then
		echo "Invalid protocol, using tcp"
		proto="tcp"
	fi
	if [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]
	then
		echo "Invalid port number (must be in range 1, 65535), using default"
		port="443"
	fi
	
	#Replace protocol and port
	sudo sed -i "s/port 1194/port $port/" /etc/openvpn/server.conf
	sudo sed -i "s/proto udp/proto $proto/" /etc/openvpn/server.conf

	if [[ "$proto" != "tcp" ]]
	then
		sudo sed -i "s/explicit-exit-notify 1/explicit-exit-notify 0/" /etc/openvpn/server.conf
	fi

	#Server network configuration
	sudo sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/" /etc/sysctl.conf
	sudo sysctl -p

	#Discover network interface
	IFS=' '
	interfaces=$(ip route |grep default)
	next=0
	for x in $interfaces
	do
		if [[ "$next" -eq 1 ]]
		then
			netinterface="$x"
			break
		fi
		#messy but whatever.
		if [[ "$x" == "dev" ]]
		then 
			next=1
		fi

	done
	unset IFS

	#Write ufw settings
	sudo tee /etc/ufw/before.rules <<EOF >/dev/null
# START OPENVPN RULES
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
# Allow traffic from OpenVPN client to $netinterface
-A POSTROUTING -s 10.8.0.0/8 -o $netinterface -j MASQUERADE
COMMIT
# END OPENVPN RULES
EOF

	sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

	sudo ufw allow $port/$proto
	sudo ufw allow OpenSSH

	sed -i "s/;user nobody/user nobody/" ~/client-configs/base.conf
	sed -i "s/;group nogroup/group nogroup/" ~/client-configs/base.conf
	sed -i "s/ca ca.crt/#ca ca.crt/" ~/client-configs/base.conf
	sed -i "s/cert client.crt/#cert client.crt/" ~/client-configs/base.conf
	sed -i "s/key client.key/#key client.key/" ~/client-configs/base.conf
	sed -i "s/tls-auth ta.key 1/#tls-auth ta.key 1/" ~/client-configs/base.conf
	sed -i "cipher AES-256-CBC/a auth SHA256" ~/client-configs/base.conf
	
	{

		echo "key-direction 1"

		echo "#Uncomment if linux client with /etc/openvpn/update-resolv-conf"
		echo "# script-security 2"
		echo "# up /etc/openvpn/update-resolv-conf"
		echo "# down /etc/openvpn/update-resolv-conf"
	} >> ~/client-configs/base.conf

	cat << 'EOF' > client-configs/make_config.sh
#!/bin/bash

# First argument: Client identifier

KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-auth>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-auth>') \
    > ${OUTPUT_DIR}/${1}.ovpn
EOF

	chmod u+x ~/client-configs/make_config.sh

	echo "Setup completed. Run \"sudo ./make_config.sh [CLIENT_NAME]\" in directory \"client-configs\" to create a [CLIENT_NAME].ovpn file, and send it to the client."
fi

