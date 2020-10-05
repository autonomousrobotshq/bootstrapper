#!/bin/zsh
#
# Configurations go into config.txt
#

# internal environment variables
set -a
kernel="$(uname -s)"
callee=$0
source $(dirname "$0")/lib/core.zsh
basedir=$(realpath $(dirname "$0"))
lib=$basedir/lib
playbooks=$basedir/playbooks
playbooks_cpy=$basedir/.playbooks_cpy
ansibleconfigcache=$basedir/.ansible.config
ansibleconfigtemplate=$lib/ansible.config.template
ssh_d=$basedir/.ssh
configcache=$basedir/.config
configtemplate=$lib/config.template
refresh=$basedir/.refresh
source $basedir/config.txt || exit 1
downloads=$basedir/downloads
os_img=$downloads/$OS_IMG
os_img_checksum=$os_img.sha256sums
os_mnt=$basedir/.mnt
source $lib/checks.zsh || exit 1
source $lib/image.zsh || exit 1

# internal runtime variables
banner=false

## os variables
case $kernel in
	Darwin)
		alias PKG_UPDATE="brew update"
		alias PKG_INSTALL="brew install"
	;;
	Linux)
		flavour=$(cat /etc/os-release | grep ID_LIKE | cut -d= -f2)
		case $flavour in
			arch)
				alias PKG_UPDATE="yay -Sy"
				alias PKG_INSTALL="yay --noconfirm -S"
			;;
			ubuntu)
				alias PKG_UPDATE="sudo apt-get update"
				alias PKG_INSTALL="sudo apt-get install -y"
			;;
			*) logp fatal "You have choosen an operating system that is not on good terms with the Federation." ;;
		esac
	;;
	*) logp fatal "You have choosen an operating system that is not on good terms with the Federation." ;;
esac
# end of environment variables

function clean_up()
{
	[ ! -f $basedir/.tmp ] || rm -f $basedir/.tmp
	[ ! -z "$(mount | grep $os_mnt)" ] && logp info "Unmounting $os_mnt" && sudo umount $os_mnt
	case $1 in
		INT) logp fatal "aborting.." ;;
		EXIT) [ $banner = true ] && logp endsection ;;
		TERM) logp fatal "aborting.." ;;
	esac
}

trap "clean_up INT" INT
trap "clean_up TERM" TERM
trap "clean_up EXIT" EXIT

function banner()
{
	banner=true
	clear

	case $kernel in 
		Darwin) PRETTY_NAME="Mac OSx" ;;
		Linux) source /etc/os-release ;;
	esac
	cols=$(tput cols)
	date=$(date)
	whoami=$(whoami)
	ip="$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | tail -n1)"
	beacon="$(whoami)@$HOST ($ip)"

	zsh -c "echo -e \"\e[1m\e[33m+$(termFill '-' $((cols - 2)))+\""
	printf "|\e[0m`tput bold` %-$((cols - $((15 + ${#PRETTY_NAME} + ${#beacon})) ))s%-5s\e[1m\e[33m |\n" "$callee -- ROS:$ROS_RELEASE" "running $PRETTY_NAME @ $beacon"
	printf "\e[1m\e[33m| %-$((cols - 4))s\e[1m\e[33m |\n" ""
	if [ $# -gt 0 ]; then; printf "\e[1m\e[33m| %-$((cols - $((4 + ${#date})) ))s%-5s\e[1m\e[33m |\n" "$1" "`date`"; fi
	logp beginsection	
}


function prepareAnsibleEnvironment()
{
	prepareDependency ansible
	ANSIBLE_USER=ansible
	ANSIBLE_KEY=$(realpath $ssh_d)/ansible
	[ ! -d $ssh_d ] && mkdir -p $ssh_d
	if ! checkHasAnsibleKey && [ -z ${RKEY+x} ]; then
		logp info "Generating sshkey $ANSIBLE_KEY"
		prepareDependency ssh-keygen
		ssh-keygen -f $ANSIBLE_KEY -q -N "" || logp fatal "Couldn't generate ansible's bloody key!"
	fi
}

function ansibleRunPlaybook
{
	target=$1
	if [ $# -eq 2 ] && [ "$2" = "firstrun" ]; then
		ansibleoptions="ansible_port=$RPORT ansible_ssh_user=$DEFAULT_USER ansible_ssh_pass=$DEFAULT_PASS ansible_python_interpreter=/usr/bin/python3"
	else
		[ ! -f $ANSIBLE_KEY ] && logp fatal "No ansible ssh key found."
		ansibleoptions="ansible_port=$RPORT ansible_ssh_user=$ANSIBLE_USER ansible_ssh_private_key_file=$ANSIBLE_KEY ansible_python_interpreter=/usr/bin/python3 "
	fi

	ansible-playbook	-i $RHOST,\
						-e $ansibleoptions \
						$basedir/playbooks/$target.yml 
}

function readAnsibleConfigCache() { export $(grep -f $ansibleconfigtemplate $ansibleconfigcache) }

function writeAnsibleConfigcache() { typeset | grep -f $ansibleconfigtemplate > $ansibleconfigcache }

function readConfigcache() { export $(grep -f $configtemplate $configcache) }

function writeConfigcache() { env | grep -f $configtemplate > $configcache }

function getUserInfo()
{
	if [ "$ACTION" = "bootstrap" ] && [ "$2" = "raspberry" ]; then
		{ [ ! -f $configcache ] || [ $(wc -l $configcache | cut -f1 -d\ ) -lt 3 ] } && logp info "Your attention is required. The experiment requires you to answer truely and wholeheartedly."
		[ -z "${RHOST+x}" ] && logp question "remote host's network address" && read -r RHOST
		[ -z "${RPORT+x}" ] && logp question "remote host's port" &&  read -r RPORT
		[ -z "${DEFAULT_USER+x}" ] && logp question "remote host's first login user" && read -r DEFAULT_USER
		[ -z "${DEFAULT_PASS+x}" ] && logp question "remote host's first login  pass" && read -r DEFAULT_PASS
		[ -z "${ADMIN_USER+x}" ] && logp question "remote host's preferred admin user" && read -r ADMIN_USER
		[ -z "${ADMIN_PASS+x}" ] && logp question "remote host's preferred admin password" && read -r ADMIN_PASS
		[ -z "${ADMIN_KEY+x}" ] && logp question "remote host's preferred admin key" && read -r ADMIN_KEY
	elif [ "$ACTION" = "bootstrap" ] && [ "$2" = "raspberry-microsd" ]; then
		checkConfigcacheExists $configcache && readConfigcache
		logp info "Your attention is required. The experiment requires you to answer truely and wholeheartedly."
		if which lsblk; then
			logp info "Block devices : "
			lsblk -f 
		fi
		logp question "Destination microsd card (or other blockdevice)"; read -r blk_dev
		[ -z "${WIFI_SSID+x}" ] && logp question "Wifi address" && read -r WIFI_SSID
		[ -z "${WIFI_PASS+x}" ] && logp question "Wifi password" && read -r WIFI_PASS
	fi

	writeConfigcache
}

function prepareDependency()
{
	dep=$1
	if ! command -v $dep &> /dev/null; then
		logp info "Dependency '$dep' is missing. Attempting to install:"
		PKG_UPDATE || logp fatal "Couldn't update packages"
		PKG_INSTALL $dep || logp fatal "Couldn't install dependency '$dep'!"
	fi
}

function prepareAllDependencies()
{
	U=0
	for dep in "${DEPENDENCIES[@]}"
	do
		if ! command -v $dep &> /dev/null; then
			if [ $U -eq 0 ]; then
				PKG_UPDATE || logp fatal "Couldn't update packages"
				U=1
			fi
			PKG_INSTALL $dep || logp fatal "Couldn't install dependency '$dep'!"
		fi
	done
}

#https://stackoverflow.com/questions/3258243/check-if-pull-needed-in-git
function pullMaster()
{
	logp info "Checking for update.."
	prepareDependency git
	if git remote update 1>/dev/null ; then
		upstream=${1:-'@{u}'}
		local=$(git rev-parse @ $basedir)
		remote=$(git rev-parse "$upstream" $basedir)
		if [ $local != $remote ]; then
			p=$(pwd)
			cd $basedir
			git pull 1>/dev/null
			git submodule update --init --remote 1>/dev/null
			logp info "Bootstrapper has evolved!"
			cd $p
		fi
	else; return 1; fi
}

function prepareEnvironment()
{
	[ "$(echo $SHELL | rev | cut -d\/ -f1 | rev)" = "zsh" ] || logp fatal "$callee requires to be run with zsh."
	checkConnectivity && checkMasterUpdate && pullMaster || logp warning "An update has failed you. Your computer will explode now."
}

function handleFlags()
{
	[ $# -eq 0 ] && usage
	# read action options
	for ARG in $@; do
		[ "${ARG}" = "bootstrap" ] && ACTION="${ARG}" && break
		[ "${ARG}" = "clean" ] && ACTION="${ARG}" && break
		[ "${ARG}" = "reset" ] && ACTION="${ARG}" && break
		[ "${ARG}" = "help" ] && ACTION="${ARG}" && break
	done
	[ "$ACTION" = "" ] && usage
}

function performActions()
{
	case $ACTION in
		bootstrap) #############################################################
			[ $# -lt 2 ] && logp usage "$callee bootstrap [raspberry | arduino | arduino-env ] [ARGS]"
			case $2 in
				raspberry) #####################################################
					banner "Arr matey. Bootstrapping raspberry. Strike the earth!"

					checkConfigcacheExists $configcache  && { readConfigcache || logp fatal "configfile' $configfile' has corrupted." }
					getUserInfo $@	|| logp fatal "Failed to get your info"

					checkConnectivity || logp fatal "The network doesn't believe you have connected to it."
					checkIsReachable $RHOST || logp fatal "Host '$RHOST' is not reachable at this time (ping test)."
					prepareAnsibleEnvironment || logp fatal "The Ansible Environment has denied your request."

					if ! checkIsManageable $RHOST $RPORT $ANSIBLE_USER "NULL" $ANSIBLE_KEY; then
						target="ansible_user"; logp info "Started running playbook $target...";
						ansibleRunPlaybook $target firstrun || logp fatal "The machine is still resisting. $target rules have failed to comply!"
						if checkIsManageable $RHOST $RPORT $DEFAULT_USER $DEFAULT_PASS; then
							logp info "Default user is still present. Injecting ansible inlog and locking default user.."
							target="lock"; logp info "Started running playbook $target...";
							ansibleRunPlaybook $target || logp fatal "The machine is still resisting. $target rules have failed to comply!"
						else 
							logp fatal "Your $RHOST gave us trouble. Please give us the right credentials."
						fi
						sleep 5 # lock fucks with ssh-server
					fi

					target="system"; logp info "Started running playbook $target...";
					ansibleRunPlaybook $target || logp fatal "The machine is still resisting. $target rules have failed to comply!"

					target="ros"; logp info "Started running playbook $target...";
					ansibleRunPlaybook $target || logp fatal "The machine is still resisting. $target rules have failed to comply!"

					logp info "The machine has spoken. Bootstrap complete."
				;;
				raspberry-microsd) #############################################
					banner "Electrons! We summon you to carry out this microsd bootstrapping thing!"

					getUserInfo	$@ || logp fatal "Failed to get your info"
					image_prepare || logp fatal "Image couldn't be prepared at this moment."
					image_write || logp fatal "Failed to write image."
					logp info "The image was written succesfully." 

					image_prepare_network || logp fatal "Failed to apply network information: enter network info manualy!"
					logp info "The network configuration has decided in favour of the Federation. It was a wise decision." 

					[ ! -z "$(mount | grep $os_mnt)" ] && logp info "Unmounting $os_mnt" && { sudo umount $os_mnt || logp warning "Failed unmounting $os_mnt" }
					logp info "Syncing last blocks to disk.." && sudo sync
					logp info "By the analog Gods and the digital! The image was build. Yalla let us bootstrap a raspberry."
				;;
				arduino) #######################################################
					banner "Arduino here to bootstrap your spine."

					[ ! -f $ARDUINO_FIRMWARE_LOCATION ] && logp fatal "Store the compiled arduino firmware file @ $ARDUINO_FIRMWARE_LOCATION"

					if checkConfigcacheExists $configcache ; then readConfigcache || logp fatal "configfile' $configfile' has corrupted."
					else getUserInfo $@	|| logp fatal "Failed to get your info"; fi

					logp question "Local or Remote ? -> type L or R : "; read -r response
					if [ "$response" = "L" ]; then
						logp info "Attempting to flash locally.."

					elif [ "$response" = "R" ]; then
						logp info "Attempting to flash remotely.."
						checkIsReachable $RHOST || logp fatal "Host '$RHOST' is not reachable at this time (ping test)."
						
						target="arduino_upload"; logp info "Started running playbook $target...";
						ansibleRunPlaybook $target || logp fatal "The machine is still resisting. $target rules have failed to comply!"

					else
						logp fatal "bekijk 't maar"
					fi
				;;
				arduino-env) ###################################################
					[ ! $# -eq 3 ] && logp usage "$callee bootstrap arduino-env [[HOST:DIRECTORY] | [DIRECTORY]]"
					if checkIsReachable "$(echo $3 | cut -d: -f1)"; then
						which rsync || logp fatal "Cannot copy to/from host without rsync installed!"
						rsync -Wav --progress $3 || logp fatal "Couldn't copy arduino env over"
					elif [ -d $3 ] || mkdir -p $3; then
						dir=$3
						PKG_INSTALL $ARDUINO_PACKAGES || logp fatal "Couldn't install Arduino packages!"
						git clone git@github.com:$GIT_ORG/$GIT_LLC.git $dir || logp fatal "Couldn't clone Arduino-env!"
					else
						logp usage "$callee bootstrap arduino-env [[HOST:DIRECTORY] | [DIRECTORY]]";
					fi
				;;
			esac
		;;
		clean) #################################################################
			[ -f $ARDUINO_FIRMWARE_LOCATION ] && rm -f $ARDUINO_FIRMWARE_LOCATION && logp info "Cleaned configcache '$ARDUINO_FIRMWARE_LOCATION'"
			[ -d $downloads ] && rm -rf $downloads && logp info "Cleaned out downloads folder : $downloads."
		;;
		reset) #################################################################
			logp warning_nnl "Are you sure? This will also delete ansible/user keys! -> Legal demands that you type IMNOTANIDIOT to continue : "; read -r response
			if [ "$response" = "IMNOTANIDIOT" ]; then
				[ -d "$ssh" ] && rm -rf $ssh && logp info "Cleaned ssh folder with keys '$ssh'"
				[ -f $refresh ] && rm -f $refresh && logp info "Cleaned git update refresh file '$refresh'"
				[ -f $configcache ] && rm -f $configcache && logp info "Cleaned configcache '$configcache'"
				[ -f $ARDUINO_FIRMWARE_LOCATION ] && rm -f $ARDUINO_FIRMWARE_LOCATION && logp info "Cleaned configcache '$ARDUINO_FIRMWARE_LOCATION'"
				[ -d $downloads ] && rm -rf $downloads && logp info "Cleaned out downloads folder : $downloads."
			else	logp fatal "Probably a wise decision."; fi
		;;
		help) ##################################################################
			usage
		;;
	esac
}

function usage()
{
	(logp usage "")
	cat<<-EOF
		$callee bootstrap raspberry
		$callee bootstrap raspberry-microsd
		$callee bootstrap arduino
		$callee bootstrap arduino-env
		$callee clean # deletes replaceable data
		$callee reset # this clears out more than you might want
		$callee help	
	EOF
	exit 1
}

function main()
{
	prepareEnvironment || logp fatal "The Environment has denied your request."
	handleFlags $@
	performActions $@
}


main $@
