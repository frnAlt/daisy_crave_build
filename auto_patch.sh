#!/bin/bash
# ==============================================================================
# Universal Auto-Patch & Bug-Fix Routine for Xiaomi Mi A2 Lite (daisy)
# Android 16 / LineageOS 23.2 / Lunaris OS / crDroid / Evolution X / AOSP (msm8953)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/patches"
LEGACY_DIR="${PATCHES_DIR}/legacy_compat"

# If executed directly inside an Android build tree root
ANDROID_ROOT="${ANDROID_ROOT:-$PWD}"

echo "============================================================"
echo "[DAISY AUTO-PATCH] Initializing universal auto-patcher for daisy..."
echo "[DAISY AUTO-PATCH] Workspace root: ${ANDROID_ROOT}"
echo "============================================================"

# Helper: safely apply patch with git apply
apply_patch_safe() {
    local target_dir="$1"
    local patch_name="$2"
    local patch_file="${PATCHES_DIR}/${patch_name}"
    local desc="$3"

    echo "[AUTO-PATCH] Checking: ${desc} (${patch_name})..."

    if [ ! -d "${ANDROID_ROOT}/${target_dir}" ]; then
        echo "[AUTO-PATCH] Target directory '${target_dir}' not found. Skipping."
        return 0
    fi

    # Download patch on the fly if not locally present in PATCHES_DIR
    if [ ! -f "$patch_file" ]; then
        echo "[AUTO-PATCH] Downloading ${patch_name} from upstream..."
        mkdir -p "${PATCHES_DIR}"
        curl -sL "https://raw.githubusercontent.com/ximi-daisy/daisy_manifests/master/lineageos-23.2/${patch_name}" -o "$patch_file" || true
    fi

    if [ -f "$patch_file" ]; then
        # Check if patch applies cleanly
        if git -C "${ANDROID_ROOT}/${target_dir}" apply --check "$patch_file" >/dev/null 2>&1; then
            git -C "${ANDROID_ROOT}/${target_dir}" apply --ignore-whitespace "$patch_file"
            echo "✅ [AUTO-PATCH] Successfully applied ${patch_name} to ${target_dir}"
            return 0
        elif git -C "${ANDROID_ROOT}/${target_dir}" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
            echo "ℹ️  [AUTO-PATCH] ${patch_name} is already applied in ${target_dir}. Skipping."
            return 0
        fi
    fi

    return 1
}

# ------------------------------------------------------------------------------
# 1. Permissive Recovery Patch (device/lineage/sepolicy or sepolicy)
# ------------------------------------------------------------------------------
patch_recovery_permissive() {
    local te_file="${ANDROID_ROOT}/device/lineage/sepolicy/common/private/recovery.te"

    if [ -f "$te_file" ]; then
        if grep -q "userdebug_or_eng" "$te_file" && grep -q "permissive recovery;" "$te_file"; then
            echo "[AUTO-FIX] Unwrapping 'permissive recovery;' in ${te_file}..."
            sed -i '/userdebug_or_eng(`/{n;d}' "$te_file" 2>/dev/null || true
            sed -i 's/userdebug_or_eng(`//g' "$te_file" 2>/dev/null || true
            sed -i "/^')/d" "$te_file" 2>/dev/null || true
            echo "✅ [AUTO-FIX] Recovery permissive domain enabled for user builds."
        else
            echo "ℹ️  [AUTO-FIX] Recovery permissive rule already active or not found."
        fi
    else
        apply_patch_safe "device/lineage/sepolicy" "0003-run-recovery-permissive.patch" "Run recovery permissive" || true
    fi
}

# ------------------------------------------------------------------------------
# 2. Sepolicy Allow Permissive User Builds (system/sepolicy)
# ------------------------------------------------------------------------------
patch_sepolicy_permissive_user() {
    local target="system/sepolicy"
    local policy_go="${ANDROID_ROOT}/${target}/build/soong/policy.go"

    if [ -f "$policy_go" ]; then
        if grep -q "ERROR: permissive domains not allowed in user builds" "$policy_go"; then
            echo "[AUTO-FIX] Disabling strict permissive check on user builds in ${policy_go}..."
            sed -i 's/if !ctx.Config().Debuggable() {/if false \&\& !ctx.Config().Debuggable() {/g' "$policy_go" 2>/dev/null || true
            echo "✅ [AUTO-FIX] Sepolicy permissive domains check bypassed for user builds."
        else
            echo "ℹ️  [AUTO-FIX] Sepolicy user permissive check already patched."
        fi
    else
        apply_patch_safe "$target" "0004-sepolicy-allow-permissive-user.patch" "Sepolicy permissive user check" || true
    fi
}

