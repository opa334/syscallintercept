include $(THEOS)/makefiles/common.mk

export TARGET = iphone:clang:12.1.2:8.0
export ARCHS = arm64 armv7

TWEAK_NAME = syscallintercept
syscallintercept_CFLAGS = -fobjc-arc
syscallintercept_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk
