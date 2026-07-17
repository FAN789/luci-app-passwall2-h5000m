# Third-party components

Release archives contain redistributable OpenWrt APK packages built from the
following pinned feeds:

- OpenWrt packages: `ebb7c18a5d50fee8e79b0ee3e604da1e7339914b`
- OpenWrt LuCI: `25b3d5b9908687dceabe7804b4003ce345323ced`
- OpenWrt routing: `c7872431105f69894201dc522b7560e47d1e8ba9`
- OpenWrt telephony: `5d68d53c160a325ea9d03fce393e051573bcc736`
- kenzok8/small-package: `fd17d0c9aaafe1c170b0680718ff19aed8dd275e`

PassWall2 originates from `xiaorouji/openwrt-passwall2`. Xray Core, sing-box,
V2Ray data packages, v2ray-plugin, GeoView and their libraries retain their
respective upstream licenses and copyright notices. The H5000M wrapper's MIT
license does not replace or relax those licenses.

The only PassWall2 source adjustment in this release is recorded in
`patches/001-passwall2-empty-nftset-guard.patch`.
