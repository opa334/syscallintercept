include $(THEOS)/makefiles/common.mk

export TARGET = iphone:clang:12.1.2:8.0
export ARCHS = armv7 arm64

APPLICATION_NAME = syscall
syscall_FILES = main.m SCAppDelegate.m SCRootViewController.m
syscall_FRAMEWORKS = UIKit CoreGraphics
syscall_CODESIGN_FLAGS = -Sent.xml

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall \"syscall\"" || true
