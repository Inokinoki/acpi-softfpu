
DefinitionBlock ("", "SSDT", 2, "INOKI", "RAYTRACE", 0x00000001)
{
    Device (SFPU) {         // SOFTFPU
        Method (GENF, 3) {  // Construct float from integer
            /*
            Arg0: sign
            Arg1: exp
            Arg2: number
            */
            Return ((Arg0 << 31) + (Arg1 << 23) + Arg2)
        }

        Method (FABS, 1) {  // Abs
            Return (Arg0 & 0x7fffffff)
        }

        Method (MTH3, 1) {  // Chs
            Return (Arg0 ^ 0x80000000)
        }

        Method (INFI, 1) {  // Infinity
            Return ((Arg0 & 0x7fffffff) == 0x7f800000)
        }

        Method (NEG, 1) {  // Neg
            Return ((Arg0 >> 31) == 1)
        }

        Method (FRAC, 1) {  // Extract frac
            Return (Arg0 & 0x007FFFFF)
        }

        Method (EXP, 1) {  // Extract exp
            Return ((Arg0 >> 23) & 0xFF)
        }

        Method (SIGN, 1) {  // Extract sign
            Return (Arg0 >> 31)
        }
    }
}

