#!/bin/bash
#
#
# author:   lorenzo chianura 
# mail:     lorenzo.chianura_at_abinsula.com
# version:  0.1
#
#

## tools, helpers, data structures, colors
USER=$(whoami)
SDKDIR=""
DATAFILE="pkgs.data"
PKGS=
REPOS=
GITSTATUS="git status --porcelain"
GITREMOTEUPDATE="git remote update"

# associative arrays
declare -Ag libs_to_repos
declare -Ag libs_to_require
declare -Ag libs_to_branch

# colors
RED_COLOR="\e[01;31m"
GREEN_COLOR="\e[01;32m"
YELLOW_COLOR="\e[01;33m"
BLUE_COLOR="\e[01;34m"
END_COLOR="\e[0m"

# useful fields for data mining
LIBNAME="1"
BRANCH="2"
GITURL="3"
REQUIRE="4"


## functions

# color helpers
red() { echo -e "$RED_COLOR $@ $END_COLOR"; }
green() { echo -e "$GREEN_COLOR $@ $END_COLOR"; }
blue() { echo -e "$BLUE_COLOR $@ $END_COLOR"; }
yellow() { echo -e "$YELLOW_COLOR $@ $END_COLOR"; }

# check if USER is not root, otherwise exit
check_uid() {
    if [ "$EUID" -eq 0 ]; then
        echo "[$(red WARNING)] do not run this script as root!"
        exit 1
    fi
}

# check if SDK is installed, if TRUE check for write permissions 
check_sdk() {
    if [ ! -d "$SDKDIR" ]; then
        echo "[$(red WARNING)] SDK path does not exist!"
        exit 1
    else
        if [ "$(stat -c %U "${SDKDIR}")" != "$USER" ]; then
            echo -n "[$(yellow WARNING)]$(blue "${USER}")does not have write "
            echo -n "permissions on $SDKDIR, correct this? [y,n]: "
            read -r yn
            case $yn in
                 [Yy]* ) sudo chown "$USER":"$USER" -R $SDKDIR;;
                 [Nn]* ) echo -n "[ $(red ERROR) ] with no write permissions ";
                         echo -n "on SDK sysroot path you'll be unable tu use ";
                         echo "this script."; exit 1;;
                 * ) echo "Please answer yes or no."; exit 1;;
            esac
        fi
        echo "[$(blue INFO)] SDK sysroot path: $SDKDIR"
    fi
}

# check if DATAFILE is provided
check_data() {
    if [ ! -f "$DATAFILE" ]; then
        echo "[$(yellow WARNING)] cannot found $DATAFILE !"
        echo -n "create an empty one? [y,n]: "
        read -r yn
        case $yn in
            [Yy]* ) echo "# lines beginning with # will be ignored" > $DATAFILE; exit 0;;
            [Nn]* ) exit 1;;
            * ) echo "Please answer yer or no."; exit 1;;
        esac
    else
        PKGS=( `grep -v '^[[:space:]]*#' ${DATAFILE} | awk -v idx=$LIBNAME '{print $idx}'` )
        REPOS=( `grep -v '^[[:space:]]*#' ${DATAFILE} | awk -v idx=$GITURL '{print $idx}'` )
        BRANCHES=( `grep -v '^[[:space:]]*#' ${DATAFILE} | awk -v idx=$BRANCH '{print $idx}'` )

        # it should be safe enough 'cause awk will return empty lines also
        REQUIRES=( `grep -v '^[[:space:]]*#' ${DATAFILE} | awk -v idx=$REQUIRE '{print $idx}'` )

        # check if arrays length is correct
        if [ "${#PKGS[*]}" -ne "${#REPOS[*]}" -o "${#PKGS[*]}" -ne "${#BRANCHES[*]}" ]; then
            echo "[$(red ERROR)] $DATAFILE is malformed!"
        else
            # build associative arrays
            idx=0
            while [ "$idx" -lt "${#PKGS[@]}" ]; do
                tlib="${PKGS[$idx]}"
                trepo="${REPOS[$idx]}"
                tdep="${REQUIRES[$idx]}"
                tbranch="${BRANCHES[$idx]}"
                # TODO: why I have to "duplicate" tlib and trepo vars in order
                #       to avoid error assignment in the associative array?
                #       I should be able to use:
                #           libs_to_repos[$tlib]=$trepo
                #       but it ends with "wrong index" error
                sub_idx=$tlib
                sub_arg_repo=$trepo
                sub_arg_dep=$tdep
                sub_arg_branch=$tbranch

                libs_to_repos[$sub_idx]=$sub_arg_repo
                libs_to_require[$sub_idx]=$sub_arg_dep
                libs_to_branch[$sub_idx]=$sub_arg_branch

                let idx=idx+1
            done
        fi
    fi
}


