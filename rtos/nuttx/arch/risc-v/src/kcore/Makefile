############################################################################
# arch/risc-v/src/kcore/Makefile
#
# Copyright (c) 2026 kcore Project
# SPDX-License-Identifier: Apache-2.0
#
############################################################################

# No chip-specific files needed - using common RISC-V implementation
include $(TOPDIR)/Make.defs

CHIP_CSRCS = 

INCLUDES += ${INCDIR_PREFIX}$(ARCH_SRCDIR)$(DELIM)chip
INCLUDES += ${INCDIR_PREFIX}$(ARCH_SRCDIR)$(DELIM)common
INCLUDES += ${INCDIR_PREFIX}$(TOPDIR)$(DELIM)sched

CPPFLAGS += $(INCLUDES)
CFLAGS += $(INCLUDES)
CXXFLAGS += $(INCLUDES)
AFLAGS += $(INCLUDES)
