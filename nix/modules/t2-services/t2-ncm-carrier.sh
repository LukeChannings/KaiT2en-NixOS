# Kicks the T2 CDC-NCM link once after boot if it never gets a carrier.
#
# cdc_ncm only learns the link is up from bridgeOS's NETWORK_CONNECTION
# notification. When cdc_ncm binds in early boot, bridgeOS has not finished
# bringing its side up and never sends it, so the link sits without carrier
# (and NetworkManager never gives it an IPv6 link-local address) until the
# first suspend/resume reset-resumes the device. A later unbind/bind gets the
# notification within a second, with or without NetworkManager running.
#
# Local to the Nix layer: upstream ships no equivalent. Drop it once upstream
# gains a boot-time fix, or once the T2 reports carrier on the first bind.

grace=${T2_NCM_CARRIER_GRACE:-10}
settle=${T2_NCM_CARRIER_SETTLE:-15}
attempts=${T2_NCM_CARRIER_ATTEMPTS:-3}
drv=${T2_SYSFS:-/sys}/bus/usb/drivers/cdc_ncm

log() { printf 't2-ncm-carrier: %s\n' "$*" >&2; }

# The NCM control interface of the T2 controller (05ac:8233, CDC class 02,
# subclass 0d), matched like upstream's old is_t2_ncm_control.
find_ncm() {
	local dev parent
	for dev in "$drv"/*:*; do
		dev=$(readlink -f -- "$dev") || continue
		parent=${dev%/*}
		[[ -r $parent/idVendor && -r $parent/idProduct &&
			-r $dev/bInterfaceClass && -r $dev/bInterfaceSubClass ]] || continue
		[[ $(<"$parent/idVendor") == 05ac && $(<"$parent/idProduct") == 8233 &&
			$(<"$dev/bInterfaceClass") == 02 && $(<"$dev/bInterfaceSubClass") == 0d ]] || continue
		printf '%s\n' "${dev##*/}"
		return 0
	done
	return 1
}

# The netdev is renamed (eth0 -> enp...) on every bind, so look it up afresh.
# Reading carrier fails while the interface is down; that counts as no carrier.
has_carrier() {
	local net carrier
	for net in "$drv/$1"/net/*; do
		[[ -e $net ]] || continue
		carrier=$(cat -- "$net/carrier" 2>/dev/null) || continue
		[[ $carrier == 1 ]] && return 0
	done
	return 1
}

wait_carrier() {
	local i
	for ((i = 0; i < $2; i++)); do
		has_carrier "$1" && return 0
		sleep 1
	done
	has_carrier "$1"
}

if ! id=$(find_ncm); then
	log "no T2 NCM interface bound to cdc_ncm; nothing to do"
	exit 0
fi

if wait_carrier "$id" "$grace"; then
	log "$id has carrier"
	exit 0
fi

for ((n = 1; n <= attempts; n++)); do
	log "$id has no carrier; rebinding cdc_ncm (attempt $n/$attempts)"
	if [[ -e $drv/$id ]] && ! printf '%s' "$id" >"$drv/unbind"; then
		log "cannot unbind $id"
	fi
	sleep 2
	if [[ ! -e $drv/$id ]] && ! printf '%s' "$id" >"$drv/bind"; then
		log "cannot bind $id"
		continue
	fi
	if wait_carrier "$id" "$settle"; then
		log "$id has carrier after rebind"
		exit 0
	fi
done

log "$id still has no carrier after $attempts rebind(s); it will come up on the next resume"
exit 1
