@echo off
set str=%*
set "str=%str:\=/%"
echo "Arg is " %str% " en " %cd% "."
echo docker run -it --rm --net="host" -v %cd%:/code set-registry.repo.icts.kuleuven.be/dsb/xake:latest ./build.sh %str%
docker run --rm --net="host" -v %cd%:/code registry.gitlab.kuleuven.be/wet/ximera/xake-docker:2019  ./build.sh %str%
