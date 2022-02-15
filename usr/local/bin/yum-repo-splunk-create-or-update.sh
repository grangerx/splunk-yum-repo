#!/bin/bash 
#File: yum-repo-splunk-create-or-update.sh
#Author: grangerx (grangerx@grangerx.com)
#Version: 2022.02.15.A

PASSFILESPEC=/root/.yum-repo-splunk

#For Username and Password, place those in a file at path ${PASSFILESPEC}
#NOTE: For the USER and PASS, use the ones that have been registered with www.splunk.com, to allow downloads of their packages:
# -v- Content of file ${PASSFILESPEC} should be
USER=PUTSPLUNKDOTCOMUSERNAMEHERE
PASS=PUTSPLUNKDOTCOMPASSWORDHERE
# -^- Content of file ${PASSFILESPEC} should be
source ${PASSFILESPEC}
if [ -z "${USER}" || -z "${PASS}" ]; then
	echo "USER or PASS variable is unset."
	echo "Please create file ${PASSFILESPEC} containing these variable declarations."
	exit 1 
fi

DATE_SPEC="$( date +%Y%m%d-%H%M%S )"
SPLUNK_DL_TEMP_LOC="/tmp/download-splunk-${DATE_SPEC}/"
SPLUNK_REPO_CONFIG_DIR_PATH="/etc/yum.repos.d/"
#SPLUNK_REPO_CONFIG_FP_SPEC="${SPLUNK_REPO_CONFIG_DIR_PATH}/splunk.repo"
SPLUNK_REPO_PATH_BASE="/opt/yumrepos/splunk"


#---------------------------------------
#-v- function fnCHECKUTIL
#---------------------------------------
function fnCHECKUTIL() {
	local utilpath="${1}"
	local utilname="${2}"
	local fixtextblurb="${3}"
	if [ ! -f "${utilpath}" ]; then
	echo "ERROR: The '${utilname}' executable must be available for this script to function."
	echo "NOTE: Issue the command '${fixtextblurb}' to install the utility."
	exit 1
	fi
}
#---------------------------------------
#-^- function fnCHECKUTIL
#---------------------------------------

#check for createrepo:
fnCHECKUTIL "/bin/createrepo" "createrepo" "#yum install createrepo"

#check for sha512sum:
fnCHECKUTIL "/usr/bin/sha512sum" "sha512sum" "#yum install coreutils"

#check for curl:
fnCHECKUTIL "/bin/curl" "curl" "#yum install curl"


declare -a ERRORS

#declare an associative array where each key is the repo name/dir and the value is the url to download from:
declare -A SPLUNK_RPM_HTTP_DL_URL
SPLUNK_RPM_HTTP_DL_URL+=([splunk-enterprise]="https://www.splunk.com/en_us/download/splunk-enterprise.html#")
SPLUNK_RPM_HTTP_DL_URL+=([splunk-universal-forwarder]="https://www.splunk.com/en_us/download/universal-forwarder.html#")


#---------------------------------------
#-v- function finish
#---------------------------------------
# finish function - this is called when the script exits
#---------------------------------------
function finish() {
	echo "Cleanup: Deleting temp directory: ${SPLUNK_DL_TEMP_LOC}"
	rmdir "${SPLUNK_DL_TEMP_LOC}"
}
#---------------------------------------
#-^- function finish
#---------------------------------------

#DL function
function fnDownloadFile() {
	l_link="${1}"
	l_path="${2}"
	$( cd ${l_path} ; curl --user ${USER}:${PASS} -O -s "${l_link}" )
	return $?
}

#CREATEDIR function
function fnCreateDir() {
	local l_dir="${1}"
	local l_desc="${2}"
	if [ ! -d ${l_dir} ]; then
		echo "${l_desc}: ${l_dir} : Does Not Exist" 
		echo "${l_desc}: ${l_dir} : Creating Directory" 
		mkdir -p "${l_dir}"
	else
		echo "${l_desc}: ${l_dir} : Already Exists" 
	fi # if directory doesn't exist

}

#GETTHEPKG function
function fnGetThePkg() {
	local repo_name="${1}"
	local dl_link="${2}"
	local dl_rpm_name="${3}"
	local checksum_remote="${4}"
	local temp_fpspec="${SPLUNK_DL_TEMP_LOC}/${dl_rpm_name}"

	echo "Downloading file to temporary location: ${temp_fpspec}"

	DL_RES=$( fnDownloadFile "${dl_link}" "${SPLUNK_DL_TEMP_LOC}" )
	#echo "Checking local file checksum:"
	local checksum_local=$( cd ${SPLUNK_DL_TEMP_LOC} ; sha512sum -b "${dl_rpm_name}" | sed -e "s/^\(.*\) \*\(.*\)/SHA512(\2)= \1/g" )
	#Check the SHA512 checksum:
	if [ "${checksum_remote}" == "${checksum_local}" ]; then
		echo "Local file matches expected checksum: ${temp_fpspec}"
		echo "Moving file to final location: ${SPLUNK_REPO_PATH_BASE}/${repo_name}"
		mv "${SPLUNK_DL_TEMP_LOC}/${dl_rpm_name}" "${SPLUNK_REPO_PATH_BASE}/${repo_name}"
		return 0
	else
		echo "Checksum for : ${temp_fpspec} :: FAILED"
		return 1
	fi
}


