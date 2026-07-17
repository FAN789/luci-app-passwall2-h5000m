#!/bin/sh
set -eu

/etc/init.d/passwall2 stop >/dev/null 2>&1 || true
apk del luci-i18n-passwall2-zh-cn luci-app-passwall2
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "PassWall2 UI was removed. Shared proxy cores were kept for safe reuse."
