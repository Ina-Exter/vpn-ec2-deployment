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

ipv6dump=$(ip a|grep "/128")                                                                                                                                                                                         IFS=' '
for x in $ipv6dump
do
	if [[ ${x: -4} == "/128" ]]
	then
		ipv6="$x"
		break
	fi
done
unset IFS

#Request protocol
echo "You will have to select a port and protocol for the VPN. Popular choices include port udp/1194 (but might require port-forwarding on your router) or udp/443 (default value in this script). If you do not know what you are doing, go for udp/443. Otherwise, you can select your own protocol with \"proto\"/\"port\" and the script will create a seucrity group rule with it. Note that tcp is not advised (tcp meltdown)."
echo "Note that you will be prompted again in the deploy script (WIP...?)"
read -r protoport
if [[ "${protoport:3:1}" != "/" ]]
then
	echo "Empty variable or bad structure, using default."
	port="443"
	proto="udp"
else
	proto=${protoport:0:3}
	port=${protoport:4}
fi
if [[ "$proto" != "tcp" ]] && [[ "$proto" != "udp" ]]
then
	echo "Invalid protocol, using udp"
	proto="udp"
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

#Create key pair
aws --profile "$profile" ec2 create-key-pair --region "$region" --key-name vpn-keypair --query 'KeyMaterial' --output text > vpn-keypair.pem
chmod 400 vpn-keypair.pem

#Create instance in a new VPC to which we pinned the IPv6 CIDR block
vpcid=$(aws --profile "$profile" ec2 create-vpc --cidr-block 10.0.0.0/23 --amazon-provided-ipv6-cidr-block --query Vpc.VpcId --output text)
aws --profile "$profile" ec2 create-tags --resources "$vpcid" --tags Key=Name,Value=vpn-vpc
ipv6cidr=$(aws --profile "$profile" ec2 describe-vpcs --vpc-id "$vpcid" --query Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock --output text)
ipv6cidrshort=${ipv6cidr:0:-3}

#Create security group
groupid=$(aws --profile "$profile" ec2 create-security-group --region "$region" --group-name vpn-sg --vpc-id "$vpcid" --description "security group for openvpn instance" --output text)

#Create SG rules
#SSH SG rule
aws --profile "$profile" ec2 authorize-security-group-ingress --region "$region" --group-id "$groupid" --protocol tcp --port 22 --cidr "$ip/32"
#VPN SG rule
IFS=';'
for x in $vpnaccessip
do
	aws --profile "$profile" ec2 authorize-security-group-ingress --region "$region" --group-id "$groupid" --protocol $proto --port $port --cidr "$x"
done
unset IFS

#IPV6 SG rule
aws --profile "$profile" ec2 authorize-security-group-ingress --region "$region" --group-id "$groupid" --ip-permissions IpProtocol=$proto,FromPort=$port,ToPort=$port,Ipv6Ranges='[{CidrIpv6='$ipv6'}]'



#Create a subnet within, pin it a v6 subnet
subnetid=$(aws --profile mtxalpha ec2 create-subnet --cidr-block 10.0.1.0/24 --ipv6-cidr-block "$ipv6cidrshort/64" --vpc-id "$vpcid" --query Subnet.SubnetId --output text)
aws --profile "$profile" ec2 create-tags --resources "$subnetid" --tags Key=Name,Value=vpn-subnet
aws --profile "$profile" ec2 modify-subnet-attribute --subnet-id "$subnetid" --map-public-ip-on-launch
aws --profile "$profile" ec2 modify-subnet-attribute --subnet-id "$subnetid" --assign-ipv6-address-on-creation


ami=$(aws --profile "$profile" ec2 describe-images --region "$region" --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20200112' 'Name=state,Values=available' --owners 099720109477 --query 'reverse(sort_by(Images, &CreationDate))[:1].ImageId' --output text)
 
instanceid=$(aws --profile "$profile" ec2 run-instances --region "$region" --image-id "$ami" --instance-type t2.micro --subnet-id "$subnetid" --security-group-ids "$groupid" --key-name vpn-keypair --associate-public-ip-address --query Instances[0].InstanceId --output text)
aws --profile "$profile" ec2 create-tags --resources "$instanceid" --tags Key=Name,Value=vpn-server
vpnserverip=$(aws --profile "$profile" ec2 describe-instances --region "$region" --filters "Name=instance-id,Values=$instanceid" --query Reservations[0].Instances[0].PublicIpAddress --output text)
if [[ "$vpnserverip" != "null" ]] && [[ "$vpnserverip" != "" ]]
then
	echo "Deployment of instance successful."
	echo "You can now send the \"deploy-vpn-on-server.sh\" script to the server"
	#scp -i vpn-keypair.pem deploy-vpn-on-server.sh ubuntu@$vpnserverip:/home/ubuntu
	echo "Use: scp -i vpn-keypair.pem deploy-vpn-on-server.sh ubuntu@$vpnserverip:/home/ubuntu"
	echo "Connect using the following command and run \"deploy-vpn-on-server.sh\" on the server:"
	echo "ssh -i vpn-keypair.pem ubuntu@$vpnserverip"
	echo "server ip: $vpnserverip, protocol: $proto, port: $port, ipv4: $ip, ipv6: $ipv6" > serverconf.txt
	#scp -i vpn-keypair.pem serverconf.txt ubuntu@$vpnserverip:/home/ubuntu
	echo "A conf.txt file has been created. It contains various data about the server, and serves as a reminder/is read by the script. Don't hestitate to send it over"
else
	echo "Error in instance deployment."
fi
