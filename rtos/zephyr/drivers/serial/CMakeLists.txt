# Copyright (c) 2026 kcore Project
# SPDX-License-Identifier: Apache-2.0

zephyr_library()
zephyr_library_sources_ifdef(CONFIG_UART_KCORE uart_kcore.c)
