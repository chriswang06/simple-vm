CONFIG ?= debug
BIN := .build/$(if $(filter release,$(CONFIG)),release,debug)/simple-vm
ENT := SimpleVM.entitlements

.PHONY: build sign run clean

build:
	swift build $(if $(filter release,$(CONFIG)),-c release,)
	codesign --entitlements $(ENT) --force --sign - $(BIN)

sign:
	codesign --entitlements $(ENT) --force --sign - $(BIN)

run: build
	$(BIN) $(ARGS)

clean:
	swift package clean
	rm -rf .build
