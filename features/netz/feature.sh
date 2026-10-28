# netz – IPv4 vor IPv6 bevorzugen (B10: halb funktionierendes IPv6 im Heimnetz)
# shellcheck shell=bash disable=SC2034,SC2086  # Kennwerte liest ./setup; $SUDO/$PACKAGES absichtlich ungequotet
TITLE="IPv4 zuerst"
DESC="IPv4 vor IPv6 bevorzugen – gegen abbrechende Downloads bei halbem IPv6"
DEFAULT=1
NEEDS="basis"
PACKAGES=""

feature_install() {
    # Gilt für alle Programme (apt, curl, wget, pip, uv, git); IPv6 bleibt als Ausweich
    sys_line /etc/gai.conf "precedence ::ffff:0:0/96  100"
    ok "/etc/gai.conf: IPv4 zuerst"
}
