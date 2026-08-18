.PHONY: all test test_softfpu clean

all: test

test: test_softfpu

test_softfpu: softfpu.aml test_softfpu.sh
	/usr/bin/env bash test_softfpu.sh

softfpu.aml: softfpu.asl
	iasl softfpu.asl

clean:
	rm -f softfpu.aml
