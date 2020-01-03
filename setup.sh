#!/bin/sh -e

cwd=$(cd -- "$(dirname -- "$0")" && pwd -P)

curl=$(command -v curl || true)
[ ! "$curl" ] && printf "curl is required, aborting...\n" && exit 127

# quick function to get OS "name"
get_os() {
  case $(uname -s | tr '[:upper:]' '[:lower:]') in
    bsd*) echo "bsd" ;;
    darwin*) echo "darwin" ;;
    linux*) echo "linux" ;;
    msys|cygwin|ming*) echo "windows" ;;
    *) echo "" ;;
  esac
}

os_hardware=$(uname -m)
os_name=$(get_os)

# check if jq is available on the system, and try to download/make it if not
jq=$(command -v jq || true)
if [ -z "${jq}" ]; then
  jq="/tmp/jq"

  if [ ! -x "${jq}" ]; then
    printf "required jq not found, trying to retrieve...\n"

    if [ -z "${os_hardware#*64}" ]; then
      arch=64
    else
      arch=32
    fi

    case $os_name in
      darwin) jq_os="osx-amd64" ;;
      linux) jq_os="linux${arch}" ;;
      *) jq_os="tar.gz" ;;
    esac

    jq_release_url=$($curl -s https://api.github.com/repos/stedolan/jq/releases/latest \
      | grep browser_download_url \
      | grep "${jq_os}" \
      | cut -d '"' -f 4)

    if [ "$jq_os" = "tar.gz" ]; then
      if [ ! "$(command -v autoreconf || true)" -o ! "$(command -v make || true)" ]; then
        printf "GCC, Make, and Autotools required to build jq from source"
        exit 1
      fi

      $curl -fsSL -o /tmp/jq.tar.gz $jq_release_url
      tar -xzf /tmp/jq.tar.gz /tmp/jq-build
      rm -f /tmp/jq.tar.gz
      cd /tmp/jq-build
      autoreconf -i
      ./configure --disable-maintainer-mode
      make
      cp jq /tmp/jq
      cd $cwd
      rm -rf /tmp/jq-build
    else
      $curl -fsSL -o /tmp/jq $jq_release_url
      chmod +x /tmp/jq
    fi
  fi
fi

# make sure any other files, required by this script, are available locally
if [ ! -s "${cwd}/config.json" ];then
  $curl -fsSL -O https://raw.githubusercontent.com/jwinn/setup-system/master/config.json
fi

# load the config file into a var
config=$(cat "${cwd}/setup.sh.json" | "${jq}" ".${os_name}")

# use jq to parse requisite pieces out
pkg_config=$(echo "${config}" | "${jq}" -r '.pkg')
pkg_cmd=$(echo "${pkg_config}" | "${jq}" -r '.cmd')
pkg_setup=$(echo "${pkg_config}" | "${jq}" -r '.setup')
pkg_preinstall=$(echo "${pkg_config}" | "${jq}" -r 'select(. | has("preinstall")) | .preinstall | join(" && ")')
pkg_postinstall=$(echo "${pkg_config}" | "${jq}" -r 'select(. | has("postinstall")) | .postinstall | join(" && ")')

echo "config cmd setup preinstall postinstall" | tr ' ' '\n' | while read -r i; do
  echo "\$pkg_${i}=$(eval echo "\$pkg_${i}")"
done
exit

setup_macos() {
  brew=$(command -v ${pkg_cmd} || true)

  if [ -n "$brew" ]; then
    $brew update && $brew upgrade && $brew clean && $brew doctor
  else
    printf "Do you want to install homebrew? (Y/n)"
    read -r homebrew_answer
    if [ -z "${homebrew_answer#[Yy]}" ] || [ -z "${homebrew_answer}" ]; then
      printf "Installing homebrew...\n"
      /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
      printf "Done\n\n"

      printf "Do you want to install homebrew packages? (Y/n)"
      read -r homebrew_pkg_answer
      if [ -z "${homebrew_pkg_answer#[Yy]}" ] || [ -z "${homebrew_pkg_answer}" ]; then
      fi
    fi
  fi
}

case $os_name in
  bsd) setup_bsd ;;
  darwin) setup_macos ;;
  linux) setup_linux ;;
esac

if [ "${os_name}" != "windows" ]; then
  printf "Do you want to install dotfiles? (Y/n)"
  read -r dotfiles_answer
  if [ -z "${dotfiles_answer#[Yy]}" ] || [ -z "${dotfiles_answer}" ]; then
    # get dotfiles
    curl -fsSL https://raw.githubusercontent.com/jwinn/dotfiles/master/install.sh | sh
  fi
fi