# Universal ROM Crave Build Pipeline & Local Manifests for Xiaomi Mi A2 Lite (`daisy`)

This repository provides an all-in-one, turnkey solution for compiling **Android 16 / LineageOS 23.2 / Lunaris OS / crDroid / Evolution X** for the **Xiaomi Mi A2 Lite (`daisy`)** on Qualcomm Snapdragon 625 (MSM8953).

It combines:
- Verified device, kernel, and proprietary vendor trees.
- Legacy Qualcomm CAF MSM8996 display, audio, and media HALs.
- Automatic bug fixes from [`ximi-daisy/daisy_manifests`](https://github.com/ximi-daisy/daisy_manifests), [`TheGamerKing561/local_manifests`](https://github.com/TheGamerKing561/local_manifests), and [`android_vendor_extra-daisy`](https://github.com/frnAlt/android_vendor_extra-daisy).
- Fully automated in-flight patcher (`auto_patch.sh`) supporting all custom ROM variants.
- Cloud-ready Crave build script (`build.sh`) with error handling, crash logging, and artifact uploading.

---

## 📁 Repository Structure

```text
.
├── local_manifests.xml         # Unified universal local manifest
├── manifests/
│   ├── daisy.xml               # Clean hardware, device, vendor, kernel trees
│   ├── los_replacements.xml    # Replacements & removals for LineageOS/Lunaris builds
│   └── extra_features.xml      # ViPER4AndroidFX, Dolby, Datura, and signing keys
├── patches/
│   ├── 0003-run-recovery-permissive.patch
│   ├── 0004-sepolicy-allow-permissive-user.patch
│   ├── 0005-systeminfo-skip-per-process-GPU.patch
│   ├── 0006-remove-install-recovery.patch
│   ├── 0007-msm8996.patch
│   ├── 0011-fw_n-kill-gpuwork.patch
│   ├── 0012-setupwizard_skip.patch
│   ├── 0013-microg_user_build_fix.patch
│   ├── 0017-packages_modules_Connectivity-no-BTF.patch
│   └── legacy_compat/          # Universal per-project patches for any ROM type
│       ├── build_make/
│       ├── frameworks_native/
│       ├── hardware_interfaces/
│       ├── hardware_qcom-caf_common/
│       ├── hardware_qcom-caf_msm8996_audio/
│       ├── hardware_qcom-caf_msm8996_display/
│       ├── hardware_qcom-caf_wlan/
│       ├── hardware_qcom_wlan/
│       ├── kernel_configs/
│       ├── packages_modules_Connectivity/
│       └── system_memory_libmeminfo/
├── build.sh                    # Full automated Crave / local build pipeline
├── auto_patch.sh               # Standalone universal auto-patcher
├── crave.yaml                  # One-click Crave DevSpace config
└── README.md                   # Documentation and usage guide
```

---

## 🚀 Building on Crave

Run directly in Crave:

```bash
crave run -- "git clone https://github.com/frnAlt/daisy_crave_build.git /tmp/daisy_builder && bash /tmp/daisy_builder/build.sh daisy"
```

Or set custom ROM target:

```bash
# Example for LineageOS:
crave run -- "git clone https://github.com/frnAlt/daisy_crave_build.git /tmp/daisy_builder && ROM_NAME='LineageOS' REPO_INIT_URL='https://github.com/LineageOS/android' REPO_INIT_BRANCH='lineage-23.2' bash /tmp/daisy_builder/build.sh daisy"

# Example for Lunaris OS:
crave run -- "git clone https://github.com/frnAlt/daisy_crave_build.git /tmp/daisy_builder && ROM_NAME='Lunaris OS' REPO_INIT_URL='https://github.com/Lunaris-AOSP/android' REPO_INIT_BRANCH='16.2' bash /tmp/daisy_builder/build.sh daisy"

# Example for crDroid:
crave run -- "git clone https://github.com/frnAlt/daisy_crave_build.git /tmp/daisy_builder && ROM_NAME='crDroid' REPO_INIT_URL='https://github.com/crdroidandroid/android' REPO_INIT_BRANCH='16.0' bash /tmp/daisy_builder/build.sh daisy"
```

---

## 💻 Building Locally

```bash
# 1. Place the local manifest into your source tree
mkdir -p .repo/local_manifests/
cp local_manifests.xml .repo/local_manifests/daisy.xml

# 2. Sync sources
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc)

# 3. Apply all patches automatically
bash auto_patch.sh

# 4. Compile
source build/envsetup.sh
lunch lineage_daisy-userdebug
m bacon -j$(nproc)
```

---

## 🛠️ Automated Bug Fixes Included

1. **Permissive Recovery**: Removes restriction on permissive domain for recovery in user builds (`device/lineage/sepolicy`).
2. **Sepolicy Allow Permissive**: Bypasses Soong permissive check rejection on user builds (`system/sepolicy`).
3. **GPU Memory Tracing Crash**: Skips BPF `/sys/fs/bpf/map_gpuMem_gpu_mem_total_map` tracing if disabled in kernel, eliminating soft-reboots on 3.18/4.9 kernels (`system/memory/libmeminfo`).
4. **Remove `install-recovery.sh`**: Strips obsolete recovery flashing script during OTA package generation (`build/make`).
5. **MSM8996 CAF Namespace**: Generates `Android.bp` and `Android.mk` for `hardware/qcom-caf/msm8996` HAL namespace.
6. **Kill GpuWork on Legacy Kernels**: Disables BPF GpuWork features when running on pre-6.19 kernels (`frameworks/native`).
7. **Skip SetupWizard**: Enables the skip button across all build flavors (`packages/apps/SetupWizard`).
8. **MicroG Signature Spoofing**: Removes `isDebuggable()` check in `ComputerEngine.java` to support spoofing on user builds (`frameworks/base`).
9. **NetBpfLoad BTF Compatibility**: Adjusts BTF minimum kernel requirement from 4.19 to 5.15 (`packages/modules/Connectivity`).
10. **Legacy Compatibility Matrix & Kernel Configs**: Restores 4.9 and 4.4 configs and compatibility matrix for legacy device boot.
