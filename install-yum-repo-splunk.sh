#!/bin/sh

cd $( dirname "$(readlink -f "$0")" )

echo "cp -a ./usr/local/bin/yum-repo-splunk-create-or-update.sh /usr/local/bin/yum-repo-splunk-create-or-update.sh :"
cp -a ./usr/local/bin/yum-repo-splunk-create-or-update.sh /usr/local/bin/yum-repo-splunk-create-or-update.sh

echo "cp -a ./etc/cron.d/yum_repo_splunk /etc/cron.d/yum_repo_splunk :"
cp -a ./etc/cron.d/yum_repo_splunk /etc/cron.d/yum_repo_splunk

echo "set selinux attributes:"
chcon system_u:object_r:system_cron_spool_t:s0 /etc/cron.d/yum_repo_splunk
chcon system_u:object_r:bin_t:s0 /usr/local/bin/yum-repo-splunk-create-or-update.sh

echo "yum install needed prerequisites:"
yum install createrepo coreutils curl

echo '------------'
USERFILE=~/.yum-repo-splunk
if ! [ -f "${USERFILE}" ]; then
	echo "create a credentials file to hold splunk.com credentials: ${USERFILE}"
	touch "${USERFILE}"
	chmod 660 "${USERFILE}"
	echo 'SPLUNKUSER=PUTSPLUNKDOTCOMUSERNAMEHERE' >> "${USERFILE}"
	echo 'SPLUNKPASS=PUTSPLUNKDOTCOMPASSWORDHERE' >> "${USERFILE}"
	echo "File ${USERFILE} has been created if needed."
	echo "Make sure to input/update your splunk.com SPLUNKUSER and SPLUNKPASS there."
else
	echo "Please verify splunk.com credentials are correct in file: ${USERFILE}"
fi
