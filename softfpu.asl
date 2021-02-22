
DefinitionBlock ("", "SSDT", 2, "INOKI", "RAYTRACE", 0x00000001)
{
    Device (SFPU) {         // SOFTFPU
        // Float classes
        Name (NORM, 0x00)
        Name (UNCL, 0x01)   // UNCLASSIFIED
        Name (CLS0, 0x02)   // ZERO
        Name (CLSI, 0x03)   // INFINITY
        Name (QNAN, 0x04)   // QNAN
        Name (SNAN, 0x05)   // SNAN

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

        // Check is infinity
        Method (ISIN, 1) {
            Return ((INFI(Arg0)))
        }

        // Check is NaN
        Method (ISNA, 1) {
            Return ((Arg0 & ~(1 << 31)) > 0x7f800000)
        }

        // Check is zero
        Method (ISZE, 1) {
            Return ((Arg0 & 0x7fffffff) == 0)
        }

        // Check is normal
        Method (ISNO, 1) {
            Return ((((Arg0 >> 23) + 1) & 0xff) >= 2)
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

        Method (FADD, 2) {   // Add 2 floats
            // Extract reach parts
            Local0 = SIGN(Arg0)
            Local1 = SIGN(Arg1)

            Local2 = EXP(Arg0)
            Local3 = EXP(Arg1)

            Local4 = FRAC(Arg0)
            Local5 = FRAC(Arg1)

            // Local6 = CLS(Arg0)
            // Local7 = CLS(Arg1)
            
            // Both two are in the normal class
            if (Local2 > Local3) {  // Arg0.exp > Arg1.exp
                Local1 = SHFT(Local1, Local2 - Local3)
            } else {
                if (Local2 < Local3) {   // Arg0.exp < Arg1.exp
                    Local0 = SHFT(Local0, Local3 - Local2)
                    Local2 = Local3
                }
            }
            Local0 += Local1    // Arg0.frac += Arg1.frac
            // if (Local0 ) // TODO: check overflow
            Return GENF(Local0, Local2, Local4)


        }

        Method (SHFT, 2) {
            Local0 = 0
            Local1 = 0
            Local2 = 0

            if (Arg1 == 0) {
                Local0 = Arg0
            }
            else {
                if (Arg1 < 64) {
                    Local2 = (Zero - Arg1) & 63
                    Local1 = ((Arg0<< Local2) != 0)
                    if (Local1) {
                        Local0 = (Arg0>>Arg1) | One
                    } else {
                        Local0 = (Arg0>>Arg1) | Zero
                    }
                }
                else {
                    Local1 = (Arg0 != 0)

                    if (Local1) {
                        Local0 = 1
                    } else {
                        Local0 = 0
                    }
                }
            }
            Return (Local0)
        }
    }
}

