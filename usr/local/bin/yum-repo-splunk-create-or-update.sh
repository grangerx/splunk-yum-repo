#!/bin/bash 
#File: yum-repo-splunk-create-or-update.sh
#Author: Justin Hochstetler (justin@grangerx.com)
#Version: 2022.02.24.A

PASSFILESPEC=~/.yum-repo-splunk

SYSLOGLEVEL=5
#syslog severity levels borrowed from solarwinds list.
#VALUE	SEVERITY	KEYWORD	DESCRIPTION
#0	Emergency	emerg	System is unusable
#1	Alert		alert	Should be corrected immediately
#2	Critical	crit	Critical conditions	
#3	Error		err	Error conditions
#4	Warning		warning	May indicate that an error will occur if action is not taken.
#5	Notice		notice	Events that are unusual, but not error conditions.	 
#6	Informational	info	Normal operational messages that require no action.
#7	Debug		debug	Information useful to developers for debugging the application.	 
BUFFER_EMERG=""; BUFFER_ALERT=""; BUFFER_CRIT=""; BUFFER_ERROR=""; BUFFER_WARNING=""; BUFFER_NOTICE=""; BUFFER_INFO=""; BUFFER_DEBUG=""

#a separate buffer, to collect everything that needs to be summarized.
BUFFER_SUMMARY=""

#For Username and Password, place those in a file at path ${PASSFILESPEC}
#NOTE: For the SPLUNKUSER and SPLUNKPASS, use the ones that have been registered with www.splunk.com, to allow downloads of their packages:
# -v- Content of file ${PASSFILESPEC} should be
SPLUNKUSER=PUTSPLUNKDOTCOMUSERNAMEHERE
SPLUNKPASS=PUTSPLUNKDOTCOMPASSWORDHERE
# -^- Content of file ${PASSFILESPEC} should be

#Source the file if it exists:
if [ -f ${PASSFILESPEC} ]; then
	#echo "Sourcing ${PASSFILESPEC}"
	source ${PASSFILESPEC}
else
	echo "Please validate that file ${PASSFILESPEC} exists, and contains lines for SPLUNKUSER= and SPLUNKPASS= ."
fi

#Validate that the sourced file did set SPLUNKUSER and SPLUNKPASS variables:
if [[ -z "${SPLUNKUSER}" || -z "${SPLUNKPASS}" ]]; then
	echo "SPLUNKUSER or SPLUNKPASS variable is unset."
	echo "Please validate that file ${PASSFILESPEC} exists, and contains lines for SPLUNKUSER= and SPLUNKPASS= ."
	exit 1 
fi

#Validate that the sourced file is not using the dummy values, though:
if [[ "${SPLUNKUSER}" == "PUTSPLUNKDOTCOMUSERNAMEHERE" || "${SPLUNKPASS}" == "PUTSPLUNKDOTCOMPASSWORDHERE" ]]; then
	echo "SPLUNKUSER or SPLUNKPASS in ${PASSFILESPEC} is not properly set."
	exit 1
fi

DATE_SPEC="$( date +%Y%m%d-%H%M%S )"
SPLUNK_DL_TEMP_LOC="/tmp/download-splunk-${DATE_SPEC}/"
SPLUNK_REPO_CONFIG_DIR_PATH="/etc/yum.repos.d/"
#SPLUNK_REPO_CONFIG_FP_SPEC="${SPLUNK_REPO_CONFIG_DIR_PATH}/splunk.repo"
SPLUNK_REPO_PATH_BASE="/opt/yumrepos/splunk"


#---------------------------------------
#-v- function fnBUFFER
#---------------------------------------
function fnBUFFER() {
	local msglevel="${1}"
	local includeinsummary="${2}"
	local content="${3}"
	local msglvlnum=7

#BUFFER_EMERG=""; BUFFER_ALERT=""; BUFFER_CRIT=""; BUFFER_ERROR=""; BUFFER_WARNING=""; BUFFER_NOTICE=""; BUFFER_INFO=""; BUFFER_DEBUG=""
	case "${msglevel}" in
		"DEBUG")
			msglvlnum=7
			BUFFER_DEBUG+="${content}\n"
			;;
		"INFO")
			msglvlnum=6
			BUFFER_INFO+="${content}\n"
			;;
		"NOTICE")
			msglvlnum=5
			BUFFER_NOTICE+="${content}\n"
			;;
		"WARNING")
			msglvlnum=4
			BUFFER_WARNING+="${content}\n"
			;;
		"ERROR")
			msglvlnum=3
			BUFFER_ERROR+="${content}\n"
			;;
		"CRIT")
			msglvlnum=2
			BUFFER_CRIT+="${content}\n"
			;;
		"ALERT")
			msglvlnum=1
			BUFFER_ALERT+="${content}\n"
			;;
		"EMERG")
			msglvlnum=0
			BUFFER_EMERG+="${content}\n"
			;;
		*)
			msglvlnum=5
			BUFFER_NOTICE+="${content}\n"
			;;
	esac
	
	if [ "${includeinsummary}" -eq 1 ]; then
		BUFFER_SUMMARY+="${content}\n"
	fi

	#if msglevel is lt/equal to defined SYSLOGLEVEL, echo the message:
	if [ "${msglvlnum}" -le "${SYSLOGLEVEL}" ]; then
		echo "${content}"
	fi
}
#---------------------------------------
#-^- function fnBUFFER
#---------------------------------------



