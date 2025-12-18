
test_softfpu: softfpu.aml test_softfpu.sh
	/usr/bin/env bash test_softfpu.sh

softfpu.aml: softfpu.asl
	iasl softfpu.asl

.PHONY: test_softfpu
