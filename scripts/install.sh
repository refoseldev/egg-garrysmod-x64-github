#!/bin/bash

set -Eeuo pipefail

server_dir=/mnt/server
steamcmd_dir="${server_dir}/steamcmd"

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git tar
rm -rf /var/lib/apt/lists/*

mkdir -p "${steamcmd_dir}" "${server_dir}/steamapps"
curl --fail --show-error --location --retry 3 \
    --output /tmp/steamcmd.tar.gz \
    https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzf /tmp/steamcmd.tar.gz -C "${steamcmd_dir}"
rm -f /tmp/steamcmd.tar.gz

export HOME="${server_dir}"

steam_user=${STEAM_USER:-anonymous}
steamcmd_args=(
    +force_install_dir "${server_dir}"
    +login "${steam_user}" "${STEAM_PASS:-}" "${STEAM_AUTH:-}"
    +app_update "${SRCDS_APPID:-4020}"
    -beta x86-64
)

if [[ -n "${EXTRA_FLAGS:-}" ]]; then
    read -r -a extra_flags <<< "${EXTRA_FLAGS}"
    steamcmd_args+=("${extra_flags[@]}")
fi

steamcmd_args+=(validate +quit)
"${steamcmd_dir}/steamcmd.sh" "${steamcmd_args[@]}"

install -D -m 0644 "${steamcmd_dir}/linux32/steamclient.so" "${server_dir}/.steam/sdk32/steamclient.so"
install -D -m 0644 "${steamcmd_dir}/linux64/steamclient.so" "${server_dir}/.steam/sdk64/steamclient.so"

mkdir -p "${server_dir}/garrysmod/lua/autorun/server" "${server_dir}/garrysmod/cfg"

if [[ ! -f "${server_dir}/garrysmod/lua/autorun/server/workshop.lua" ]]; then
    cat > "${server_dir}/garrysmod/lua/autorun/server/workshop.lua" <<'LUA'
-- Add individual Workshop addon IDs here when clients must download them.
-- Example: resource.AddWorkshop("123456789")
LUA
fi

if [[ ! -f "${server_dir}/garrysmod/cfg/server.cfg" ]]; then
    cat > "${server_dir}/garrysmod/cfg/server.cfg" <<'CFG'
hostname "Hosted by RefoselDev"
sv_password ""
sv_loadingurl ""
sv_downloadurl ""

sv_region "255"
sv_lan "0"
sv_max_queries_sec_global "30000"
sv_max_queries_window "45"
sv_max_queries_sec "5"

sbox_maxprops "100"
sbox_maxragdolls "5"
sbox_maxnpcs "10"
sbox_maxballoons "10"
sbox_maxeffects "10"
sbox_maxdynamite "10"
sbox_maxlamps "10"
sbox_maxthrusters "10"
sbox_maxwheels "10"
sbox_maxhoverballs "10"
sbox_maxvehicles "20"
sbox_maxbuttons "10"
sbox_maxsents "20"
sbox_maxemitters "5"
sbox_godmode "0"
sbox_noclip "0"

sv_minrate "75000"
sv_maxrate "0"
gmod_physiterations "2"
net_splitpacket_maxrate "45000"
decalfrequency "12"

exec banned_ip.cfg
exec banned_user.cfg
CFG
fi

if [[ "${AUTO_INSTALL:-0}" != "1" ]]; then
    echo "Git repository installation is disabled."
    exit 0
fi

if [[ -z "${GIT_ADDRESS:-}" ]]; then
    echo "GIT_ADDRESS must be set when AUTO_INSTALL is enabled." >&2
    exit 1
fi

git_folder=${GIT_FOLDER:-}
if [[ "${git_folder}" = /* || "${git_folder}" == *..* ]]; then
    echo "GIT_FOLDER must be a relative path without '..'." >&2
    exit 1
fi

if [[ -n "${git_folder}" ]]; then
    git_target="${server_dir}/${git_folder}"
else
    git_target="${server_dir}"
fi
mkdir -p "${git_target}"

# The installer runs as root, but /mnt/server belongs to the container user.
# Git 2.35+ rejects repositories whose .git is owned by another UID ("dubious
# ownership"), so trust both the install-time and the runtime path explicitly.
# (The volume is mounted at /mnt/server here and at /home/container at runtime.)
git_safe=(
    -c "safe.directory=${git_target}"
    -c "safe.directory=${git_target/#${server_dir}//home/container}"
)

git_address=${GIT_ADDRESS}
[[ "${git_address}" == *.git ]] || git_address="${git_address}.git"

askpass=
if [[ -n "${USERNAME:-}" && -n "${ACCESS_TOKEN:-}" ]]; then
    askpass=$(mktemp)
    cat > "${askpass}" <<'ASKPASS'
#!/bin/sh
case "$1" in
    *Username*) printf '%s\n' "$GIT_USERNAME" ;;
    *) printf '%s\n' "$GIT_ACCESS_TOKEN" ;;
esac
ASKPASS
    chmod 700 "${askpass}"
    export GIT_ASKPASS="${askpass}" GIT_USERNAME="${USERNAME}" GIT_ACCESS_TOKEN="${ACCESS_TOKEN}"
    trap 'rm -f "${askpass}"' EXIT
fi

git "${git_safe[@]}" -C "${git_target}" init
git "${git_safe[@]}" -C "${git_target}" remote remove origin 2>/dev/null || true
git "${git_safe[@]}" -C "${git_target}" remote add origin "${git_address}"
git "${git_safe[@]}" -C "${git_target}" fetch --depth=1 origin "${BRANCH:-HEAD}"
git "${git_safe[@]}" -C "${git_target}" checkout -f -B deployed FETCH_HEAD

# The installer ran as root, so give the checkout back to whoever owns the
# server volume; otherwise the runtime container (a different UID) keeps
# tripping over the same "dubious ownership" check.
if [[ ${EUID} -eq 0 ]]; then
    chown -R "$(stat -c '%u:%g' "${server_dir}")" "${git_target}"
fi

echo "Repository installed into ${git_target}."
