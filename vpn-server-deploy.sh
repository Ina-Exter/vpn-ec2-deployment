#!/bin/bash

#Disclaimer
echo "Note that this will require sudo. If you are running this on an AWS EC2 instance, it should not ask for a password."

sleep 5

#Dependancies
sudo apt update
sudo apt install openvpn -y

#Install EasyRSA
cd 
wget -P ~/ https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
tar xvf EasyRSA-unix-v3.0.6.tgz
file=EasyRSA-v3.0.6


#CA handling
echo "This will install the CA on the SAME machine. This is a big security risk, but if you are the single user on your VPN, it should be fine. If you do not want to install the CA here, you will have to do it manually."
echo "Type \"yes\" to install the CA here."
read -r answer
if [[ "$answer" == "yes" ]]
then
	cp "$file/vars.example" "$file/vars"
	./$file/easyrsa init-pki
	echo "You will need to confirm data about your CA. This is not necessarily relevant, enter whatever."
	echo "It is recommanded to put a passphrase on your CA. Would you like one? You may have to type it several times during the script."
	read -r answer
	if [[ "$answer" == "yes" ]]
	then
		./$file/easyrsa build-ca
	else
		./$file/easyrsa build-ca nopass
	fi
	
	#Server request
	./$file/easyrqa gen-req server nopass
	sudo cp $file/pki/private/server.key /etc/openvpn
	./$file/easyrsa sign-req server server
	sudo cp $file/pki/issued/server.crt /etc/openvpn
	sudo cp $file/pki/ca.crt /etc/openvpn

	#Diffie-Hellmann key
	./$file/easyrsa gen-dh
	openvpn --genkey --secret ta.key
	sudo cp $file/ta.key /etc/openvpn
	sudo cp $file/pki/dh.pem /etc/openvpn

	#Client certificate
	mkdir -p client-configs/key
	chmod -R 700 client-configs
	echo "Choose a name for your client."
	read -r clientname
	./$file/easyrsa gen-req $clientname nopass
	cp $file/pki/private/$clientname.key client-configs/keys/
	./$file/easyrsa sign-req client $clientname
	cp $file/pki/issued/$clientname.crt client-configs/keys/
fi

