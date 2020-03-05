#!/bin/bash

echo "Required: ssh, scp, awscli."
echo "Be sure to configure your aws profile in the CLI (aws configure --profile [NAME]) and be sure to have sufficient privileges to create EC2 instances and security groups."
echo "Enter the profile name you would like to use:"
read -r profile

if ! aws --profile "$profile" sts get-caller-identity > /dev/null 2>&1
then
	echo "Unrecognized profile. Please make sure you typed the correct name. Exiting."
	exit 1
fi

echo "Enter the region you would like to create the instance in among the following list:"
aws --profile "$profile" ec2 describe-regions --query Regions[*].RegionName --output json
read -r region

ip=$(curl --silent ifconfig.me)

#Create key pair
aws --profile "$profile" ec2 create-key-pair --region "$region" --key-name vpn-keypair --query 'KeyMaterial' --output text > vpn-keypair.pem
chmod 400 vpn-keypair.pem

#Create security group
aws --profile "$profile" ec2 create-security-group --region "$region" --group-name vpn-sg --description "security group for openvpn instance" > /dev/null 2>&1

#Request protocol
echo "You will have to select a port and protocol for the VPN. Popular choices include port udp/1194 (but might require port-forwarding on your router) or tcp/443 (default value in this script). If you do not know what you are doing, go for tcp/443. Otherwise, you can select your own protocol with \"proto\"/\"port\" and the script will create a seucrity group rule with it."
echo "Note that you will be prompted again in the deploy script (WIP...?)"
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

echo "Authorize VPN access from all IPs? (all/mine/select, default mine)"
read -r ipselect
if [[ "$ipselect" == "all" ]]
then
	vpnaccessip="0.0.0.0/0"
elif [[ "$ipselect" == "select" ]]
then
	echo "Enter the CIDR blocks that you want to grant access to, separate them with a ;."
	read -r vpnaccessip
else
	vpnaccessip="$ip/32"
fi

#Create SG rules
#SSH SG rule
aws --profile "$profile" ec2 authorize-security-group-ingress --region "$region" --group-name vpn-sg --protocol tcp --port 22 --cidr "$ip/32"
#VPN SG rule
IFS=';'
for x in $vpnaccessip
do
	aws --profile "$profile" ec2 authorize-security-group-ingress --region "$region" --group-name vpn-sg --protocol $proto --port $port --cidr "$x"
done

unset IFS


#Create instance in default VPC

ami=$(aws --profile "$profile" ec2 describe-images --region "$region" --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20200112' 'Name=state,Values=available' --owners 099720109477 --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)

instanceid=$(aws --profile "$profile" ec2 run-instances --region "$region" --image-id "$ami" --instance-type t2.micro --security-groups vpn-sg --key-name vpn-keypair --query Instances[0].InstanceId)
if [[ "$instanceid" != "null" ]]
then
	echo "Deployment of instance successful."
	vpnserverip=$(aws --profile "$profile" ec2 describe-instances --region "$region" --filters "Name=instance-id,Values=$instanceid" --query Reservations[0].Instances[0].PublicIpAddress --output text)
	echo "Send the \"deploy-vpn-on-server.sh\" script to the server using the following command:"
	echo "scp -i vpn-keypair.pem deploy-vpn-on-server.sh ubuntu@$vpnserverip:/home/ubuntu"
	echo "Then, connect using the following command and run \"deploy-vpn-on-server.sh\" on the server:"
	echo "ssh -i vpn-keypair.pem ubuntu@$vpnserverip"
else
	echo "Error in instance deployment."
fi
