
test_softfpu: softfpu.aml test_softfpu.sh
	/bin/sh test_softfpu.sh

softfpu.aml: softfpu.asl
	iasl softfpu.asl
