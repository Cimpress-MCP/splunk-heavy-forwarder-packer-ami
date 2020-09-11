# heavy-forwarder-packer-ami

This repo uses [packer](https://packer.io) to build an AMI for deploying a Splunk Heavy Forwarder (HFW) to AWS.  This is intended for use with a [companion Terraform repo](https://github.com/Cimpress-MCP/splunk-heavy-forwarder-terraform-deployment) which will build the necessary infrastructure to deploy this to AWS using a sensible infrastructure.

## Additional Requirements

This requires a few extra things from you:

 1. [The Splunk Enterprise RPM file](https://www.splunk.com/en_us/download/splunk-enterprise.html)
 2. A license file from Splunk
 3. The app from Splunk that authenticates your HFW with to your Splunk Cloud account
 4. The input "address" for your Splunk Cloud instance

In detail:

**Enterprise RPM**
Download the Splunk Enterprise x86 64bit RPM from Splunk and save to [bin/splunk-enterprise-x86_64.rpm](bin/splunk-enterprise-x86_64.rpm).

**Splunk License**
Splunk will provide you with a HFW license file or, in the case of Cimpress business units, you will get this from CimSec.  Copy your license file into the [license](license) directory (the filename doesn't matter).

**Splunk app for authentication**
Splunk will provide you with an app that authenticates your HFW with your splunk cloud instance.  For CimSec business units this will be provided by CimSec.  Download this app and overwrite [bin/splunkclouduf.spl](bin/splunkclouduf.spl).

**Input "address" for Splunk Cloud**
Finally, you must tell the HFW where to direct output to.  Normally this is the standard "input" for your splunk cloud account, and will be something like `inputs1.[account_name].splunkcloud.com:9997`  This will be passed into packer when you run it (see [Running Packer](#running-packer) below)

## Running Packer

Theoretically this is very easy to run.  You just need to [install packer](https://www.packer.io/downloads) and set your AWS credentials in the standard environment variables/credentials file.  When you run packer you must specify a region to deploy the AMI to as well as the input address for your splunk cloud instance:

```
packer build -var 'region=us-east-1' -var 'splunk_input=inputs1.[account_name].splunkcloud.com:9997' heavy-forwarder.json
```

There are some important "gotchas" though.  Full details about building in AWS [are available from Packer](https://www.packer.io/docs/builders/amazon).

### VPCs

Packer needs to deploy an EC2 instance in AWS to build the AMI.  To do this it needs a VPC/subnet to deploy the instance into.  You can provide a (public) subnet id to deploy the build instance into like this:

```
packer build -var 'subnet_id=subnet-xxxxxxxx' -var 'region=us-east-1' -var 'splunk_input=inputs1.[account_name].splunkcloud.com:9997' heavy-forwarder.json
```

If you don't it will try to pick a sensible default, which may work fine for you.

### Security Groups and firewalls

Packer needs to connect to the build instance via SSH.  To do that it needs to be able to access the instance in question, so by default it generates a security group with the SSH port wide open to the internet (`0.0.0.0/0`) and attaches it to the instance.  Depending on the security settings in your AWS account this may cause problems.  If so you have to create your own security group for the deployment process in a particular subnet, whitelist only your IP address (with TCP/22) in the security group, and then tell Packer to use that security group.  Doing so looks like this:

```
packer build -var 'subnet_id=subnet-xxxxxxxx' -var 'security_group_id=sg-xxxxxxxxxxxxxxxxx' -var 'region=us-east-1' -var 'splunk_input=inputs1.[account_name].splunkcloud.com:9997' heavy-forwarder.json
```

If Packer seems to hang up on the "Connecting via SSH" step then there is probably a misconfiguration with the security group and Packer is unable to connect to the instance.  You don't actually have to stop Packer to fix this - it will continuously try to reconnect for a few minutes, so you have some time to adjust the security group rules.  If you correct it (and you gave Packer the correct security group id) then Packer will connect to the instance and continue without issue.

### AWS_PROFILE

Naturally, Packer needs write access to AWS in order to do its thing.  In most Cimpress accounts the default AWS access credentials are read-only, and then you must assume a role to gain write access.  In this case Packer will fail unless it knows what role to use.  The simplest way to fix this is by specifying an `AWS_PROFILE` environment variable to point to the admin profile in your AWS `credentials` file (which usually lives in `~/.aws/credentials`).  If your `credentials` file specifies another profile named e.g.  `account@admin` then you would `export AWS_PROFILE="account@admin"`.  When you run Packer it will use this profile and everything should work.

## Build Artifacts

Of course the end result of the Packer run is an AMI.  This is currently hard-coded to build an AMI with a name of `splunk_heavy_forwarder_aws_linux_8.0.5`.  The [Terraform repo that is a companion to this](https://github.com/Cimpress-MCP/splunk-heavy-forwarder-terraform-deployment) is set to look for an AMI with this name, so as long as you get the region right (AMIs are not accessible cross-region), you'll be fine.

If you want the resultant AMI to be in multiple regions you don't have to run this multiple times.  Instead just edit the `ami_regions` key in the `heavy-forwarder.json` file accordingly.

## Build Steps

Here is a quick rundown of what Packer does:

 1. Copy the license, app, installation RPMs, and some helper scripts into the build instance
 2. Install Splunk, Install the crowdstrike agent, and install the AWS SSM agent (The standard Splunk installation location - AKA `$SPLUNK_HOME` - is `/opt/splunk`)
 3. Install Python 3.7.  Python 3.7 is the Python version used by Splunk when switching to Python3, but unfortunately it must be manually compiled to install it on Amazon Linux 2
 4. Copy the contents of the `license` directory to `/opt/splunk/etc/licenses/enterprise/`.  Splunk will automatically find and import it from there when it starts.
 5. Copy the Splunk App to `/opt/splunk/etc/apps/splunkclouduf.spl`
 6. Add an environment variable for all users so that `$SPLUNK_HOME` will be set when you SSH into the machine.
 7. Switch Splunk to Python3
 8. Generate a random admin password for Splunk
 9. Initialize splunk, accept the license agreement, configure it to launch on startup, and set the admin password
 10. Re-configure it as a HFW instead of a full Splunk Enterprise installation
 11. Add the destination server input to the HFW configuration
 12. Install the `splunkclouduf.spl` app so that the HFW can authenticate with Splunk Cloud
 13. Configure the HFW to serve web traffic over HTTPS instead of HTTP (with a self-signed certificate)
 14. Configure the HFW to serve the UI on port 443 instead of 8000
 15. Throw away the admin password
