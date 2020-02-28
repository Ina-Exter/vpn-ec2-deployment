# vpn-ec2-deployment (tentative name)

A bundle of thoroughly guided scripts to deploy openvpn on an EC2 instance.

## What is this

This is an easy way to deploy an OpenVPN server using your AWS (Amazon Web Services) account.

This is **FREE-TIER COMPATIBLE**, which means you can have a personal vpn for free for one year using the AWS free tier.

## Prerequisites

An AWS account

A bash shell on a debian or ubuntu system to run the server creation script (optional). WSL Debian should work.

A VPN client (Openvpn)

## How to use

The server creation script is made to run on a debian or ubuntu linux with a bash shell. While a bash shell and the AWSCLI should be sufficient, it is untested on anything else than debian 10 "buster".

Install the required packages:

`sudo apt-get update; sudo apt-get install ssh scp awscli`

Configure your AWS credentials:

`aws configure --profile [NAME]`

Clone the repository:

`git clone https://github.com/Ina-Exter/vpn-ec2-deployment`

Run the server creation script (if on a compatible system) and input the required data:

`./create-vpn-server.sh`

Send the setup script to the remote server:

`scp -i vpn-keypair.pem deploy-vpn-on-server.sh ubuntu@[SERVER_IP]:/home/ubuntu`

SSH into the remote server:

`ssh -i vpn-keypair.pem ubuntu@[SERVER_IP]`

Run the setup script and input the required data (answer "yes" for signature requests):

`./deploy-vpn-on-server.sh`

Back on your machine, fetch the .ovpn file:

`scp -i vpn-keypair.pem ubuntu@[SERVER_IP]:/home/ubuntu/client-configs/files/[CLIENT_NAME].ovpn`

Optional: on a Linux client, edit the .ovpn file to uncomment the required lines.

Use the vpn client of your choice to connect.

## Precautions and caveats

Do not shut down the instance once it is created: That will change the public IP and you will need to reconfigure.

If any part of the script fails, delete everything it made before setting up again. (For server creation, this means key-pair, instance, security group. For the setup script, just rm -rf the home dir).

If you use a non-standard port, you may have to configure port forwarding on your router.

Remember to edit the .ovpn file if you use a linux client.

The region you use will be where your VPN is based. Choose it wisely.

## Creating the server manually (if you cannot run the server creation script)

In case you use a specific system or do not have access to a bash shell (hello, Windows), you may want to create the server manually. This comes in three parts, for which we will use the AWS Console (browser-based):

### 0: Navigate to aws.amazon.com and login to the console

Also make sure to select the region of your choice.

### 1: Navigate to the **EC2** service and create a Key Pair

Select the "Key pair" category and create a key-pair. Name it whatever you would like, then download the key file. For the sake of this tutorial, it will be named vpn-keypair.pem

### 2: Create a fitting security group

Select the "Security Group" category and create a new one. Name it "vpn", for instance. You will want to add the following inbound rules:

 * tcp for port 22 for your IP (SSH)
 * protocol of your choice for port of your choice for IPs you choose (VPN)

Note the selected protocol and port: you will have to input them again later in the deployment script. A personal recommandation is tcp for port 443 for your IP, and serves as the default for the whole script.

Outbound rules should be allow all traffic to anywhere.

### 3: Create the server

Select the "Instances" category and click "Launch instance".

Select the "Ubuntu Server 18.04 LTS (HVM), SSD Volume Type, (64-bit x86)" AMI

Select a t2.micro instance (free tier eligible) and click Next. Note: if you would not like to use free tier, you may select whichever type you want, but yu **will** be billed. I am not responsible for any billing incurred.

Click Next until you arrive at "6. Configure Security Group" and select the "vpn" security group you created beforehand. Then click "Review and Launch".

Click "Launch". You will be prompted to select a key pair. Select the key pair you created beforehand.

Wait for the machine to start, then resume the "How to use" steps at "Send the deployment script to your remote instance".

## Disclaimer

This software is given as is, without any guarantees or liabilities. I am not responsible for any incurred billing.