# -v- Main:

#create the temp dl path if it doesn't exist:
fnCreateDir "${SPLUNK_DL_TEMP_LOC}" "Temp file Download Folder"
trap finish EXIT

#create the directory if it doesn't exist:
fnCreateDir "${SPLUNK_REPO_PATH_BASE}" "File Repositories BasePath"

#for each dl_url, process the url, find the true url, and download it.
for repo_name in "${!SPLUNK_RPM_HTTP_DL_URL[@]}"
do
	echo "Processing repo: ${repo_name}"
	dl_url="${SPLUNK_RPM_HTTP_DL_URL[${repo_name}]}"
	repo_path="${SPLUNK_REPO_PATH_BASE}/${repo_name}"
	repo_config_fp_spec="${SPLUNK_REPO_CONFIG_DIR_PATH}/${repo_name}.repo"

	fnCreateDir "${repo_path}" "File Repository Path for ${repo_name}"

	#get the content of the page of the url:
	DL_PAGE_CONTENT=$( curl --user ${USER}:${PASS} -s "${dl_url}" )


	#parse the actual package(s) and checksum(s) download location(s) from the page content:
	#use mapfile to read DL_LINKS and CHECKSUM_LINKS into arrays, with each element a line
	mapfile -t DL_LINKS <<< "$(echo "${DL_PAGE_CONTENT}" | grep "data-file" | grep rpm | sed 's/.*data-link="\([^"]*\)".*/\1/g')"
	mapfile -t CHECKSUM_LINKS <<< "$(echo "${DL_PAGE_CONTENT}" | grep "data-sha512" | grep rpm | sed 's/.*data-sha512="\([^"]*\)".*/\1/g')"
		
	#get the count of DL links and display it, just to give some info on what is being seen by the script.
	DL_LINKS_COUNT=${#DL_LINKS[@]} ; CHECKSUM_LINKS_COUNT=${#CHECKSUM_LINKS[@]} 
	echo "Packages found on remote site for ${repo_name}: ${DL_LINKS_COUNT}"


	#take the count of links, and use a for loop to iterate
	#across the array of DL and Checksum links
	for ((i=0;i<${#DL_LINKS[@]};i++))
	do
		#get the i-th DL and Checksum link out of each array:
		dl_link="${DL_LINKS[i]}"
		checksum_link="${CHECKSUM_LINKS[i]}"

		#get the rpm name from the link:
		dl_rpm_name="$(basename "${dl_link}")"

		#determine the final file name/location:
		this_pkg_rpm_final_fpspec="${repo_path}/${dl_rpm_name}"

		#sha512_link="${dl_link}.sha512"

		#download the checksum file for the file:
		checksum_remote=$( curl --user ${USER}:${PASS} -s "${checksum_link}" )

		#check if the file has already been successfully downloaded:
		if [ -f ${this_pkg_rpm_final_fpspec} ]; then
			echo "Local file already exists: ${this_pkg_rpm_final_fpspec}"
			#if downloaded, check the checksum:
			sha512_local=$( cd ${repo_path} ; sha512sum -b "${dl_rpm_name}" | sed -e "s/^\(.*\) \*\(.*\)/SHA512(\2)= \1/g" )
			if [ "${checksum_remote}" == "${sha512_local}" ]; then
				echo "Local file matches given remote checksum: ${this_pkg_rpm_final_fpspec}"
			else
				echo "Local file DOES NOT match expected checksum: ${this_pkg_rpm_final_fpspec}"
				fnGetThePkg "${repo_name}" "${dl_link}" "${dl_rpm_name}" "${checksum_remote}"
			fi
		else
			echo "Local file does not exist."
			fnGetThePkg "${repo_name}" "${dl_link}" "${dl_rpm_name}" "${checksum_remote}"
		fi
	done


	#process any files in the final repo location:
	echo "Create Repo: Executing for: ${repo_name}"
	#create the yum repo metadata:
	/bin/createrepo --update "${repo_path}"
	echo "Create Repo: Finished for: ${repo_name}"
	echo ""


	#if the repo file doesn't exist, create it:
	if [ ! -f ${repo_config_fp_spec} ]; then
	echo "Setting up the repo configuration file for: ${repo_name}"
	cat <<- EO1STF > ${repo_config_fp_spec}
	[${repo_name}]
	name=Splunk Software Repository - ${repo_name}
	baseurl=file://${repo_path}/
	enabled=1
	gpgcheck=0
	EO1STF
	fi

done