# first time setup: fetch all packages and build them
setup_env() {
    if [ "${#PKGS[*]}" -ne 0 ]; then
        for pkg in "${PKGS[@]}"; do
            echo -n "[$(yellow FETCHING)] $pkg ..."
            if [ -d "$pkg" ]; then
                cls_row
                echo -n "[$(red FETCHING)] $pkg ..."
                echo "$(red a directory with the same name already exist)"
            else
                clone_pkg $pkg
            fi
        done
    else
        echo -n "[$(yellow WARNING)] $DATAFILE does not contain any package"
        echo
        exit 0
    fi
}

# clone $1 pkg
clone_pkg() {
    cls_row
    echo -n "[$(yellow FETCHING)] $1 ..."
    # check if the remote branch exist
    git ls-remote ${libs_to_repos[$1]} | grep ${libs_to_branch[$1]} &> /dev/null
    if [ "$?" -ne 0 ]; then
        cls_row
        echo -n "[$(red FETCHING)] $1 ..."
        echo "$(red branch)$(blue ${libs_to_branch[$1]})$(red not found in upstream repo)"
    else
        git clone ${libs_to_repos[$1]} -b ${libs_to_branch[$1]} $1 &> /dev/null
        if [ $? -eq 0 ]; then
            cls_row
            echo -n "[$(green FETCHING)] $1 ..."
            echo "$(green done) [$(blue ${libs_to_branch[$1]})]"
        else
            cls_row
            echo -n "[$(red FETCHING)] $1 ..."
            echo "$(red failed)"
        fi
    fi
}

# ask for cloning
ask_for_reclone() {
    echo -n "[$(blue INFO)] clone everything again? "
    echo "(obviously, undeleted directories will not be overwritten) [y,n]: "
    read -r yn
    case $yn in
         [Yy]* ) setup_env; exit 0;;
         [Nn]* ) exit 0;;
         * ) echo "Please answer yes[y] or no[n]."; exit 1;;
    esac
}

# add packages to DATAFILE
add_pkg() {
    if [[ -z ${1} || -z ${2} ]]; then
        echo "missing arguments, usage:"
        echo "    ./dev_tool.sh -a git@your.git.repo/project.git branch"
    else
        idx=0    
        flag=0
        while [ $idx -lt ${#REPOS[@]} ]; do
            repo="${REPOS[$idx]}"
            if [ "${repo}" == "${1}" ]; then
                echo -n "[$(yellow WARNING)] $1 already in $DATAFILE"
                echo
                flag=1
                break
            fi
            let idx=idx+1
        done

        if [ "${flag}" -eq 0 ]; then
            pkgname=$(echo "$1" | awk  -F "/" '{print $NF}' | cut -d. -f1)
            echo $pkgname $2 $1 >> $DATAFILE
            echo "[$(blue INFO)] $pkgname added"
            check_data
            echo "[$(blue INFO)] packages list updated"
            echo -n "[$(blue INFO)] clone $pkgname now? [y,n]: "
            read -r yn
            case $yn in
                [Yy]* ) clone_pkg $pkgname; exit 0;;
                [Nn]* ) exit 0;;
                * ) echo "Please answer yes[y] or no[n]."; exit 1;;
            esac
        fi
    fi
}

