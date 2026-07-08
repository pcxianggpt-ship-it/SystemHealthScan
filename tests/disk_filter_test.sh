#!/usr/bin/env bash
# Integration test for disk collection filtering.
# Usage: bash tests/disk_filter_test.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/df" <<'DFEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-iP" ]; then
    cat <<'OUT'
Filesystem                       Inodes IUsed   IFree IUse% Mounted on
devtmpfs                        1880000   400 1879600    1% /dev
tmpfs                           1881000     1 1880999    1% /dev/shm
tmpfs                           1881000   850 1880150    1% /run
tmpfs                           1881000     3 1880997    1% /sys/fs/cgroup
/dev/mapper/klas-root           13631488 920000 12711488  7% /
tmpfs                           1881000    20 1880980    1% /tmp
/dev/mapper/datavg_lvm-data_lv  138412032 990000 137422032 1% /data
/dev/sda1                         524288   310    523978  1% /boot
tmpfs                            376200      1    376199  1% /run/user/0
overlay                         138412032 990000 137422032 1% /data/docker_root/overlay2/de4a4901e985/merged
OUT
else
    cat <<'OUT'
Filesystem                      Size  Used Avail Use% Mounted on
devtmpfs                        7.2G     0  7.2G   0% /dev
tmpfs                           7.2G     0  7.2G   0% /dev/shm
tmpfs                           7.2G  755M  6.5G  11% /run
tmpfs                           7.2G     0  7.2G   0% /sys/fs/cgroup
/dev/mapper/klas-root            26G   18G  8.7G  67% /
tmpfs                           7.2G  172K  7.2G   1% /tmp
/dev/mapper/datavg_lvm-data_lv  264G  146G  106G  58% /data
/dev/sda1                      1014M  167M  848M  17% /boot
tmpfs                           1.5G     0  1.5G   0% /run/user/0
overlay                         264G  146G  106G  58% /data/docker_root/overlay2/de4a4901e985/merged
OUT
fi
DFEOF
chmod +x "${TMP_DIR}/bin/df"

PATH="${TMP_DIR}/bin:${PATH}" bash "${ROOT_DIR}/collect.sh" "${TMP_DIR}/collect.dat" >/dev/null

disk_line="$(grep '^DISK_=' "${TMP_DIR}/collect.dat")"
inode_line="$(grep '^INODE_=' "${TMP_DIR}/collect.dat")"

expect_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "FAIL: ${label}; missing ${needle}" >&2
        echo "${haystack}" >&2
        exit 1
    fi
}

expect_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "FAIL: ${label}; unexpected ${needle}" >&2
        echo "${haystack}" >&2
        exit 1
    fi
}

expect_contains "${disk_line}" "/dev:7.2G:0:0%" "keeps devtmpfs"
expect_contains "${disk_line}" "/run:7.2G:755M:11%" "keeps tmpfs"
expect_contains "${disk_line}" "/:26G:18G:67%" "keeps root filesystem"
expect_contains "${disk_line}" "/data:264G:146G:58%" "keeps data filesystem"
expect_contains "${disk_line}" "/boot:1014M:167M:17%" "keeps boot filesystem"
expect_not_contains "${disk_line}" "docker_root" "drops docker overlay mounts"

expect_contains "${inode_line}" "/dev:400/1880000:1%" "keeps devtmpfs inode data"
expect_contains "${inode_line}" "/data:990000/138412032:1%" "keeps data inode data"
expect_not_contains "${inode_line}" "docker_root" "drops docker overlay inode data"

echo "PASS: disk collection keeps non-docker mounts and drops docker mounts"
