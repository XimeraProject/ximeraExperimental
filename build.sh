#!/bin/bash
#
# This script
#  - starts a xake docker onainer (unless were already IN a container)
#  - starts xake, with the arguments passed to the script
#  - optionally gets you a shell inside the container
#  - optionally automates lots of other things


#: "${XAKE_IMAGE:=xake}"
: "${XAKE_IMAGE:=registry-ext.repo.icts.kuleuven.be/set/dsb/xake:1.2.1a}"
: "${MOUNTDIR:=$(pwd)}"

if [[ -f /.dockerenv ]]  
then
    echo "Running in docker container ($HOSTNAME)"
elif [[ -n "$KUBERNETES_SERVICE_HOST" ]] 
then
    echo "Running in kubernetes container ($KUBERNETES_SERVICE_HOST)"
else 
    echo "Running $0 on host ($HOSTNAME)"

    if [[ "$1" == "-i" ]]
    then
        INTERACTIVE="-it"
    fi 

    # LOCAL_IP is only needed if you want to serve to your localhost
    if [[ "$LOCAL_IP" == "" ]]
    then
        LOCAL_IP=$(set -- $(hostname -I); echo "$1")
        echo "SETTING LOCAL_IP=$LOCAL_IP"
    fi

    echo "Restarting myself in docker container"	
    echo  docker run --env LOCAL_IP --env URL_XIMERA --env REPO_XIMERA --env GPG_KEY --env GPG_KEY_ID --network host --rm $INTERACTIVE --mount type=bind,source=$MOUNTDIR,target=/code $XAKE_IMAGE ./build.sh $*
    exec  docker run --env LOCAL_IP --env URL_XIMERA --env REPO_XIMERA --env GPG_KEY --env GPG_KEY_ID --network host --rm $INTERACTIVE --mount type=bind,source=$MOUNTDIR,target=/code $XAKE_IMAGE ./build.sh $*
    # END-OF-SCRIPT: this exec will never return !
fi

# We're for sure running in a container now

echo "Starting $*"

# If there are local versions of ximeraLatex, copy them to the right place  inside the container
if [[ -f .ximera/ximera.4ht ]]; then
    echo "USING ximera.4ht from local repo"
    cp .ximera/ximera.4ht /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/ximera.cls ]]; then
    echo "USING ximera.cls from local repo"
    cp .ximera/ximera.cls /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/ximera.cfg ]]; then
    echo "USING ximera.cfg from local repo"
    cp .ximera/ximera.cfg /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/xourse.cls ]]; then
    echo "USING xourse.cls from local repo"
    cp .ximera/xourse.cls /root/texmf/tex/latex/ximeraLatex/
fi
if [[ -f .ximera/xourse.4ht ]]; then
    echo "USING xourse.4ht from local repo"
    cp .ximera/xourse.4ht /root/texmf/tex/latex/ximeraLatex/
fi

# HACK: is there a better solution for sagelatex ...?
if [[ -f .ximera/sagetex.sty ]]; then
    echo "USING sagetex.sty from local repo"
    cp .ximera/sagetex.sty /root/texmf/tex/latex/ximeraLatex/
fi