#---------------------------------------
#-v- function fnCHECKUTIL
#---------------------------------------
function fnCHECKUTIL() {
	local utilpath="${1}"
	local utilname="${2}"
	local fixtextblurb="${3}"
	if [ ! -f "${utilpath}" ]; then
	fnBUFFER ERROR 1 "ERROR: The '${utilname}' executable must be available for this script to function."
	fnBUFFER ERROR 1 "NOTE: Issue the command '${fixtextblurb}' to install the utility."
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
	fnBUFFER DEBUG 0 "Cleanup: Deleting temp directory: ${SPLUNK_DL_TEMP_LOC}"
	rmdir "${SPLUNK_DL_TEMP_LOC}"
	echo '----'
	echo -e "SUMMARY:"
	echo -e "${BUFFER_SUMMARY}"
}
#---------------------------------------
#-^- function finish
#---------------------------------------

#DL function
function fnDownloadFile() {
	l_link="${1}"
	l_path="${2}"
	$( cd ${l_path} ; curl --user ${SPLUNKUSER}:${SPLUNKPASS} -O -s "${l_link}" )
	return $?
}

#CREATEDIR function
function fnCreateDir() {
	local l_dir="${1}"
	local l_desc="${2}"
	if [ ! -d ${l_dir} ]; then
		fnBUFFER INFO 0 "${l_desc}: ${l_dir} : Does Not Exist" 
		fnBUFFER INFO 0 "${l_desc}: ${l_dir} : Creating Directory" 
		mkdir -p "${l_dir}"
	else
		fnBUFFER INFO 0 "${l_desc}: ${l_dir} : Already Exists" 
	fi # if directory doesn't exist

}

#GETTHEPKG function
function fnGetThePkg() {
	local repo_name="${1}"
	local dl_link="${2}"
	local dl_rpm_name="${3}"
	local checksum_remote="${4}"
	local temp_fpspec="${SPLUNK_DL_TEMP_LOC}/${dl_rpm_name}"

	fnBUFFER INFO 0 "${repo_name}: Downloading file to temporary location: ${temp_fpspec}"

	DL_RES=$( fnDownloadFile "${dl_link}" "${SPLUNK_DL_TEMP_LOC}" )
	#echo "Checking local file checksum:"
	local checksum_local=$( cd ${SPLUNK_DL_TEMP_LOC} ; sha512sum -b "${dl_rpm_name}" | sed -e "s/^\(.*\) \*\(.*\)/SHA512(\2)= \1/g" )
	#Check the SHA512 checksum:
	if [ "${checksum_remote}" == "${checksum_local}" ]; then
		fnBUFFER INFO 0 "${repo_name}: Remote file downloaded and checksum validated: ${temp_fpspec}"
		fnBUFFER INFO 0 "${repo_name}: Moving file to final location: ${SPLUNK_REPO_PATH_BASE}/${repo_name}"
		mv "${SPLUNK_DL_TEMP_LOC}/${dl_rpm_name}" "${SPLUNK_REPO_PATH_BASE}/${repo_name}"
		fnBUFFER INFO 1 "${repo_name}: File Downloaded: ${checksum_local}"
		return 0
	else
		fnBUFFER ERROR 1 "${repo_name}: Downloaded file Checksum for : ${temp_fpspec} :: FAILED"
		fnBUFFER ERROR 1 "${repo_name}: Local file expected checksum for : ${temp_fpspec} :: ${checksum_remote}"
		fnBUFFER ERROR 1 "${repo_name}: Local file   actual checksum for : ${temp_fpspec} :: ${checksum_local}"
		return 1
	fi
}

# -v- Main:


#create the temp dl path if it doesn't exist:
fnCreateDir "${SPLUNK_DL_TEMP_LOC}" "Temp file Download Folder"

#Trap EXIT to display summary and do cleanup:
trap finish EXIT

#create the directory if it doesn't exist:
fnCreateDir "${SPLUNK_REPO_PATH_BASE}" "File Repositories BasePath"

