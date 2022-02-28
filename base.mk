.SECONDEXPANSION:
.SUFFIXES:
.SHELL := bash

# debug goal
ifneq ($(words $(filter debug,$(MAKECMDGOALS))),0)
DEBUG := 1
endif

# Path utilities
DirectoryOfThisFile = $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

# Source/object path translation
ChangeExtension = $(addsuffix $(if $2,.$2,),$(basename $1))
ToSources = $(subst ~,/,$(patsubst @%,..%,$(patsubst onedot%,.%,$1)))
ToObjects = $(patsubst .%,onedot%,$(patsubst ..%,@%,$(subst /,~,$1)))
ObjectsForSources = $(addprefix $(OBJDIR)/,$(call ToObjects,$(addsuffix .o,$1)))

# Build/object directory
DISTDIR ?= build
BUILDDIR := $(DISTDIR)$(if $(VARIANT),/$(VARIANT),)
ifdef DEBUG
BUILDDIR := $(BUILDDIR)/debug
endif
OBJDIR := $(BUILDDIR)/obj

# Flags
ASFLAGS := 
ARCHFLAGS := 
CCFLAGS := 
CFLAGS := 
CXXFLAGS := 
LDFLAGS := 

# Launch things in external windows (Mac only)
ifdef W
EXTERNAL_LAUNCH_WINDOW := 1
endif
ifdef EXTERNAL_LAUNCH_WINDOW
ExternalLaunch = echo cd '$(abspath .)' >"$(OBJDIR)/launch-$1.command"; echo '$2' >>"$(OBJDIR)/launch-$1.command"; chmod +x "$(OBJDIR)/launch-$1.command"; open "$(OBJDIR)/launch-$1.command"
else
ExternalLaunch = $2
endif

# C/C++ dependency management
CDependencyFlags = -MT $@ -MMD -MP -MF "$(OBJDIR)/$*.Td"
CDependencyPostCompile = mv -f "$(OBJDIR)/$*.Td" "$(OBJDIR)/$*.d"
$(OBJDIR)/%.d: ;
.PRECIOUS: $(OBJDIR)/%.d
-include $(wildcard $(OBJDIR)/*.d)

# Compilation rules
LINK.cc = $(CXX) $(ARCHFLAGS) $(CCFLAGS) $(CXXFLAGS) $(LDFLAGS)
%.o:
%.a:
$(OBJDIR)/%.s.o: $$(call ToSources,%).s | $(OBJDIR)
	$(CC) -x assembler-with-cpp $(ARCHFLAGS) $(ASFLAGS) -c "$<" -o "$@" 
$(OBJDIR)/%.c.o: $$(call ToSources,%).c $(OBJDIR)/%.d | $(OBJDIR)
	$(CC) $(CDependencyFlags) $(ARCHFLAGS) $(CCFLAGS) $(CFLAGS) -c "$<" -o "$@"
	$(CDependencyPostCompile)
$(OBJDIR)/%.cpp.o: $$(call ToSources,%).cpp $(OBJDIR)/%.d | $(OBJDIR)
	$(CXX) $(CDependencyFlags) $(ARCHFLAGS) $(CCFLAGS) $(CXXFLAGS) -c "$<" -o "$@"
	$(CDependencyPostCompile)

# General rules
$(BUILDDIR) $(OBJDIR) $(BUILDBASE):
	-mkdir -p $@
clean:
	-rm -rf $(BUILDDIR)
distclean:
	-rm -rf $(DISTDIR)
.PHONY: all clean distclean run debug
.DEFAULT_GOAL :=

ifndef NOCONFIG
-include Config.mk
endif
ifdef VARIANT
-include Config.$(VARIANT).mk
endif

MACOS_ARCH := $(shell uname -p)
ifeq ($(MACOS_ARCH),arm)
MACOS_ARM := 1
endif
ifeq ($(MACOS_ARCH),i386)
MACOS_x86 := 1
endif

SRC := $(strip $(SRC) )