# remove all cloned repos
remove_all() {
if [ -z "${1}" ]; then
    echo "[$(blue INFO)] you're going to permanently delete all your cloned repos"
	echo "         ($(yellow NOTE) that in case you decide to proceed, local repos that have unstaged work will remain untouched )"
    echo "are you sure? [y,n]: "
    read -r yn
    case $yn in
         [Yy]* ) ;;
         [Nn]* ) exit 0;;
         * ) echo "Please answer yes[y] or no[n]."; exit 1;;
    esac

    #delete all cloned dirs
    for pkg in "${PKGS[@]}"; do
        echo -n "[$(yellow DELETING)] $pkg ..."
        if [ ! -d $pkg ]; then
            cls_row
            echo -n "[$(red DELETING)] $pkg ..."
            echo "$(red not found)"
        else
            cd $pkg &>/dev/null
            unstaged=$(${GITSTATUS} 2>&1 | awk '{print $1}' | wc -l)
            if [ $unstaged -gt 0 ]; then
                cls_row
                echo -n "[$(red DELETING)] $pkg ..."
                echo "$(red cannot proceed)"
                echo
                echo -e "\t     cannot delete $(blue $pkg) because you have" 
                echo -e "\t     unstaged work in your local repository. Please"
                echo -e "\t     commit and push your work or stash/delete it."
                echo
                cd - &>/dev/null
                continue;
            else
                cd - &>/dev/null
            fi

            rm -rf $pkg &> /dev/null
            if [ $? -eq 0 ]; then
                echo "$(green done)"
            else
                echo "$(red failed)"
            fi
        fi
    done
    echo

    ask_for_reclone
else
    pkgname=${1%/}
    echo -n "[$(yellow DELETING)] ${pkgname} ..."
    if [ ! -d "${pkgname}" ]; then
        cls_row
        echo -n "[$(red DELETING)] ${pkgname} ..."
        echo "$(red not found)"
    else
        cd $pkgname &>/dev/null
        unstaged=$(${GITSTATUS} 2>&1 | awk '{print $1}' | wc -l)
        if [ $unstaged -gt 0 ]; then
            cls_row
            echo -n "[$(red DELETING)] $pkgname ..."
            echo "$(red cannot proceed)"
            echo
            echo -e "\t     cannot delete $(blue $pkgname) because you have" 
            echo -e "\t     unstaged work in your local repository. Please"
            echo -e "\t     commit and push your work or stash/delete it."
            echo
            cd - &>/dev/null
        else
            cd - &>/dev/null
        fi

        rm -rf $pkgname &> /dev/null
        if [ $? -eq 0 ]; then
            echo "$(green done)"
        else
            echo "$(red failed)"
        fi
        echo -n "[$(blue INFO)] delete $pkgname entry from local db? Future updates will avoid to update it [y,n]: "
        read -r yn
        case $yn in
            [Yy]* ) sed -i "/"$pkgname"/d" $DATAFILE;;
            [Nn]* ) exit 0;;
            * ) echo "Please answer yes[y] or no[n]."; exit 1;;
        esac
    fi
fi
}

# remove all the stuff without check git status
remove_force() {
#delete all cloned dirs
for pkg in "${PKGS[@]}"; do
    echo -n "[$(yellow DELETING)] $pkg ..."
    if [ ! -d $pkg ]; then
        echo "$(red not found)"
    else
        rm -rf $pkg &> /dev/null
        if [ $? -eq 0 ]; then
            echo "$(green done)"
        else
            echo "$(red failed)"
        fi
    fi
done
echo

ask_for_reclone
}


# print a "first time run" warning
setup_warn() {
    echo
    echo "[$(yellow README)]   You're going to fetch, build and install all the"
    echo "             packages listed in $DATAFILE: if a previous "
    echo "             run of this script has already fetched all or some "
    echo "             of the packages, the git fetch will fail."
    echo
}

