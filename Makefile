include common.mk

APP_NAME = "TactixWatchFace"
DEVICE = epix2pro51mm
VERSION = "0.1.0"

all: build

print_env:
	@echo "-------------- ENV --------------"
	@echo "SDK_HOME  = $(SDK_HOME)"
	@echo "JAVA_HOME = $(JAVA_HOME)"
	@echo "DEV_KEY   = $(DEV_KEY)"
	@echo "---------------------------------"

start_simulator:
	@$(SDK_HOME)/bin/connectiq

start_simulator_bg:
	@$(SDK_HOME)/bin/connectiq &
	@sleep 1

clean:
	@rm -rf bin

# TODO
# --debug
# --unit-test
build: print_env
	@$(JAVA_HOME)/bin/java \
	-Xms1g \
	-Dfile.encoding=UTF-8 \
	-Dapple.awt.UIElement=true \
	-jar "$(SDK_HOME)/bin/monkeybrains.jar" \
	--output bin/$(APP_NAME).prg \
	--jungles monkey.jungle \
	--private-key $(DEV_KEY) \
	--device $(DEVICE) \
	--typecheck 2 \
	--warn

release: print_env
	@$(JAVA_HOME)/bin/java \
	-Xms1g \
	-Dfile.encoding=UTF-8 \
	-Dapple.awt.UIElement=true \
	-jar "$(SDK_HOME)/bin/monkeybrains.jar" \
	--output bin/$(APP_NAME)-v$(VERSION).prg \
	--jungles monkey.jungle \
	--private-key $(DEV_KEY) \
	--device $(DEVICE) \
	--typecheck 2 \
	--release \
	--warn
	@echo "bin/$(APP_NAME)-v$(VERSION).prg"

package: print_env
	@$(JAVA_HOME)/bin/java \
	-Xms1g \
	-Dfile.encoding=UTF-8 \
	-Dapple.awt.UIElement=true \
	-jar "$(SDK_HOME)/bin/monkeybrains.jar" \
	--output bin/$(APP_NAME)-v$(VERSION).iq \
	--jungles monkey.jungle \
	--private-key $(DEV_KEY) \
	--device $(DEVICE) \
	--typecheck 2 \
	--warn \
	--release \
	--package-app
	@echo "bin/$(APP_NAME)-v$(VERSION).iq"

sim: build start_simulator_bg
	$(SDK_HOME)/bin/monkeydo bin/$(APP_NAME).prg $(DEVICE)