# ------------------------------------------------------------------------------
# 3. Systeminfo Skip Per-Process GPU Memory Trace (system/memory)
# ------------------------------------------------------------------------------
patch_sysmeminfo_gpu() {
    local target="system/memory"
    local cpp_file="${ANDROID_ROOT}/${target}/libmeminfo/sysmeminfo.cpp"

    if [ -f "$cpp_file" ]; then
        if ! grep -q "GpuMem tracing is disabled in kernel" "$cpp_file"; then
            echo "[AUTO-FIX] Injecting legacy kernel GPU memory BPF check in ${cpp_file}..."
            if apply_patch_safe "$target" "0005-systeminfo-skip-per-process-GPU.patch" "Skip per-process GPU memory trace"; then
                return 0
            fi

            # Fallback Python insertion
            python3 - <<EOF 2>/dev/null || true
import sys

file_path = "${cpp_file}"
with open(file_path, "r") as f:
    content = f.read()

target = 'static constexpr const char kBpfGpuMemTotalMap[] = "/sys/fs/bpf/map_gpuMem_gpu_mem_total_map";'
replacement = '''static constexpr const char kBpfGpuMemTotalMap[] = "/sys/fs/bpf/map_gpuMem_gpu_mem_total_map";

    if (access(kBpfGpuMemTotalMap, F_OK)) {
        LOG(ERROR) << "ReadPerProcessGpuMem: GpuMem tracing is disabled in kernel. Skipping!";
        return false;
    }'''

if target in content and "GpuMem tracing is disabled in kernel" not in content:
    content = content.replace(target, replacement, 1)
    replacement_kb = '''static constexpr const char kBpfGpuMemTotalMap[] = "/sys/fs/bpf/map_gpuMem_gpu_mem_total_map";

    if (access(kBpfGpuMemTotalMap, F_OK)) {
        LOG(ERROR) << "ReadProcessGpuUsageKb: GpuMem tracing is disabled in kernel. Skipping!";
        return false;
    }'''
    if target in content:
        content = content.replace(target, replacement_kb, 1)
    with open(file_path, "w") as f:
        f.write(content)
    print("✅ [AUTO-FIX] sysmeminfo.cpp patched via fallback.")
EOF
        else
            echo "ℹ️  [AUTO-FIX] sysmeminfo GPU memory trace check already present."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 4. Remove install-recovery.sh from OTA Tools (build/make)
# ------------------------------------------------------------------------------
patch_build_make_install_recovery() {
    local target="build/make"
    local common_py="${ANDROID_ROOT}/${target}/tools/releasetools/common.py"

    if [ -f "$common_py" ]; then
        if grep -q 'sh_location = os.path.join(sh_dir, "install-recovery.sh")' "$common_py"; then
            echo "[AUTO-FIX] Removing redundant install-recovery.sh generation from ${common_py}..."
            sed -i '/sh_location = os.path.join(sh_dir, "install-recovery.sh")/d' "$common_py" 2>/dev/null || true
            echo "✅ [AUTO-FIX] install-recovery.sh removed from releasetools."
        else
            echo "ℹ️  [AUTO-FIX] install-recovery.sh check already patched or absent."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 5. MSM8996 CAF Hardware Namespace Creation (hardware/qcom-caf/msm8996)
# ------------------------------------------------------------------------------
setup_msm8996_caf_namespace() {
    local target_dir="${ANDROID_ROOT}/hardware/qcom-caf/msm8996"
    mkdir -p "$target_dir"

    # Android.bp
    if [ ! -f "${target_dir}/Android.bp" ]; then
        echo "[AUTO-FIX] Creating ${target_dir}/Android.bp (soong_namespace)..."
        cat << 'EOF' > "${target_dir}/Android.bp"
soong_namespace {
}
EOF
        echo "✅ [AUTO-FIX] Created hardware/qcom-caf/msm8996/Android.bp"
    fi

    # Android.mk
    if [ ! -f "${target_dir}/Android.mk" ]; then
        echo "[AUTO-FIX] Creating ${target_dir}/Android.mk (sub-makefiles)..."
        cat << 'EOF' > "${target_dir}/Android.mk"
LOCAL_PATH := $(call my-dir)
ifneq ($(filter $(LOCAL_PATH),$(PRODUCT_SOONG_NAMESPACES)),)
ifneq ($(BUILD_WITHOUT_VENDOR), true)
include $(call first-makefiles-under,$(LOCAL_PATH))
endif
endif
EOF
        echo "✅ [AUTO-FIX] Created hardware/qcom-caf/msm8996/Android.mk"
    fi
}

# ------------------------------------------------------------------------------
# 6. Kill GpuWork on Legacy Kernels (frameworks/native)
# ------------------------------------------------------------------------------
patch_frameworks_native_gpuwork() {
    local target="frameworks/native"
    local gpuwork_cpp="${ANDROID_ROOT}/${target}/services/gpuservice/gpuwork/GpuWork.cpp"

    if [ -f "$gpuwork_cpp" ]; then
        if ! grep -q "Legacy kernel detected. Disabling GpuWork BPF features." "$gpuwork_cpp"; then
            echo "[AUTO-FIX] Disabling GpuWork BPF on legacy kernels in ${gpuwork_cpp}..."
            if apply_patch_safe "$target" "0011-fw_n-kill-gpuwork.patch" "Kill GpuWork on legacy kernels"; then
                return 0
            fi

            # Fallback
            python3 - <<EOF 2>/dev/null || true
file_path = "${gpuwork_cpp}"
with open(file_path, "r") as f:
    content = f.read()

target = "void GpuWork::initialize() {"
replacement = """void GpuWork::initialize() {
    if (!bpf::isAtLeastKernelVersion(6, 19, 0)) {
        ALOGI("Legacy kernel detected. Disabling GpuWork BPF features.");
        mInitialized.store(false);
        return;
    }"""

if target in content and "Legacy kernel detected" not in content:
    content = content.replace(target, replacement, 1)
    with open(file_path, "w") as f:
        f.write(content)
    print("✅ [AUTO-FIX] GpuWork.cpp patched via fallback.")
EOF
        else
            echo "ℹ️  [AUTO-FIX] GpuWork legacy kernel bypass already active."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 7. SetupWizard Skip Button on All Builds (packages/apps/SetupWizard)
# ------------------------------------------------------------------------------
patch_setupwizard_skip() {
    local target="packages/apps/SetupWizard"
    local welcome_java="${ANDROID_ROOT}/${target}/src/org/lineageos/setupwizard/WelcomeActivity.java"

    if [ -f "$welcome_java" ]; then
        if grep -q 'if (Build.TYPE.equals("eng"))' "$welcome_java"; then
            echo "[AUTO-FIX] Enabling SetupWizard skip button on all build types in ${welcome_java}..."
            sed -i '/if (Build.TYPE.equals("eng"))/d' "$welcome_java" 2>/dev/null || true
            echo "✅ [AUTO-FIX] SetupWizard skip button enabled."
        else
            echo "ℹ️  [AUTO-FIX] SetupWizard skip button already enabled."
        fi
    else
        apply_patch_safe "$target" "0012-setupwizard_skip.patch" "SetupWizard skip button" || true
    fi
}

# ------------------------------------------------------------------------------
# 8. MicroG Signature Spoofing on User Builds (frameworks/base)
# ------------------------------------------------------------------------------
patch_microg_user_build() {
    local target="frameworks/base"
    local engine_java="${ANDROID_ROOT}/${target}/services/core/java/com/android/server/pm/ComputerEngine.java"

    if [ -f "$engine_java" ]; then
        if grep -q 'public static boolean isMicrogSigned' "$engine_java"; then
            echo "[AUTO-FIX] Checking MicroG isDebuggable check in ${engine_java}..."
            python3 - <<EOF 2>/dev/null || true
file_path = "${engine_java}"
with open(file_path, "r") as f:
    lines = f.readlines()

out = []
in_func = False
skip_next = 0

for line in lines:
    if "public static boolean isMicrogSigned" in line:
        in_func = True
    if in_func and "if (!isDebuggable())" in line:
        skip_next = 3
        in_func = False
        continue
    if skip_next > 0:
        skip_next -= 1
        continue
    out.append(line)

with open(file_path, "w") as f:
    f.writelines(out)
print("✅ [AUTO-FIX] MicroG spoofing check patched for user builds.")
EOF
        else
            echo "ℹ️  [AUTO-FIX] ComputerEngine MicroG spoofing signature method not found."
        fi
    else
        apply_patch_safe "$target" "0013-microg_user_build_fix.patch" "MicroG user build fix" || true
    fi
}

# ------------------------------------------------------------------------------
# 9. NetBpfLoad BTF pre-5.15 Bypass (packages/modules/Connectivity)
# ------------------------------------------------------------------------------
patch_connectivity_netbpfload() {
    local target="packages/modules/Connectivity"
    local bpf_file="${ANDROID_ROOT}/${target}/bpf/loader/NetBpfLoad.cpp"

    if [ -f "$bpf_file" ]; then
        if grep -q "isAtLeastKernelVersion(4, 19)" "$bpf_file"; then
            echo "[AUTO-FIX] Relaxing BTF kernel requirement to 5.15 in ${bpf_file}..."
            sed -i 's/isAtLeastKernelVersion(4, 19)/isAtLeastKernelVersion(5, 15)/g' "$bpf_file" 2>/dev/null || true
            echo "✅ [AUTO-FIX] NetBpfLoad BTF check relaxed to 5.15."
        else
            echo "ℹ️  [AUTO-FIX] NetBpfLoad BTF check already updated or not present."
        fi
    else
        apply_patch_safe "$target" "0017-packages_modules_Connectivity-no-BTF.patch" "NetBpfLoad no BTF on pre-5.15" || true
    fi
}

# ------------------------------------------------------------------------------
# 10. Apply Universal Legacy Compatibility Patches (for all ROM types)
# ------------------------------------------------------------------------------
apply_all_legacy_compat_patches() {
    if [ ! -d "${LEGACY_DIR}" ]; then
        return 0
    fi

    echo "[DAISY AUTO-PATCH] Scanning and applying universal legacy compat patches..."

    for proj_dir in "${LEGACY_DIR}"/*/; do
        [ -d "$proj_dir" ] || continue
        proj_dir=${proj_dir%/}
        local folder_name="${proj_dir##*/}"

        local proj_path=""
        case "${folder_name}" in
            build_make)
                proj_path="build/make"
                ;;
            frameworks_native)
                proj_path="frameworks/native"
                ;;
            hardware_interfaces)
                proj_path="hardware/interfaces"
                ;;
            hardware_qcom-caf_common)
                proj_path="hardware/qcom-caf/common"
                ;;
            hardware_qcom-caf_msm8996_audio)
                proj_path="hardware/qcom-caf/msm8996/audio"
                ;;
            hardware_qcom-caf_msm8996_display)
                proj_path="hardware/qcom-caf/msm8996/display"
                ;;
            hardware_qcom-caf_wlan)
                proj_path="hardware/qcom-caf/wlan"
                ;;
            hardware_qcom_wlan)
                proj_path="hardware/qcom/wlan"
                ;;
            kernel_configs)
                proj_path="kernel/configs"
                ;;
            packages_modules_Connectivity)
                proj_path="packages/modules/Connectivity"
                ;;
            system_memory_libmeminfo)
                proj_path="system/memory"
                ;;
            *)
                proj_path=$(echo "${folder_name}" | tr '_' '/')
                ;;
        esac

        if [ -d "${ANDROID_ROOT}/${proj_path}" ]; then
            for patch_f in "${proj_dir}"/*.patch; do
                [ -f "$patch_f" ] || continue
                local p_base=$(basename "$patch_f")
                if git -C "${ANDROID_ROOT}/${proj_path}" apply --check "$patch_f" >/dev/null 2>&1; then
                    echo "[AUTO-PATCH] Applying legacy compat patch: ${folder_name}/${p_base}..."
                    git -C "${ANDROID_ROOT}/${proj_path}" apply --ignore-whitespace "$patch_f" 2>/dev/null || true
                fi
            done
        fi
    done
}

# ------------------------------------------------------------------------------
# 11. Vendor Extra vendorsetup.sh Hook
# ------------------------------------------------------------------------------
run_vendor_extra_hook() {
    if [ -f "${ANDROID_ROOT}/vendor/extra/vendorsetup.sh" ]; then
        echo "[DAISY AUTO-PATCH] Executing vendor/extra/vendorsetup.sh..."
        (
            cd "${ANDROID_ROOT}"
            export APPLY_LEGACY_KERNEL_PATCHES=true
            export APPLY_PATCHES=true
            bash "${ANDROID_ROOT}/vendor/extra/vendorsetup.sh" || true
        )
    fi
}

# ------------------------------------------------------------------------------
# 12. Ensure Missing Daisy Repositories from daisy_a16_recipe.sh are Present
# ------------------------------------------------------------------------------
ensure_daisy_trees() {
    echo "[DAISY AUTO-PATCH] Verifying essential device, vendor, kernel, and HAL trees..."

    # Device Tree
    if [ ! -d "${ANDROID_ROOT}/device/xiaomi/daisy" ]; then
        echo "[AUTO-FETCH] Cloning device/xiaomi/daisy (branch 16.2)..."
        git clone --depth=1 --branch 16.2 https://github.com/frnAlt/android_device_xiaomi_daisy "${ANDROID_ROOT}/device/xiaomi/daisy" || \
        git clone --depth=1 --branch 16.2 https://github.com/ximi-daisy/android_device_xiaomi_daisy "${ANDROID_ROOT}/device/xiaomi/daisy"
    fi

    # Common Device Tree
    if [ ! -d "${ANDROID_ROOT}/device/xiaomi/msm8953-common" ]; then
        echo "[AUTO-FETCH] Cloning device/xiaomi/msm8953-common (branch 16.2)..."
        git clone --depth=1 --branch 16.2 https://github.com/frnAlt/android_device_xiaomi_msm8953-common "${ANDROID_ROOT}/device/xiaomi/msm8953-common" || \
        git clone --depth=1 --branch 16.2 https://github.com/ximi-daisy/android_device_xiaomi_msm8953-common "${ANDROID_ROOT}/device/xiaomi/msm8953-common"
    fi

    # Vendor Tree
    if [ ! -d "${ANDROID_ROOT}/vendor/xiaomi/daisy" ]; then
        echo "[AUTO-FETCH] Cloning vendor/xiaomi/daisy (branch 16)..."
        git clone --depth=1 --branch 16 https://github.com/frnAlt/proprietary_vendor_xiaomi_daisy "${ANDROID_ROOT}/vendor/xiaomi/daisy" || \
        git clone --depth=1 --branch 16 https://github.com/ximi-daisy/proprietary_vendor_xiaomi_daisy "${ANDROID_ROOT}/vendor/xiaomi/daisy"
    fi

    # Common Vendor Tree
    if [ ! -d "${ANDROID_ROOT}/vendor/xiaomi/msm8953-common" ]; then
        echo "[AUTO-FETCH] Cloning vendor/xiaomi/msm8953-common (branch 16.2)..."
        git clone --depth=1 --branch 16.2 https://github.com/frnAlt/proprietary_vendor_xiaomi_msm8953-common "${ANDROID_ROOT}/vendor/xiaomi/msm8953-common" || \
        git clone --depth=1 --branch 16.2 https://github.com/ximi-daisy/proprietary_vendor_xiaomi_msm8953-common "${ANDROID_ROOT}/vendor/xiaomi/msm8953-common"
    fi

    # Fingerprint Opensource Interfaces
    if [ ! -d "${ANDROID_ROOT}/vendor/fingerprint/opensource/interfaces" ]; then
        echo "[AUTO-FETCH] Cloning vendor/fingerprint/opensource/interfaces (branch lineage-21)..."
        git clone --depth=1 --branch lineage-21 https://github.com/frnAlt/android_vendor_fingerprint_opensource_interfaces "${ANDROID_ROOT}/vendor/fingerprint/opensource/interfaces" || \
        git clone --depth=1 --branch lineage-21 https://github.com/ximi-daisy/android_vendor_fingerprint_opensource_interfaces "${ANDROID_ROOT}/vendor/fingerprint/opensource/interfaces"
    fi

    # Kernel Tree
    if [ ! -d "${ANDROID_ROOT}/kernel/xiaomi/msm8953" ]; then
        echo "[AUTO-FETCH] Cloning kernel/xiaomi/msm8953 (branch lineage-23.2)..."
        git clone --depth=1 --branch lineage-23.2 https://github.com/frnAlt/android_kernel_xiaomi_msm8953 "${ANDROID_ROOT}/kernel/xiaomi/msm8953" || \
        git clone --depth=1 --branch lineage-23.2 https://github.com/ximi-daisy/android_kernel_xiaomi_msm8953/ "${ANDROID_ROOT}/kernel/xiaomi/msm8953"
    fi

    # Hardware Xiaomi
    if [ ! -d "${ANDROID_ROOT}/hardware/xiaomi" ]; then
        echo "[AUTO-FETCH] Cloning hardware/xiaomi (branch lineage-23.2)..."
        git clone --depth=1 --branch lineage-23.2 https://github.com/LineageOS/android_hardware_xiaomi "${ANDROID_ROOT}/hardware/xiaomi"
    fi

    # Hardware Sony Timekeep
    if [ ! -d "${ANDROID_ROOT}/hardware/sony/timekeep" ]; then
        echo "[AUTO-FETCH] Cloning hardware/sony/timekeep (branch lineage-23.2)..."
        git clone --depth=1 --branch lineage-23.2 https://github.com/LineageOS/android_hardware_sony_timekeep "${ANDROID_ROOT}/hardware/sony/timekeep"
    fi

    # Legacy Qualcomm MSM8996 Media HAL
    if [ ! -d "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/media" ]; then
        echo "[AUTO-FETCH] Cloning hardware/qcom-caf/msm8996/media (lineage-22.2-caf-msm8996)..."
        git clone --depth=1 --branch lineage-22.2-caf-msm8996 https://github.com/LineageOS/android_hardware_qcom_media "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/media"
    fi

    # Legacy Qualcomm MSM8996 Display HAL
    if [ ! -d "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/display" ]; then
        echo "[AUTO-FETCH] Cloning hardware/qcom-caf/msm8996/display (lineage-22.2-caf-msm8996)..."
        git clone --depth=1 --branch lineage-22.2-caf-msm8996 https://github.com/LineageOS/android_hardware_qcom_display "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/display"
    fi

    # Legacy Qualcomm MSM8996 Audio HAL
    if [ ! -d "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/audio" ]; then
        echo "[AUTO-FETCH] Cloning hardware/qcom-caf/msm8996/audio (lineage-22.2-caf-msm8996)..."
        git clone --depth=1 --branch lineage-22.2-caf-msm8996 https://github.com/LineageOS/android_hardware_qcom_audio "${ANDROID_ROOT}/hardware/qcom-caf/msm8996/audio"
    fi
}

# ------------------------------------------------------------------------------
# Master Auto-Patch Execution
# ------------------------------------------------------------------------------
run_all_daisy_patches() {
    echo "[DAISY AUTO-PATCH] Executing universal automated patch suite..."
    patch_recovery_permissive
    patch_sepolicy_permissive_user
    patch_sysmeminfo_gpu
    patch_build_make_install_recovery
    setup_msm8996_caf_namespace
    patch_frameworks_native_gpuwork
    patch_setupwizard_skip
    patch_microg_user_build
    patch_connectivity_netbpfload
    apply_all_legacy_compat_patches
    run_vendor_extra_hook
    ensure_daisy_trees
    echo "============================================================"
    echo "🎉 [DAISY AUTO-PATCH] Universal patch suite completed successfully!"
    echo "============================================================"
}

run_all_daisy_patches
