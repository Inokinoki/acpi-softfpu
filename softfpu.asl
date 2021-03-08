
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

            if (Local0 != Local1) {
                // TODO: subtraction
                // Return (FSUB(Arg0, Arg1))
            }

            Local4 = FRAC(Arg0)
            Local5 = FRAC(Arg1)

            // r_sign: Local3, r_exp: Local6, r_frac: Local7
            if (EXP(Arg0) - EXP(Arg1) == 0) {
                if (EXP(Arg0) == 0) {
                    Return (PACK(Local0, EXP(Arg0), Local4 + Local5))
                }

                if (EXP(Arg0) == 0xFF) {
                    if (Local4 | Local5 != 0) {
                        // Propagate NaN
                        Return (PNAN(Arg0, Arg1))
                    } else {
                        Return (PACK(Local0, EXP(Arg0), Local4 + Local5))
                    }
                }
                Local3 = Local0
                Local6 = EXP(Arg0)
                Local7 = 0x01000000 + Local4 + Local5

                if (Local7 & 0x01 == 0 && Local6 < 0xFE) {
                    Return (PACK(Local3, Local6, Local7 >> 1))
                }

                Local7 <<= 6
            } else {
                Local3 = Local0

                Local4 <<= 6;
                Local5 <<= 6;

                if (EXP(Arg0) < EXP(Arg1)) {
                    // a_exp < b_exp
                    if (EXP(Arg1) == 0xFF) {
                        if (Local1 != 0) {
                            // Propagate NaN
                            Return (PNAN(Arg0, Arg1))
                        } else {
                            Return (PACK(Local3, 0xFF, 0))
                        }
                    }

                    Local6 = EXP(Arg1)

                    if (EXP(Arg0) != 0) {
                        // a_frac += 0x20000000;
                        Local4 += 0x20000000
                    } else {
                        Local4 += Local4
                    }

                    Local4 = SHRT(Local4, EXP(Arg1) - EXP(Arg0))
                } else {
                    // a_exp > b_exp
                    if (EXP(Arg0) == 0xFF) {
                        if (Local0 != 0) {
                            // Propagate NaN
                            Return (PNAN(Arg0, Arg1))
                        } else {
                            Return (PACK(Local0, 0xFF, Local4))
                        }
                    }

                    Local6 = EXP(Arg0)

                    if (EXP(Arg1) != 0) {
                        Local5 += 0x20000000
                    } else {
                        Local5 += Local5
                    }
                    Local5 = SHRT(Local5, EXP(Arg0) - EXP(Arg1))
                }

                Local7 = 0x20000000 + Local4 + Local5

                if (Local7 < 0x40000000) {
                    Local6 -= 1
                    Local7 <<= 1
                }
            }

            // Round and pack
            Return (ROPK(Local3, Local6, Local7))
        }

        Method (ROPK, 3) {
            // round and pack
            // round_increment = 0x40
            Local7 = 0x40

            Local0 = Arg0   // sign
            Local1 = Arg1   // exp
            Local2 = Arg2   // frac

            // Near Even, do nothing

            Local6 = Local2 & 0x7F  // Rounding bits

            if (Local1 >= 0xFD) {
                // TODO: implement 0xFD
                if (Local1 < 0) {

                }
            }

            Local2 = (Local2 + Local7) >> 7

            if (Local6 ^ 0x40 == 0) {
                Local2 &= 0x7FFFFFFE
            } else {
                Local2 &= 0x7FFFFFFF
            }

            if (Local2 == 0) {
                Local1 = 0
            }

            Return (PACK(Local0, Local1, Local2))
        }

        Method (PACK, 3) {
            Return (Arg0 << 31 | (Arg1 << 23) + Arg2)
        }

        Method (SHRT, 2) {
            // Arg0: a
            // Arg1: dist
            if (Arg1 < 31) {
                if ((Arg0 << ((0 - Arg1) & 31) & 0xFFFFFFFF) != 0) {
                    Return ((Arg0 >> Arg1) | 1)
                }
                Return ((Arg0 >> Arg1) | 0)
            } else {
                if (Arg0 != 0) {
                    Return (0x01)
                }
                Return (0x00)
            }
        }

        Method (PNAN, 2) {
            // Arg0: a
            // Arg1: b

            Local0 = Arg0 | 0x00400000
            Local1 = Arg1 | 0x00400000

            Local3 = FRNA(Arg0) // a frac NaN
            Local4 = FRNA(Arg1) // b frac NaN

            if (Local3 | Local4) {
                if (Local3) {
                    if (!Local4) {
                        if (ISNA(Arg1)) {
                            Return (Arg1)
                        } else {
                            Return (Arg0)
                        }
                    }
                } else {
                    if (ISNA(Arg0)) {
                        Return (Arg0)
                    } else {
                        Return (Arg1)
                    }
                }
            }

            // Fractions
            Local5 = FRAC(Arg0)
            Local6 = FRAC(Arg1)

            if (Local5 < Local6) {
                Return (Arg1)
            } else {
                if (Local5 > Local6) {
                    Return (Arg0)
                } else {
                    if (Arg0 < Arg1) {
                        Return (Arg0)
                    } else {
                        Return (Arg1)
                    }
                }
            }
        }

        Method (FRNA, 1) {
            // Arg0: a

            Local0 = ((Arg0 & 0x7FC00000) == 0x7F800000)
            Local1 = ((Arg0 & 0x003FFFFF) != 0)

            Return (Local0 && Local1)
        }
    }
}

