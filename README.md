# Xiaomi Mi A2 Lite (daisy) - Custom ROM Build Manifests & Automated Build Pipeline

This repository provides an all-in-one, ready-to-build solution for compiling **Android 16 (LineageOS 23.2 / Lunaris OS 16.2)** for the **Xiaomi Mi A2 Lite (`daisy`)** on Qualcomm MSM8953 (Snapdragon 625).

It integrates the complete trees and replacement recipes from [`ximi-daisy/daisy_manifests`](https://github.com/ximi-daisy/daisy_manifests), structured in the [`frnAlt`](https://github.com/frnAlt) manifest and build script architecture, with fully automated in-flight patching for all known Android 16 / MSM8953 compilation and runtime bugs.

---

## 📁 Repository Structure

```text
.
├── local_manifests.xml         # Unified local manifest for repo sync
├── manifests/
│   ├── daisy.xml               # Device, vendor, kernel, and hardware trees
│   ├── los_replacements.xml    # Legacy MSM8953 CAF & LineageOS replacements/removals
│   └── extra_features.xml      # ViPER4AndroidFX, Dolby, Datura, and signing keys
├── patches/                    # All 9 standalone bug-fix patches from ximi-daisy
│   ├── 0003-run-recovery-permissive.patch
│   ├── 0004-sepolicy-allow-permissive-user.patch
│   ├── 0005-systeminfo-skip-per-process-GPU.patch
│   ├── 0006-remove-install-recovery.patch
│   ├── 0007-msm8996.patch
│   ├── 0011-fw_n-kill-gpuwork.patch
│   ├── 0012-setupwizard_skip.patch
│   ├── 0013-microg_user_build_fix.patch
│   └── 0017-packages_modules_Connectivity-no-BTF.patch
├── build.sh                    # Full Crave / local automated build pipeline
├── auto_patch.sh               # Standalone auto-patcher utility
├── crave.yaml                  # Optional Crave DevSpace config
└── README.md                   # Documentation and usage guide
```

---

## 🚀 Quick Start

### 1. Build via Crave (Recommended)

Run directly on Crave cloud builder:

```bash
crave run -- "git clone https://github.com/<your-username>/daisy_build_manifests.git /tmp/daisy_builder && bash /tmp/daisy_builder/build.sh daisy"
```

Or clone this repository into your Crave workspace and run:

```bash
bash build.sh daisy
```

### 2. Build Locally / In an Existing Source Tree

If you already have your Android source initialized:

```bash
# 1. Place the local manifest into your source tree:
mkdir -p .repo/local_manifests/
cp local_manifests.xml .repo/local_manifests/daisy.xml

# 2. Sync the repositories:
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc)

# 3. Apply the automatic bug-fix patches:
bash auto_patch.sh

# 4. Initialize build environment and compile:
source build/envsetup.sh
lunch lineage_daisy-userdebug
m bacon -j$(nproc)
```

---

## 🛠️ Automated Bug Fixes Included

The build pipeline and `auto_patch.sh` automatically detect and resolve legacy MSM8953 compatibility issues on Android 16:

| # | Patch File | Target Component | Description & Root Cause |
|---|------------|------------------|--------------------------|
| **1** | `0003-run-recovery-permissive.patch` | `device/lineage/sepolicy` | Ensures recovery runs in permissive domain on `user` builds to prevent bootloader recovery bootloops. |
| **2** | `0004-sepolicy-allow-permissive-user.patch` | `system/sepolicy` | Bypasses the Soong build assertion that rejects permissive domains on user builds. |
| **3** | `0005-systeminfo-skip-per-process-GPU.patch` | `system/memory` (`libmeminfo`) | Prevents device crash and soft-reboot by skipping GPU memory BPF tracing if `CONFIG_TRACE_GPU_MEM` is not enabled in the kernel. |
| **4** | `0006-remove-install-recovery.patch` | `build/make` (`releasetools`) | Removes redundant `install-recovery.sh` packaging on A/B devices to prevent OTA packaging errors. |
| **5** | `0007-msm8996.patch` | `hardware/qcom-caf/msm8996` | Creates `Android.bp` (Soong namespace) and `Android.mk` so audio, display, and media HALs are parsed properly by Soong/Kati. |
| **6** | `0011-fw_n-kill-gpuwork.patch` | `frameworks/native` | Disables GpuWork BPF features when running on pre-6.19 kernels (fixing crashes on legacy 3.18/4.9 kernels). |
| **7** | `0012-setupwizard_skip.patch` | `packages/apps/SetupWizard` | Enables the "Skip" button in Lineage SetupWizard across all build variants (`user`, `userdebug`, `eng`). |
| **8** | `0013-microg_user_build_fix.patch` | `frameworks/base` | Removes `isDebuggable()` check so microG signature spoofing works out-of-the-box on user builds. |
| **9** | `0017-packages_modules_Connectivity-no-BTF.patch` | `packages/modules/Connectivity` | Adjusts `NetBpfLoad` BTF check from 4.19 to 5.15, avoiding fatal aborts on legacy kernels without BTF. |

---

## 📦 Trees & Repositories Used

All repositories are sourced from verified Android 16 / LineageOS 23.2 trees:

- **Device Tree**: [`ximi-daisy/android_device_xiaomi_daisy`](https://github.com/ximi-daisy/android_device_xiaomi_daisy) (`16.2`)
- **Common Device Tree**: [`ximi-daisy/android_device_xiaomi_msm8953-common`](https://github.com/ximi-daisy/android_device_xiaomi_msm8953-common) (`16.2`)
- **Vendor Tree**: [`ximi-daisy/proprietary_vendor_xiaomi_daisy`](https://github.com/ximi-daisy/proprietary_vendor_xiaomi_daisy) (`16`)
- **Common Vendor Tree**: [`ximi-daisy/proprietary_vendor_xiaomi_msm8953-common`](https://github.com/ximi-daisy/proprietary_vendor_xiaomi_msm8953-common) (`16.2`)
- **Kernel Tree**: [`ximi-daisy/android_kernel_xiaomi_msm8953`](https://github.com/ximi-daisy/android_kernel_xiaomi_msm8953) (`lineage-23.2`)
- **Hardware Xiaomi**: [`LineageOS/android_hardware_xiaomi`](https://github.com/LineageOS/android_hardware_xiaomi) (`lineage-23.2`)
- **Hardware Sony Timekeep**: [`LineageOS/android_hardware_sony_timekeep`](https://github.com/LineageOS/android_hardware_sony_timekeep) (`lineage-23.2`)
- **Tweaked Build System**: [`ximi-daisy/android_build`](https://github.com/ximi-daisy/android_build) (`lineage-23.2-tweaked`)
- **Tweaked Interfaces**: [`ximi-daisy/android_hardware_interfaces`](https://github.com/ximi-daisy/android_hardware_interfaces) (`lineage-23.2-tweaked`)
- **Tweaked WLAN HAL**: [`ximi-daisy/android_hardware_qcom_wlan`](https://github.com/ximi-daisy/android_hardware_qcom_wlan) (`lineage-23.2-tweaked` & `lineage-23.2-caf-tweaked`)
- **Tweaked Connectivity**: [`ximi-daisy/android_packages_modules_Connectivity`](https://github.com/ximi-daisy/android_packages_modules_Connectivity) (`lineage-23.2-tweaked`)
- **Tweaked BPF**: [`ximi-daisy/android_system_bpf`](https://github.com/ximi-daisy/android_system_bpf) (`lineage-23.2-tweaked`)
- **Qualcomm 8996 Display/Audio/Media HALs**:
  - `hardware/qcom-caf/msm8996/media`: [`LineageOS/android_hardware_qcom_media`](https://github.com/LineageOS/android_hardware_qcom_media) (`lineage-22.2-caf-msm8996`)
  - `hardware/qcom-caf/msm8996/display`: [`ximi-daisy/android_hardware_qcom_display`](https://github.com/ximi-daisy/android_hardware_qcom_display) (`lineage-23.2-caf-msm8996`)
  - `hardware/qcom-caf/msm8996/audio`: [`ximi-daisy/android_hardware_qcom_audio`](https://github.com/ximi-daisy/android_hardware_qcom_audio) (`lineage-23.2-caf-msm8996`)

---

## ⚡ Build Script Features

`build.sh` contains enterprise-grade pipeline features adapted from `frnAlt/Scripts`:
- **Dual-Pipe Logging**: Live stdout in terminal while recording timestamped logs (`build_daisy_*.log`).
- **Crash Log Uploads**: Automatically uploads `.log.gz` and `out/siso_failed_commands.sh` to Gofile (with Pixeldrain fallback) on build failure.
- **OTA Metadata Generation**: Generates `${DEVICE}.json` with maintainer metadata, sha256, md5, and size for OTA updater support.
- **Parallel Artifact Upload**: Uploads ROM zip, kernel partition images (`boot.img`, `recovery.img`, `dtbo.img`), and JSON metadata in parallel with direct master links.
- **Fail-Safe Idempotence**: All patching and sanitization functions can be run repeatedly without breaking existing modifications.
