#!/usr/bin/env bash

sed -i "s/\[general\]/[general]\npython.version\ =\ python3/" /opt/splunk/etc/system/local/server.conf

# we're going to generate a random admin password for splunk so we can configure some stuff in the AMI,
# but then we are going to throw it away.  This is the easiest way to configure the things we need now
# and not have to worry about securely storing passwords.  So how do you know what password to use when
# you use this image?  You don't, but it is very easy to reset the splunk admin password, so just do that
# https://docs.splunk.com/Documentation/Splunk/7.1.2/Security/Secureyouradminaccount#Reset_a_lost_password
export SPLUNK_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')

cd /opt/splunk/bin
./splunk enable boot-start -systemd-managed 1 --accept-license --answer-yes --no-prompt --seed-passwd $SPLUNK_PASSWORD
./splunk start
./splunk enable app SplunkForwarder -auth "admin:$SPLUNK_PASSWORD"
./splunk restart
./splunk add forward-server $1 -auth "admin:$SPLUNK_PASSWORD"

cd /opt/splunk/etc/apps
tar xvf splunkclouduf.spl

cd /opt/splunk/bin
./splunk install app /opt/splunk/etc/apps/splunkclouduf.spl -auth "admin:$SPLUNK_PASSWORD"
./splunk enable web-ssl -auth "admin:$SPLUNK_PASSWORD"
./splunk set web-port 443 -auth "admin:$SPLUNK_PASSWORD"
./splunk restart

# At first I tried to manually add the license but it turns out you don't have to - it seems
# that Splunk checks the `$SPLUNK_HOME/etc/licenses` directory and automatically imports anything
# it finds in there.  Leaving this in though for reference.
# ./splunk add licenses /opt/splunk/etc/licenses/enterprise/HF_License.license