# clean stdout row
# TODO: a clever way should exist, find it
cls_row() {
echo -ne "                                                                                             \r"
}
                
# update packages
update_pkgs() {
	if [ -z "${1}" ]; then 
        for pkg in "${PKGS[@]}"; do
	        update_pkg ${pkg}
        done
    else
        update_pkg ${1}
    fi
    echo
}

# update single package
update_pkg() {
    echo
    cls_row
    pkgname=${1%/}
    echo -ne "[$(yellow UPDATING)] ${pkgname} ...\r"
    if [ ! -d "${pkgname}" ]; then
        cls_row
        echo -ne "[$(red UPDATING)] ${pkgname} ... $(red not found)\r"
    else
        cd "$1" &>/dev/null
        unstaged=$(${GITSTATUS} 2>&1 | awk '{print $1}' | wc -l)
        if [ "$unstaged" -gt 0 ]; then
            cls_row
            echo -ne "[$(red UNSTAGED)] ${pkgname} ... $(red cannot update)\r"
            echo
            echo -e "\t     cannot update $(blue $pkgname) because you have" 
            echo -e "\t     unstaged work in your local repository. Please"
            echo -e "\t     commit and push your work or stash/delete it."
            echo
        else
            # TODO: check git remote update failures
            #       for stuff like timeouts and others related
            cls_row
            echo -ne "[$(yellow UPDATING)] ${pkgname} ... checking remote\r"
            lines=$(${GITREMOTEUPDATE} 2>&1 | wc -l) 
            if [ "$lines" -gt 1 ]; then
                cls_row
                echo -ne "[$(yellow UPDATING)] ${pkgname} ... pulling\r"
                git pull &>/dev/null
                if [ $? -eq 0 ]; then
                    cls_row
                    echo -ne "[$(blue UPDATING)] ${pkgname} ... $(blue updated)\r"
                else
                    cls_row
                    echo -ne "[$(yellow UPDATING)] ${pkgname} ... $(red failed)\r"
                fi
            else
                cls_row
                echo -ne "[$(green UPDATING)] ${pkgname} ... $(green already aligned)\r"
            fi 
        fi
        cd - &>/dev/null
    fi
}

# print a useful help
print_help() {
echo "
Use: $0 [command] <options>

[command] could be:

-a, --add <repo> <branch>   add <repo> to DATAFILE, <branch> will
                            be used when cloning

-i, --init           fetch all the repositories needed to develop
                     for the LAM-TSU project, use this option
                     only during the first setup of your develop
                     environment 

-r, --remove <pkg>    if <pkg> is provided, remove cloned <pkg> otherwise
                     delete all cloned repos.
                     If you have unstaged changes in one or more local repo/s
                     a warning message will inform you and the related
                     repository will not be deleted 

-u, --update <pkg>   for every package, check if remote (git) has changed,
                     if TRUE try to pull from the configured branch (see
                     the $DATAFILE for all the infos); if there are
                     unstaged changes a warning message will inform you 
                     and the git pull will not be performed. If <pkg> is given
                     only <pkg> will be updated.

-rf, --remove-force   delete all the existing cloned repositories,
                     WITHOUT checking the git status      

-h, --help           prints this help and exit


This tool use a file named $DATAFILE (if you want to use a different
file change DATAFILE variable) to retrieve informations about name, branch
and repository url. 
A typical entry should be formatted as above:

   project_name    branch    repo_url

where project_name can be a name of your choice.
Lines which starts with # character will be ignored.
"
}

# main stuff
check_uid

case $1 in
    -a|--add ) check_data; add_pkg $2 $3; exit 0;;
    -i|--init ) check_data; setup_warn; setup_env; exit 0;;
    -h|--help ) print_help; exit 0;;
    -r|--remove ) check_data; remove_all $2; exit 0;;
    -rf|--remove-force ) check_data; remove_force; exit 0;;
    -u|--update ) check_data; update_pkgs $2; exit 0;;
    * ) echo; echo "you should add a command, try with: $0 --help"; echo; exit 1;;
esac

exit 0
