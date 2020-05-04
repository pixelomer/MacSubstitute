#!/usr/bin/env sh

if [ "${EUID}" -eq 0 ]; then
	echo "Don't run this script as root."
	exit 1;
fi

##### CONFIGURATION BEGIN #####

CC="clang"
CFLAGS=""
PROJECTS="InjectorBootstrap Injector Loader TestDylib"

Loader_OUT="loader.dylib"
Loader_FILES="main.m"
Loader_CFLAGS="-lobjc -framework Foundation -shared"
Loader_INSTALL() {
	sudo mkdir -p "/usr/local/MacSubstitute"
	sudo cp "${OUT_DIR}/${Loader_OUT}" "/usr/local/MacSubstitute/TweakLoader.dylib"
}

Injector_OUT="substituted"
Injector_CFLAGS="-lobjc -framework Foundation -framework Cocoa"
Injector_FILES="injector.cpp mach_inject.c main.mm"

InjectorBootstrap_OUT="bootstrap.dylib"
InjectorBootstrap_CFLAGS="-shared"
InjectorBootstrap_FILES="main.cpp"
InjectorBootstrap_INSTALL() {
	sudo mkdir -p "/usr/local/MacSubstitute"
	sudo cp "${OUT_DIR}/${InjectorBootstrap_OUT}" "/usr/local/MacSubstitute/Bootstrap.dylib"
}

TestDylib_OUT="test.dylib"
TestDylib_FILES=""
TestDylib_CFLAGS="-lobjc -framework Foundation -shared -framework Cocoa -I."
TestDylib_PRE_BUILD() {
	m=""
	for ((i=0;i<2;i++)); do
		for a in *.x$m; do [ -f "$a" ] && {
			logos.pl "$a" > .${a%.*}.m$m;
			TestDylib_FILES=".${a%.*}.m$m ${TestDylib_FILES}";
		}; done
		m="m"
	done
}
TestDylib_POST_BUILD() {
	rm -f .*.m .*.mm;
}
TestDylib_INSTALL() {
	sudo mkdir -p "/usr/local/MacSubstitute/DynamicLibraries/"
	sudo cp "${OUT_DIR}/${TestDylib_OUT}" test.plist "/usr/local/MacSubstitute/DynamicLibraries/"
}

##### CONFIGURATION END #####

get() {
	eval echo "\${${project}_$1}"
}
can_call() {
	type "${project}_$1" >/dev/null 2>&1
	return $?
}
call() {
	if can_call "$1"; then
		fun="${project}_$1"
		eval "${fun}"
	fi
}

PROJECT_ROOT="$(pwd)"
OUT_DIR="${PROJECT_ROOT}/out"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

echo "Cleaning up..."
set -e
sudo killall substituted >/dev/null 2>&1 || true
sudo rm -vrf ~/Library/Containers/*/Data/Documents/$(printf '\x01')SubstituteLink
set +e

for project in ${PROJECTS}; do
	echo "Building ${project}..."
	pushd "${project}" > /dev/null 2>&1
	call PRE_BUILD
	current_cflags="$(get CFLAGS)"
	current_files="$(get FILES)"
	current_out="$(get OUT)"
	"${CC}" ${CFLAGS} ${current_cflags} -o "${OUT_DIR}/${current_out}" ${current_files}
	fail=$?
	call POST_BUILD
	if [ "${fail}" -eq 0 ]; then
		if can_call INSTALL; then
			echo "Installing ${project}..."
			set -e
			call INSTALL
			set +e
		fi
	else
		exit ${fail}
	fi
	popd > /dev/null 2>&1
done