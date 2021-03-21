
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
                // Subtraction
                Return (FSUB(Arg0, Arg1))
            }

            Local4 = FRAC(Arg0)
            Local5 = FRAC(Arg1)

            // r_sign: Local3, r_exp: Local6, r_frac: Local7
            if (EXP(Arg0) - EXP(Arg1) == 0) {
                if (EXP(Arg0) == 0) {
                    Return (PACK(Local0, EXP(Arg0), Local4 + Local5))
                }

                if (EXP(Arg0) == 0xFF) {
                    if ((Local4 | Local5) != 0) {
                        // Propagate NaN
                        Return (PNAN(Arg0, Arg1))
                    } else {
                        Return (PACK(Local0, EXP(Arg0), Local4 + Local5))
                    }
                }
                Local3 = Local0
                Local6 = EXP(Arg0)
                Local7 = 0x01000000 + Local4 + Local5

                if ((Local7 & 0x01) == 0 && Local6 < 0xFE) {
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

            Local6 = (Local2 & 0x7F)  // Rounding bits

            if (Local1 >= 0xFD) {
                // TODO: implement 0xFD
                if (Local1 < 0) {

                }
            }

            Local2 = (Local2 + Local7) >> 7

            if ((Local6 ^ 0x40) == 0) {
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
            Return (((Arg0 << 31) | (Arg1 << 23)) + Arg2)
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

            Local0 = (Arg0 | 0x00400000)
            Local1 = (Arg1 | 0x00400000)

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

        Method (NRPK, 3) {  // Norm round and pack
            // Local0: sign
            Local0 = Arg0
            // Local1: exp
            Local1 = Arg1
            // Local2: frac
            Local2 = Arg2

            // Local7: Leading zero
            Local7 = CL0(Arg2) - 1

            Local1 -= Local7

            if (Local1 < 0xFD && Local7 >= 7) {
                if (Local2 == 0) {
                    Local1 = 0
                }
                Return (PACK(Local0, Local1, Local2 << Local7))
            }

            Return (ROPK(Local0, Local1, Local2 << Local7))
        }

        Name (LUT0, Buffer() {
            8, 7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4,
            3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        })

        Method (CL0, 1) {
            Local0 = Arg0
            Local7 = 0

            if (Local0 < 0x10000) {
                Local7 = 16
                Local0 <<= 16
            }
            if (Local0 < 0x1000000) {
                Local7 += 8
                Local0 <<= 8
            }

            Return (Local7 + Derefof(LUT0[((Local0 >> 24) & 0xFF)]))
        }

        Method (FSUB, 2) {
            // Extract reach parts
            Local0 = SIGN(Arg0)
            Local1 = SIGN(Arg1)

            Local2 = FRAC(Arg0)
            Local3 = FRAC(Arg1)

            Local5 = Local0  // sign
            Local6 = 0  // exp
            Local7 = 0  // frac

            Local2 <<= 7
            Local3 <<= 7

            if (EXP(Arg0) == EXP(Arg1)) {
                if (EXP(Arg0) == 0xFF) {
                    if ((Local0 | Local1) != 0) {
                        Return (PNAN(Arg0, Arg1))
                    } else {
                        // NaN
                        Return (PACK(0, 0xFF, 0))
                    }
                }

                Local4 = ((EXP(Arg0) << 8) | EXP(Arg1))
                if (EXP(Arg0) == 0) {
                    Local4 = 0x0101 // Contains a_exp and b_exp
                }

                if (Local2 > Local3) {
                    // A Frac is greater
                    Local6 = (Local4 >> 8)  // a_exp
                    Local7 = Local2 - Local3
                } else {
                    if (Local2 == Local3) {
                        Return (PACK(0, 0, 0))
                    } else {
                        Local5 ^= 1
                        Local6 = (Local4 & 0xFF)    // b_exp
                        Local7 = Local3 - Local2
                    }
                }
                Return (NRPK(Local5, Local6 - 1, Local7))
            } else {
                if (EXP(Arg0) > EXP(Arg1)) {
                    if (EXP(Arg0) == 0xFF) {
                        if (Local2 != 0) {
                            Return (PNAN(Arg0, Arg1))
                        } else {
                            Local5 = Local0
                            Local6 = EXP(Arg0)
                            Local7 = Local2
                        }
                        Return (PACK(Local5, Local6, Local7))
                    }

                    if (EXP(Arg1) != 0) {
                        Local3 += 0x40000000
                    } else {
                        Local3 += Local3
                    }

                    Local3 = SHRT(Local3, EXP(Arg0) - EXP(Arg1))
                    Local2 |= 0x40000000

                    Local6 = EXP(Arg0)
                    Local7 = Local2 - Local3
                } else {
                    if (EXP(Arg1) == 0xFF) {
                        if (Local3 != 0) {
                            Return (PNAN(Arg0, Arg1))
                        } else {
                            Return (PACK(Local5 ^ 1, 0xFF, 0))
                        }
                    }

                    if (EXP(Arg0) != 0) {
                        Local2 += 0x40000000
                    } else {
                        Local2 += Local2
                    }

                    Local2 = SHRT(Local2, EXP(Arg1) - EXP(Arg0))
                    Local3 |= 0x40000000

                    Local5 ^= 1
                    Local6 = EXP(Arg1)
                    Local7 = Local3 - Local2
                }
            }
            Return (NRPK(Local5, Local6 - 1, Local7))
        }

        Method (FEQL, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Return (Arg0 == Arg1 || ((Arg0 | Arg1) << 1) == 0)
        }

        Method (FNEQ, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Return (! FEQL(Arg0, Arg1))
        }

        Method (FGEQ, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Return (! FLET(Arg0, Arg1))
        }

        Method (FLEQ, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Local0 = SIGN(Arg0)
            Local1 = SIGN(Arg1)

            if (Local0 != Local1) {
                if (((Arg0 | Arg1) << 1) == 0 || Local0 == 1) {
                    Return (!0)
                }
            } else {
                // Same sign
                if (Arg0 == Arg1) {
                    Return (!0)
                }

                if (Local0 != 0) {
                    return (Arg0 > Arg1)
                } else {
                    return (Arg0 < Arg1)
                }
            }

            Return (0)
        }

        Method (FGRT, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Return (! FLEQ(Arg0, Arg1))
        }

        Method (FLET, 2) {
            if (ISNA(Arg0) || ISNA(Arg1)) {
                Return (0)
            }

            Local0 = SIGN(Arg0)
            Local1 = SIGN(Arg1)

            if (Local0 != Local1) {
                if (((Arg0 | Arg1) << 1) != 0) {
                    Return (Local0 == 1)
                }
            } else {
                // Same sign
                if (Arg0 != Arg1) {
                    if (Local0 != 0) {
                        return (Arg0 > Arg1)
                    } else {
                        return (Arg0 < Arg1)
                    }
                }
            }

            Return (0)
        }

        Method (NSUE, 1) {
            // norm_subnormal_frac exp
            Return (9 - CL0(Arg0))
        }

        Method (NSUF, 1) {
            // norm_subnormal_frac frac
            Local0 = CL0(Arg0) - 8

            Return (Arg0 << Local0)
        }

        Method (SSRT, 2) {
            // short_shift_right_jam64
            Local0 = Arg0
            Local1 = ((Arg0 >> Arg1) & 0xFFFFFFFF)

            if ((Local0 & ((0x01 << Arg1) - 1)) != 0) {
                Return (Local1 | 1)
            }
            Return (Local1)
        }

        Name (DK0S, Package() {
            0xFFC4, 0xF0BE, 0xE363, 0xD76F, 0xCCAD, 0xC2F0, 0xBA16, 0xB201,
            0xAA97, 0xA3C6, 0x9D7A, 0x97A6, 0x923C, 0x8D32, 0x887E, 0x8417
        })
        Name (DK1S, Package() {
            0xF0F1, 0xD62C, 0xBFA1, 0xAC77, 0x9C0A, 0x8DDB, 0x8185, 0x76BA,
            0x6D3B, 0x64D4, 0x5D5C, 0x56B1, 0x50B6, 0x4B55, 0x4679, 0x4211
        })
        Method (ARCP, 1) {
            // approx_recip
            Local0 = ((Arg0 >> 27) & 0x0F)    // index
            Local1 = (Arg0 >> 11)           // eps
            Local2 = derefof(DK0S[Local0]) - ((derefof(DK1S[Local0]) * Local1) >> 20)
            Local3 = (Local2 * Arg0) >> 7   // Delta
            Local4 = (Local2 << 16) + ((Local2 * Local3) >> 24)
            Local5 = (Local3 * Local3) >> 32
            Local6 = (Local4 + (Local4 * Local5) >> 48)

            Return (Local6)
        }

        Name (SK0S, Package() {
            0xB4C9, 0xFFAB, 0xAA7D, 0xF11C, 0xA1C5, 0xE4C7, 0x9A43, 0xDA29,
            0x93B5, 0xD0E5, 0x8DED, 0xC8B7, 0x88C6, 0xC16D, 0x8424, 0xBAE1
        })
        Name (SK1S, Package() {
            0xA5A5, 0xEA42, 0x8C21, 0xC62D, 0x788F, 0xAA7F, 0x6928, 0x94B6,
            0x5CC7, 0x8335, 0x52A6, 0x74E2, 0x4A3E, 0x68FE, 0x432B, 0x5EFD
        })
        Method (ARSR, 2) {
            // approx_recip_sqrt
            Local0 = ((Arg1 >> 27) & 0x0E) + Arg0  // index
            Local1 = ((Arg1 >> 12) & 0x0000FFFF)   // eps
            Local2 = derefof(SK0S[Local0]) - (((derefof(SK1S[Local0]) * Local1) >> 20) & 0xFFFF)
            Local3 = Local2 * Local2        // e_sqr_r0

            if (Arg0 == 0) {
                Local3 <<= 1
            }

            Local4 = (~((Local3 * Arg1) >> 23) & 0xFFFFFFFF)   // Delta
            Local5 = (Local2 << 16) + ((Local2 * Local4) >> 25)
            Local6 = (((Local4 * Local4) >> 32) & 0xFFFFFFFF)
            Local7 = (Local5 >> 1) + (Local5 >> 3) - (Local2 << 14)
            Local7 = Local7 * Local6
            Local5 += ((Local7 >> 48) & 0xFFFFFFFF)

            if ((Local5 & 0x80000000) == 0) {
                Local5 = 0x80000000
            }

            Return (Local5)
        }

        Method (FMUL, 2) {
            // Local5: r_sign, Local6: r_exp, Local7: r_frac
            Local5 = (SIGN(Arg0) ^ SIGN(Arg1))

            // Local0: a_exp
            Local0 = EXP(Arg0)
            // Local1: b_exp
            Local1 = EXP(Arg1)

            // Local2: a_frac
            Local2 = FRAC(Arg0)
            // Local3: b_frac
            Local3 = FRAC(Arg1)

            if (Local0 == 0xFF) {
                if (Local2 != 0 || (Local1 == 0xFF && Local3 != 0)) {
                    // NaN
                    Return (PNAN(Arg0, Arg1))
                }

                // Inf
                if ((EXP(Arg1) | Local3) == 0) {
                    // Default NaN
                    Return (PACK(Local5, 0xFF, 0))
                }

                Return (PACK(Local5, 0xFF, 0))
            }
            if (Local1 == 0xFF) {
                if (Local3 != 0) {
                    // NaN
                    Return (PNAN(Arg0, Arg1))
                }

                // Inf
                if ((EXP(Arg0) | Local2) == 0) {
                    // Default NaN
                    Return (PACK(Local5, 0xFF, 0))
                }

                Return (PACK(Local5, 0xFF, 0))
            }

            if (Local0 == 0) {
                if (SIGN(Arg0) == 0) {
                    Return (PACK(Local5, 0, 0))
                }

                Local0 = NSUE(Local2)
                Local2 = NSUF(Local2)
            }

            if (Local1 == 0) {
                if (SIGN(Arg1) == 0) {
                    Return (PACK(Local5, 0, 0))
                }

                Local1 = NSUE(Local3)
                Local3 = NSUF(Local3)
            }

            Local6 = Local0 + Local1 - 0x7F

            Local2 = (Local2 | 0x00800000) << 7
            Local3 = (Local3 | 0x00800000) << 8

            // FIXME: might overflow on 32 bit system
            Local4 = Local2 * Local3

            Local7 = SSRT(Local4, 32)

            if (Local7 < 0x40000000) {
                Local6 -= 1
                Local7 <<= 1
            }

            Return (ROPK(Local5, Local6, Local7))
        }

        Method (FDIV, 2) {
            // Local5: r_sign, Local6: r_exp, Local7: r_frac
            Local5 = (SIGN(Arg0) ^ SIGN(Arg1))

            // Local0: a_exp
            Local0 = EXP(Arg0)
            // Local1: b_exp
            Local1 = EXP(Arg1)

            // Local2: a_frac
            Local2 = FRAC(Arg0)
            // Local3: b_frac
            Local3 = FRAC(Arg1)

            if (Local0 == 0xFF) {
                if (Local2 != 0) {
                    Return (PNAN(Arg0, Arg1))
                }
                if (Local1 == 0xFF) {
                    if (Local3 != 0) {
                        Return (PNAN(Arg0, Arg1))
                    } else {
                        Return (PACK(Local5, 0xFF, 0))
                    }
                }
                Return (PACK(Local5, 0xFF, 0))
            }
            if (Local1 == 0xFF) {
                if (Local3 != 0) {
                    Return (PNAN(Arg0, Arg1))
                }
                Return (PACK(Local5, 0, 0))
            }

            if (Local1 == 0) {
                if (Local3 == 0) {
                    if ((Local0 | Local2) == 0) {
                        Return (PACK(Local5, 0xFF, 0))
                    }
                    Return (PACK(Local5, 0xFF, 0))
                }

                Local1 = NSUE(Local3)
                Local3 = NSUF(Local3)
            }

            if (Local0 == 0) {
                if (Local2 == 0) {
                    // 0
                    Return (PACK(Local5, 0, 0))
                }

                Local0 = NSUE(Local2)
                Local2 = NSUF(Local2)
            }

            Local6 = Local0 - Local1 + 0x7E
            Local2 |= 0x00800000
            Local3 |= 0x00800000

            if (Local2 < Local3) {
                Local6 -= 1
                Local2 <<= 31
            } else {
                Local2 <<= 30
            }
            // FIXME: might be buggy on 32 bit system
            Local7 = Local2 / Local3

            if ((Local7 & 0x3F) == 0) {
                if (Local7 * Local3 != Local2) {
                    Local7 |= 0x01
                }
            }

            Local7 &= 0xFFFFFFFF

            Return (ROPK(Local5, Local6, Local7))
        }

        Method (SQRT, 1) {
            Local0 = SIGN(Arg0)
            Local1 = EXP(Arg0)
            Local2 = FRAC(Arg0)

            // r: Local5 Local6 Local7

            if (Local1 == 0xFF) {
                if (Local2 != 0) {
                    Return (PNAN(Arg0, 0))
                }
                if (Local0 == 0) {
                    Return (Arg0)
                }

                // Invalid
                Return (PACK(1, 0xFF, 0))
            }

            if (Local0 != 0) {
                if ((Local1 | Local2) == 0) {
                    Return (Arg0)
                }
                // Invalid
                Return (PACK(1, 0xFF, 0))
            }

            if (Local1 == 0) {
                if (Local2 == 0) {
                    Return (Arg0)
                }

                Local1 = NSUE(Local2)
                Local2 = NSUF(Local2)
            }

            Local6 = ((Local1 - 0x7f) >> 1) + 0x7E
            Local1 &= 1

            Local2 = (Local2 | 0x00800000) << 8
            Local3 = ARSR(Local1, Local2)

            Local7 = Local2 * Local3
            Local7 = Local7 >> 32

            if (Local1 != 0) {
                Local7 >>= 1
            }
            Local7 += 2

            if ((Local7 & 0x3F) < 2) {
                Local4 = Local7 >> 2
                Local4 = Local4 * Local4

                Local7 &= (~0x03)

                if ((Local4 & 0x80000000) != 0) {
                    Local7 |= 0x01
                } else {
                    if (Local4 != 0) {
                        Local7 -= 1
                    }
                }
            }

            Return (ROPK(0, Local6, Local7))
        }

        Method (RINT, 1) {
            // Round to int
            Local0 = SIGN(Arg0)
            Local1 = EXP(Arg0)
            Local2 = FRAC(Arg0)

            if (Local1 < 0x7E) {
                if ((Arg0 << 1) == 0) {
                    Return (Arg0)
                }

                Local7 = Arg0 & PACK(1, 0, 0)
                if (Local2 != 0) {
                    if (Local1 == 0x7E) {
                        Local7 |= PACK(0, 0x7F, 0)
                    }
                }
                Return (Local7)
            }

            if (0x96 <= Local1) {
                if (Local1 == 0xFF && Local2 != 0) {
                    Return (PNAN(Arg0, 0))
                }
                Return (Arg0)
            }

            Local5 = (1 << (0x96 - Local1))
            Local6 = Local5 - 1
            Local7 = Arg0

            Local7 += (Local5 >> 1)
            if ((Local7 & Local6) == 0) {
                Local7 &= (~Local5)
            }
            Local7 &= (~Local6)
            Return (Local7)
        }

        Method (F2IN, 1) {
            Local0 = RINT(Arg0)

            Local7 = 0

            if (ISNA(Local0)) {
                Return (0x7FFFFFFF)
            } else {
                if (ISIN(Local0)) {
                    if (SIGN(Local0) != 0) {
                        Return (0xFFFFFFFF)
                    }
                    Return (0x7FFFFFFF)
                } else {
                    if (Local0 == 0 || Local0 == 0x80000000) {
                        Return (0)
                    }

                    Local1 = SIGN(Local0)
                    Local2 = EXP(Local0)
                    Local3 = FRAC(Local0)

                    Local3 |= 0x800000

                    if (Local2 < 0x7F) {
                        // Too tiny, must be 0
                        Return (0)
                    }

                    Local4 = Local2 - 0x7F
                    if (Local1 == 0) {
                        Return (Local3 >> (23 - Local4))
                    } else {
                        Return (0x80000000 | 
                            ((Local3 >> (23 - Local4)) - 1))
                    }
                }
            }
        }

        Method (IN2F, 1) {
            if (Arg0 == 0) {
                Return (0)
            }

            Local2 = 0
            if ((Arg0 & 0x80000000) == 0) {
                // Positive
                Local2 = Arg0
            } else {
                // Negative
                Local2 = ((~Arg0) & 0xFFFFFFFF) + 1
            }
            Local7 = CL0(Local2)
            Local6 = 32 - Local7 - 1
            Local1 = 0x7F + Local6
            Local0 = ((Arg0 & 0x80000000) >> 31)
            Return (PACK(Local0, Local1, (Local2 << (24 - Local6 - 1)) & 0x7FFFFF))
        }
    }
}

