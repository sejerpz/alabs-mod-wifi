/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * What the v6.6 driver uses and the MOD Duo X kernels (4.4.167 and 4.9.123)
 * don't have. Nothing here changes the build on the Dwarf kernel (6.1).
 */

#ifndef _RTL8XXXU_COMPAT_H
#define _RTL8XXXU_COMPAT_H

#include <linux/version.h>
#include <linux/leds.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 0)
#include <linux/bitfield.h>
#endif

#ifndef fallthrough
#define fallthrough do {} while (0)  /* fallthrough */
#endif

#ifndef FIELD_PREP
#define FIELD_PREP(_mask, _val) \
	((typeof(_mask))(((typeof(_mask))(_val) << __builtin_ctzll(_mask)) & (_mask)))
#define FIELD_GET(_mask, _reg) \
	((typeof(_mask))(((_reg) & (_mask)) >> __builtin_ctzll(_mask)))
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 18, 0)
/* typed bitfield helpers of include/linux/bitfield.h (4.18) */
static inline u32 __rtl_field_mul(u32 field)
{
	return field & -field;
}

#define __RTL_MAKE_BITS(type, to, from)					\
static inline type type##_encode_bits(type v, type field)		\
{									\
	return to((v * __rtl_field_mul(field)) & field);		\
}									\
static inline type type##_get_bits(type v, type field)		\
{									\
	return (from(v) & field) / __rtl_field_mul(field);		\
}									\
static inline void type##p_replace_bits(type *p, type val, type field)	\
{									\
	*p = (*p & ~to(field)) | type##_encode_bits(val, field);	\
}

#define __rtl_id(x) (x)
__RTL_MAKE_BITS(u8, __rtl_id, __rtl_id)
__RTL_MAKE_BITS(u32, __rtl_id, __rtl_id)
#undef __rtl_id
#undef __RTL_MAKE_BITS

static inline __le32 le32_encode_bits(u32 v, u32 field)
{
	return cpu_to_le32((v * __rtl_field_mul(field)) & field);
}
#endif

/* station link and interface settings of mac80211 (multi-link, 5.19 and 6.0) */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)
#define rtl_sta_link(sta)	(&(sta)->deflink)
#define rtl_vif_cfg(vif)	(&(vif)->cfg)
#else
#define rtl_sta_link(sta)	(sta)
#define rtl_vif_cfg(vif)	(&(vif)->bss_conf)
#endif

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 0, 0)
#define LED_ON 1
#endif

/* beacon of a link (6.0) */
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 0, 0)
#define ieee80211_beacon_get(hw, vif, link_id) ieee80211_beacon_get(hw, vif)
#endif

#endif
