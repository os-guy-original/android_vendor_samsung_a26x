# Copyright (C) 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

BOARD_VENDOR := samsung

# VNDK is fully deprecated in Android 15 (Lineage 22).
# Defining BOARD_VNDK_VERSION misroutes VNDK-SP libraries to system/vendor.
# BOARD_VNDK_VERSION := 33
