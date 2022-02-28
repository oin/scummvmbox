include base.mk

SRC += AppDelegate.m GameID.m GameIDRepository.m Download.m ext/KSFileUtilities/KSPathUtilities.m

CCFLAGS := $(CCFLAGS) -fmessage-length=0 -Wall -Wextra -Wno-unused-variable -Wno-unused-parameter -Wno-missing-declarations -Wno-unknown-pragmas -I. -mmacosx-version-min=10.9 -Wno-deprecated-declarations -DLOG_FILE_HANDLE=stderr  -ffast-math -Wno-nullability-completeness
CFLAGS := $(CFLAGS) -std=c11 -Wno-missing-prototypes
CXXFLAGS := $(CXXFLAGS) -std=c++14
LDFLAGS := $(LDFLAGS) -mmacosx-version-min=10.9 -framework Cocoa
ifdef MACOS_ARM
CCFLAGS += -arch x86_64 -arch arm64
LDFLAGS += -arch x86_64 -arch arm64
endif
ifdef DEBUG
CCFLAGS += -g -DDEBUG=1 -UNDEBUG $(if $(NO_LOGD),-DNLOGD,) -O0
else
CCFLAGS += -UDEBUG -DNDEBUG=1 -O2
endif

OBJCFLAGS := -fobjc-arc
OBJCCFLAGS := 
$(OBJDIR)/%.m.o: $$(call ToSources,%).m $(OBJDIR)/%.d | $(OBJDIR)
	$(CC) -x objective-c $(CDependencyFlags) $(ARCHFLAGS) $(CCFLAGS) $(OBJCFLAGS) $(CFLAGS) -c "$<" -o "$@"
	$(CDependencyPostCompile)
$(OBJDIR)/%.mm.o: $$(call ToSources,%).mm $(OBJDIR)/%.d | $(OBJDIR)
	$(CXX) -x objective-c++ $(CDependencyFlags) $(ARCHFLAGS) $(CCFLAGS) $(CXXFLAGS) $(OBJCFLAGS) $(OBJCCFLAGS) -c "$<" -o "$@"
	$(CDependencyPostCompile)
$(OBJDIR)/%.nib: | $(OBJDIR)
	ibtool --compile "$@" "$<"

PLIST := Info.plist
RESOURCES := Icon.icns BundleIcon.icns $(OBJDIR)/MainMenu.nib GameID.plist
$(OBJDIR)/MainMenu.nib: MainMenu.xib

EXENAME := ScummVMBox
EXE := $(OBJDIR)/$(EXENAME)
APP := $(BUILDDIR)/ScummVMBox.app

$(EXE): $(call ObjectsForSources,$(SRC))
	$(LINK.cc) $+ -o "$@"

$(APP): $(EXE) $(PLIST) $(RESOURCES) | $(BUILDDIR)
# 	rm -rf "$@"
	mkdir -p "$@" "$@/Contents/MacOS" "$@/Contents/Resources"
	cp -R $(RESOURCES) "$@/Contents/Resources"
	cat $(PLIST) | perl -0777 -pe "s&__VERSION__&$(VERSION)&g;" -pe "s&__VERSION_SHORT__&$(VERSION_SHORT)&g;" >"$@/Contents/Info.plist"
	cp $(EXE) "$@/Contents/MacOS"
	touch "$@"
	xattr -cr "$@"
	$(call Codesign,$@)

.PHONY: app .FORCE
app: $(APP)
run: $(APP)
	until open $(APP); do sleep 0.25; done
debug: $(APP)
	$(call ExternalLaunch,debug,lldb -o run $(APP)/Contents/MacOS/$(EXENAME))
all: app
.DEFAULT_GOAL := app

.FORCE:
