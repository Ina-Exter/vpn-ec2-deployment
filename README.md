# vpn-ec2-deployment (tentative name)

A bundle of thoroughly guided scripts to deploy openvpn on an EC2 instance.

## What is this

This is an easy way to deploy an OpenVPN server using your AWS (Amazon Web Services) account.

This is **FREE-TIER COMPATIBLE**, which means you can have a personal vpn for free for one year using the AWS free tier.

## Prerequisites

An AWS account

A bash shell on a debian or ubuntu system to run the server creation script (optional). WSL Debian should work.

A VPN client (Openvpn)

## How to use

The server creation script is made to run on a debian or ubuntu linux with a bash shell.

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

## Precautions and caveats

Do not shut down the instance once it is created: That will change the public IP and you will need to reconfigure.

If any part of the script fails, delete everything it made before setting up again. (For server creation, this means key-pair, instance, security group. For the setup script, just rm -rf the home dir).

If you use a non-standard port, you may have to configure port forwarding on your router.

Remember to edit the .ovpn file if you use a linux client.

## Disclaimer

This software is given as is, without any guarantees or liabilities. I am not responsible for any incurred billing.