# Add anything that might not be installed in the container 
# HACK: hardcoded path ...
if [[ -d .texmf ]]; then
    echo "USING .texmf etc from local repo"
    cp -r .texmf/* /usr/local/texlive/2019/texmf-dist/tex/generic/
fi


# Longer lines in pdflatex output
export max_print_line=1000
export error_line=254
export half_error_line=238

: "${LOCAL_IP:=localhost}"
: "${URL_XIMERA:=http://$LOCAL_IP:2000/}"     # default: publish to ximera-docker-instance, but 'localhost' does refer to THIS container
: "${REPO_XIMERA:=test}"
: "${NB_JOBS:=2}"
: "${XAKE:=xake}"
: "${DOCKER_MOUNT:=$(pwd)}"

while getopts ":hitd" opt; do
  case ${opt} in
    h ) 
       cat <<EOF
        Build and publish a ximera-repository to a ximera-server (via bake/frost/serve)

        Publishes to $URL_XIMERA$REPO_XIMERA 
EOF
       exit 0
      ;;
    i )
        echo "Interactive session"
        ;;
    d )
       XAKE="docker run --env GPG_KEY --env GPG_KEY_ID --network host --rm -it --mount type=bind,source=$(pwd),target=/code xake xake" 
       URL_XIMERA="http://$LOCAL_IP:2000/"
       echo "Using docker to run $XAKE  (from $DOCKER_MOUNT)"	

      ;;
    \? ) echo "Usage: build [-h] [-t]"
	 exit 1
      ;;
  esac
done
shift $((OPTIND -1))

COMMAND=$1

reset_file_times() {
 if find . -maxdepth 1 -name "*.tex" -mtime +1 | grep .
 then
  # .tex files older then 1 day: presumably the git was not checked out just now,
  # and modittimes are correct
  echo "Skipping resetting file times"
 else
  # all .tex files are recent, presumable just after a git clone. This would cause re-compile of everything
  # therefore: restore all modif-dates
  echo "Resetting file times"
  apt install git-restore-mtime    # HACK: this should be in the container image !!!
  # git status   # in DETACHED HEAD in CI !!
  git restore-mtime -f
  ls -al *.tex *.sty *.pdf
 fi
}

if [[ "$COMMAND" == "bash" ]]
then
    # interactive shell (option -i needed when starting the container !)
    ${XAKE%xake} /bin/bash
elif [[ "$COMMAND" == "serve" ]]
then
    echo "xake serve"
    if [[ -f "$GPG_KEY" ]]
    then
        cat $GPG_KEY | base64 --decode > .gpg # decode the base64 gpg key
    else 
        echo "$GPG_KEY" >.gpg # | base64 --decode > .gpg # decode the base64 gpg key
    fi
    echo "Importing key"
    gpg --import .gpg 
    rm .gpg # remove the gpg key so he is certainly not cached
    ### BRANCHPART=`echo "*$CI_BUILD_REF_NAME" | tr '[:upper:]' '[:lower:]'` # Add star and lowercase
    ### if [ "$MASTER_WITH_STAR" = 'false' ]; then REPO=$REPO_BASE""${BRANCHPART/*master/}; else REPO=$REPO_BASE""$BRANCHPART; fi
    echo "KEYSERVER gpg -v --keyserver $URL_XIMERA --send-key $GPG_KEY_ID"
    gpg -v --keyserver $URL_XIMERA --send-key "$GPG_KEY_ID"
    echo "xake NAME: $XAKE -U $URL_XIMERA -k $GPG_KEY_ID name $REPO_XIMERA"
    $XAKE -v -U $URL_XIMERA -k "$GPG_KEY_ID" name "$REPO_XIMERA" # Stel de repository in, op master is dit REPO_BASE, anders REPO_BASE*<branch>
#    echo "Prepare git repo"
#    git fetch --unshallow # Zorg ervoor dat we de hele geschiedenis hebben ipv enkel een deel, anders werkt het serven niet
#   .git config core.fileMode false
#    git branch -D master || true    #ignore error
#    git checkout -B master # doe alsof we op master zitten
    echo "xake FROST"
    $XAKE -v frost # Zorg voor juiste links etc = maak metadata.json en tag etc
    echo "xake SERVE"
	echo "git status:"
    git status
	echo "git tag -n"
    git tag -n
	echo "git rev-parse --abbrev-ref --all:"
    git rev-parse --abbrev-ref --all
	echo "git remote -v:"
	git remote -v
    $XAKE -v serve 2>&1 # Upload files = push tag
else
    echo "Passing arguments: starting xake $*"
    xake $*
fi

#exit 0; % ignore errors