#for each dl_url, process the url, find the true url, and download it.
for repo_name in "${!SPLUNK_RPM_HTTP_DL_URL[@]}"
do
	fnBUFFER INFO 0 "${repo_name}: Processing repo"
	dl_url="${SPLUNK_RPM_HTTP_DL_URL[${repo_name}]}"
	repo_path="${SPLUNK_REPO_PATH_BASE}/${repo_name}"
	repo_config_fp_spec="${SPLUNK_REPO_CONFIG_DIR_PATH}/${repo_name}.repo"

	fnCreateDir "${repo_path}" "${repo_name}: File Repository Path"

	#get the content of the page of the url:
	DL_PAGE_CONTENT=$( curl --user ${SPLUNKUSER}:${SPLUNKPASS} -s "${dl_url}" )


	#parse the actual package(s) and checksum(s) download location(s) from the page content:
	#use mapfile to read DL_LINKS and CHECKSUM_LINKS into arrays, with each element a line
	mapfile -t DL_LINKS <<< "$(echo "${DL_PAGE_CONTENT}" | grep "data-file" | grep rpm | sed 's/.*data-link="\([^"]*\)".*/\1/g')"
	mapfile -t CHECKSUM_LINKS <<< "$(echo "${DL_PAGE_CONTENT}" | grep "data-sha512" | grep rpm | sed 's/.*data-sha512="\([^"]*\)".*/\1/g')"
		
	#get the count of DL links and display it, just to give some info on what is being seen by the script.
	DL_LINKS_COUNT=${#DL_LINKS[@]} ; CHECKSUM_LINKS_COUNT=${#CHECKSUM_LINKS[@]} 
	fnBUFFER INFO 1 "${repo_name}: Pkgs found on remote site: ${DL_LINKS_COUNT}"


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
		checksum_remote=$( curl --user ${SPLUNKUSER}:${SPLUNKPASS} -s "${checksum_link}" )

		#check if the file has already been successfully downloaded:
		if [ -f ${this_pkg_rpm_final_fpspec} ]; then
			fnBUFFER INFO 0 "Local file already exists: ${this_pkg_rpm_final_fpspec}"
			#if downloaded, check the checksum:
			checksum_local=$( cd ${repo_path} ; sha512sum -b "${dl_rpm_name}" | sed -e "s/^\(.*\) \*\(.*\)/SHA512(\2)= \1/g" )
			if [ "${checksum_remote}" == "${checksum_local}" ]; then
				fnBUFFER INFO 0 "${repo_name}: Local file matches given remote checksum: ${this_pkg_rpm_final_fpspec}"
				fnBUFFER INFO 1 "${repo_name}: Already have file: ${checksum_local}"
			else
				fnBUFFER INFO 1 "${repo_name}: Local file DOES NOT match expected checksum: ${this_pkg_rpm_final_fpspec}"
				fnGetThePkg "${repo_name}" "${dl_link}" "${dl_rpm_name}" "${checksum_remote}"
			fi
		else
			fnBUFFER INFO 0 "${repo_name}: Local file does not exist."
			fnGetThePkg "${repo_name}" "${dl_link}" "${dl_rpm_name}" "${checksum_remote}"
		fi
	done


	#process any files in the final repo location:
	fnBUFFER INFO 0 "${repo_name}: Create Repo: Executing."
	#create the yum repo metadata:

	CREATEREPO_OUTPUT="$(/bin/createrepo --update "${repo_path}")"
	fnBUFFER DEBUG 0 "${CREAREREPO_OUTPUT}"
	fnBUFFER INFO 1 "${repo_name}: Create Repo: Finished."


	#if the repo file doesn't exist, create it:
	if [ ! -f ${repo_config_fp_spec} ]; then
		fnBUFFER INFO 0 "${repo_name}: Setting up the repo configuration file."
		cat <<- EO1STF > ${repo_config_fp_spec}
		[${repo_name}]
		name=Splunk Software Repository - ${repo_name}
		baseurl=file://${repo_path}/
		enabled=1
		gpgcheck=0
		EO1STF
		fnBUFFER INFO 1 "${repo_name}: Set up the repo configuration file."
	fi

		fnBUFFER INFO 1 "--------"
done

#echo -e "DEBUG: ${BUFFER_DEBUG}"
#echo -e "INFO: ${BUFFER_INFO}"
#echo -e "NOTICE: ${BUFFER_NOTICE}"
#echo -e "WARNING: ${BUFFER_WARNING}"
#echo -e "ERROR: ${BUFFER_ERROR}"
#echo -e "CRIT: ${BUFFER_CRIT}"
#echo -e "ALERT: ${BUFFER_ALERT}"
#echo -e "EMERG: ${BUFFER_EMERG}"
