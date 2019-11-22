## aribdecode
##
## Copyright (c) 2019 ink2ash
##
## This software is released under the MIT License.
## http://opensource.org/licenses/mit-license.php

import ./aribcharset


type GSET = enum
  UNDEFINED,                     # 0x0
  KANJI,                         # 0x1
  ALPHANUMERIC,                  # 0x2
  HIRAGANA,                      # 0x3
  KATAKANA,                      # 0x4
  MOSAIC_A,                      # 0x5
  MOSAIC_B,                      # 0x6
  MOSAIC_C,                      # 0x7
  MOSAIC_D,                      # 0x8
  PROPORTIONAL_ALPHANUMERIC,     # 0x9
  PROPORTIONAL_HIRAGANA,         # 0xA
  PROPORTIONAL_KATAKANA,         # 0xB
  JIS_X_0201_KATAKANA,           # 0xC
  JIS_COMPATIBLE_KANJI_PLANE_1,  # 0xD
  JIS_COMPATIBLE_KANJI_PLANE_2,  # 0xE
  ADDITIONAL_SYMBOLS,            # 0xF

type CSIZE = enum
  SSZ,     # Small Size
  MSZ,     # Middle Size
  NSZ,     # Normal Size
  SZX_60,  # Character Size Control Tiny size
  SZX_41,  # Character Size Control Double height
  SZX_44,  # Character Size Control Double width
  SZX_45,  # Character Size Control Double height and width
  SZX_6B,  # Character Size Control Special 1
  SZX_64,  # Character Size Control Special 2

const IS_2BYTE_SIZE : array[9, bool] = [
  false,  # CSIZE.SSZ
  false,  # CSIZE.MSZ
  true,   # CSIZE.NSZ
  false,  # CSIZE.SZX_60
  true,   # CSIZE.SZX_41
  true,   # CSIZE.SZX_44
  true,   # CSIZE.SZX_45
  true,   # CSIZE.SZX_6B
  true,   # CSIZE.SZX_64
]

var
  codeG : array[4, int]
  lockGL : ptr int
  lockGR : ptr int
  singleGL : ptr int
  csize : int


proc deallocVariables*() : void
proc decodeKanji(code1 : byte, code2 : byte) : string
proc decodeAlphanumeric(code : byte) : string
proc decodeHiragana(code : byte) : string
proc decodeKatakana(code : byte) : string
proc decodeJISX0201Katakana(code : byte) : string
proc decodeCharacter(gset : int, code : byte, enableAdditionalSymbols : bool,
                     charCodeBuf : var seq[byte]) : string
proc designateGSET(codeGIdx : int, fcode : byte) : bool {.discardable.}
proc designateDRCS(codeGIdx : int, fcode : byte) : bool {.discardable.}
proc decodeEsc(escCode : byte, escCodeBuf : var seq[byte]) : bool
proc aribdecode*(aribCodes : seq[byte],
                 enableAdditionalSymbols : bool) : string


# --------------- Util --------------------------------------------------------
proc deallocVariables() : void =
  ## Dealloc ptr variables.
  dealloc(lockGL)
  dealloc(lockGR)
  dealloc(singleGL)


# --------------- ARIB Decoder ------------------------------------------------
proc decodeKanji(code1 : byte, code2 : byte) : string =
  ## Decode 2-byte character into kanji.
  ##
  ## **Parameters:**
  ## - ``code1`` : ``byte``
  ##     The first byte of 2-byte character.
  ## - ``code2`` : ``byte``
  ##     The second byte of 2-byte character.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded kanji string.
  let
    row : int = int(code1 and byte(0x7F)) - 0x21
    cell : int = int(code2 and byte(0x7F)) - 0x21
  result = aribcharset.KANJI_TABLE[row * 94 + cell]


proc decodeAlphanumeric(code : byte) : string =
  ## Decode 1-byte character into alphanumeric.
  ##
  ## **Parameters:**
  ## - ``code`` : ``byte``
  ##     The byte of 1-byte character.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded alphanumeric string.
  let cell : int = int(code and byte(0x7F)) - 0x21
  result = aribcharset.ALPHANUMERIC_TABLE[cell]


proc decodeHiragana(code : byte) : string =
  ## Decode 1-byte character into hiragana.
  ##
  ## **Parameters:**
  ## - ``code`` : ``byte``
  ##     The byte of 1-byte character.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded hiragana string.
  let cell : int = int(code and byte(0x7F)) - 0x21
  result = aribcharset.HIRAGANA_TABLE[cell]


proc decodeKatakana(code : byte) : string =
  ## Decode 1-byte character into katakana.
  ##
  ## **Parameters:**
  ## - ``code`` : ``byte``
  ##     The byte of 1-byte character.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded katakana string.
  let cell : int = int(code and byte(0x7F)) - 0x21
  result = aribcharset.KATAKANA_TABLE[cell]


proc decodeJISX0201Katakana(code : byte) : string =
  ## Decode 1-byte character into JIS X 0201 katakana.
  ##
  ## **Parameters:**
  ## - ``code`` : ``byte``
  ##     The byte of 1-byte character.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded JIS X 0201 katakana string.
  let cell : int = int(code and byte(0x7F)) - 0x21
  result = aribcharset.JIS_X_0201_KATAKANA_TABLE[cell]


proc decodeCharacter(gset : int, code : byte, enableAdditionalSymbols : bool,
                     charCodeBuf : var seq[byte]) : string =
  ## Decode 1-byte or 2-byte character.
  ##
  ## **Parameters:**
  ## - ``gset`` : ``int``
  ##     The value of GSET enum index.
  ## - ``code`` : ``byte``
  ##     The byte of character.
  ## - ``enableAdditionalSymbols`` : ``bool``
  ##     Whether to enable additional symbols.
  ## - ``charCodeBuf`` : ``var seq[byte]``
  ##     Character codes buffer.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded string.
  case gset
  # Ignore DRCS
  of ord(GSET.UNDEFINED):
    result = ""
  # 2-byte character
  of ord(GSET.KANJI),
     ord(GSET.JIS_COMPATIBLE_KANJI_PLANE_1),
     ord(GSET.JIS_COMPATIBLE_KANJI_PLANE_2):
    if charCodeBuf.len > 0:
      charCodeBuf.add(code)
      result = decodeKanji(charCodeBuf[0], charCodeBuf[1])
    else:
      charCodeBuf.add(code)
      result = ""
  of ord(GSET.ADDITIONAL_SYMBOLS):
    if enableAdditionalSymbols:
      if charCodeBuf.len > 0:
        charCodeBuf.add(code)
        result = decodeKanji(charCodeBuf[0], charCodeBuf[1])
      else:
        charCodeBuf.add(code)
        result = ""
    else:
      result = ""
  # Alphanumeric
  of ord(GSET.ALPHANUMERIC), ord(GSET.PROPORTIONAL_ALPHANUMERIC):
    if IS_2BYTE_SIZE[csize]:
      result = decodeAlphanumeric(code)
    else:
      result = $char(code and byte(0x7F))
  # Hiragana
  of ord(GSET.HIRAGANA), ord(GSET.PROPORTIONAL_HIRAGANA):
    result = decodeHiragana(code)
  # Katakana
  of ord(GSET.KATAKANA), ord(GSET.PROPORTIONAL_KATAKANA):
    result = decodeKatakana(code)
  # JIS X 0201 katakana
  of ord(GSET.JIS_X_0201_KATAKANA):
    result = decodeJISX0201Katakana(code)
  # Ignore others
  else:
    result = ""


proc designateGSET(codeGIdx : int, fcode : byte) : bool {.discardable.} =
  ## Designate GSET.
  ##
  ## If fcode is correct, return true.
  ##
  ## **Parameters:**
  ## - ``codeGIdx`` : ``int``
  ##     Index of GSET (G1, G2, G3, G4).
  ## - ``fcode`` : ``byte``
  ##     Final character.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether fcode is correct or not.
  result = true

  case fcode
  of 0x42:
    codeG[codeGIdx] = ord(GSET.KANJI)
  of 0x4A:
    codeG[codeGIdx] = ord(GSET.ALPHANUMERIC)
  of 0x30:
    codeG[codeGIdx] = ord(GSET.HIRAGANA)
  of 0x31:
    codeG[codeGIdx] = ord(GSET.KATAKANA)
  of 0x32:
    codeG[codeGIdx] = ord(GSET.MOSAIC_A)
  of 0x33:
    codeG[codeGIdx] = ord(GSET.MOSAIC_B)
  of 0x34:
    codeG[codeGIdx] = ord(GSET.MOSAIC_C)
  of 0x35:
    codeG[codeGIdx] = ord(GSET.MOSAIC_D)
  of 0x36:
    codeG[codeGIdx] = ord(GSET.PROPORTIONAL_ALPHANUMERIC)
  of 0x37:
    codeG[codeGIdx] = ord(GSET.PROPORTIONAL_HIRAGANA)
  of 0x38:
    codeG[codeGIdx] = ord(GSET.PROPORTIONAL_KATAKANA)
  of 0x49:
    codeG[codeGIdx] = ord(GSET.JIS_X_0201_KATAKANA)
  of 0x39:
    codeG[codeGIdx] = ord(GSET.JIS_COMPATIBLE_KANJI_PLANE_1)
  of 0x3A:
    codeG[codeGIdx] = ord(GSET.JIS_COMPATIBLE_KANJI_PLANE_2)
  of 0x3B:
    codeG[codeGIdx] = ord(GSET.ADDITIONAL_SYMBOLS)
  else:
    result = false


proc designateDRCS(codeGIdx : int, fcode : byte) : bool {.discardable.} =
  ## Designate DRCS. (But ignore DRCS.)
  ##
  ## If fcode is correct, return true.
  ##
  ## **Parameters:**
  ## - ``codeGIdx`` : ``int``
  ##     Index of GSET (G1, G2, G3, G4).
  ## - ``fcode`` : ``byte``
  ##     Final character.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether fcode is correct or not.
  result = true

  case fcode
  # DRCS-0 -- 15, MACRO
  of 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
     0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x70:
    codeG[codeGIdx] = ord(GSET.UNDEFINED)
  else:
    result = false


proc decodeEsc(escCode : byte, escCodeBuf : var seq[byte]) : bool =
  ## Decode ESC codes.
  ##
  ## **Parameters:**
  ## - ``escCode`` : ``byte``
  ##     The byte of ESC codes.
  ## - ``escCodeBuf`` : ``var seq[byte]``
  ##     ESC codes buffer.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether the decoding process is completed or not.
  result = false
  escCodeBuf.add(escCode)

  case escCodeBuf.len
  of 1:
    case escCodeBuf[0]
    of 0x6E:
      # ESC 0x6E
      lockGL = codeG[2].addr
      result = true
    of 0x6F:
      # ESC 0x6F
      lockGL = codeG[3].addr
      result = true
    of 0x7E:
      # ESC 0x7E
      lockGR = codeG[1].addr
      result = true
    of 0x7D:
      # ESC 0x7D
      lockGR = codeG[2].addr
      result = true
    of 0x7C:
      # ESC 0x7C
      lockGR = codeG[3].addr
      result = true
    else:
      discard
  of 2:
    case escCodeBuf[0]
    of 0x28, 0x29, 0x2A, 0x2B:
      case escCodeBuf[1]
      of 0x20:
        discard
      else:
        # ESC 0x28 F
        # ESC 0x29 F
        # ESC 0x2A F
        # ESC 0x2B F
        designateGSET(int(escCodeBuf[0]) - 0x28, escCodeBuf[1])
        result = true
    of 0x24:
      case escCodeBuf[1]
      of 0x28, 0x29, 0x2A, 0x2B:
        discard
      else:
        # ESC 0x24 F
        designateGSET(0, escCodeBuf[1])
        result = true
    else:
      discard
  of 3:
    case escCodeBuf[0]
    of 0x28, 0x29, 0x2A, 0x2B:
      case escCodeBuf[1]
      of 0x20:
        # ESC 0x28 0x20 F
        # ESC 0x29 0x20 F
        # ESC 0x2A 0x20 F
        # ESC 0x2B 0x20 F
        designateDRCS(int(escCodeBuf[0]) - 0x28, escCodeBuf[2])
        result = true
      else:
        discard
    of 0x24:
      case escCodeBuf[1]
      of 0x28, 0x29, 0x2A, 0x2B:
        case escCodeBuf[2]
        of 0x20:
          discard
        else:
          # ESC 0x24 0x29 F
          # ESC 0x24 0x2A F
          # ESC 0x24 0x2B F
          designateGSET(int(escCodeBuf[1]) - 0x28, escCodeBuf[2])
          result = true
      else:
        discard
    else:
      discard
  of 4:
    case escCodeBuf[0]
    of 0x24:
      case escCodeBuf[1]
      of 0x28, 0x29, 0x2A, 0x2B:
        case escCodeBuf[2]
        of 0x20:
          # ESC 0x24 0x28 0x20 F
          # ESC 0x24 0x29 0x20 F
          # ESC 0x24 0x2A 0x20 F
          # ESC 0x24 0x2B 0x20 F
          designateDRCS(int(escCodeBuf[1]) - 0x28, escCodeBuf[3])
          result = true
        else:
          discard
      else:
        discard
    else:
      discard
  else:
    discard


proc aribdecode(aribCodes : seq[byte],
                enableAdditionalSymbols : bool) : string =
  ## Decode arib character codes.
  ##
  ## **Parameters:**
  ## - ``aribCodes`` : ``seq[byte]``
  ##     The byte sequence of ARIB character codes.
  ## - ``enableAdditionalSymbols`` : ``bool``
  ##     Whether to enable additional symbols.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     Decoded strings.
  result = ""

  var
    # Current GSET
    currG : int
    # Code buffer
    charCodeBuf : seq[byte] = @[]
    escCodeBuf : seq[byte] = @[]
    # Processing flag
    escProcessing : bool = false
    csizeProcessing : bool = false

  # Initialize G0, G1, G2, G3
  codeG[0] = ord(GSET.KANJI)
  codeG[1] = ord(GSET.ALPHANUMERIC)
  codeG[2] = ord(GSET.HIRAGANA)
  codeG[3] = ord(GSET.KATAKANA)

  # Initialize GL, GR
  lockGL = codeG[0].addr
  lockGR = codeG[2].addr

  # Initialize Character size
  csize = ord(CSIZE.NSZ)

  for aribCode in aribCodes:
    if charCodeBuf.len > 0:
      result &= decodeCharacter(currG, aribCode,
                                enableAdditionalSymbols, charCodeBuf)
      charCodeBuf = @[]
    elif escProcessing:
      escProcessing = not decodeEsc(aribCode, escCodeBuf)
      if not escProcessing:
        escCodeBuf = @[]
    elif csizeProcessing:
      # Character size: SZX
      case aribCode
      of 0x60:
        csize = ord(CSIZE.SZX_60)
      of 0x41:
        csize = ord(CSIZE.SZX_41)
      of 0x44:
        csize = ord(CSIZE.SZX_44)
      of 0x45:
        csize = ord(CSIZE.SZX_45)
      of 0x6B:
        csize = ord(CSIZE.SZX_6B)
      of 0x64:
        csize = ord(CSIZE.SZX_64)
      else:
        discard
      csizeProcessing = false
    else:
      if int(aribCode) > 0x20 and int(aribCode) < 0x7F:
        # GL area
        currG = if isNil(singleGL) : lockGL[] else: singleGL[]
        singleGL = nil
        result &= decodeCharacter(currG, aribCode,
                                  enableAdditionalSymbols, charCodeBuf)
      elif int(aribCode) > 0xA0 and int(aribCode) < 0xFF:
        # GR area
        currG = lockGR[]
        result &= decodeCharacter(currG, aribCode,
                                  enableAdditionalSymbols, charCodeBuf)
      else:
        # Control code
        case aribCode
        # ESC
        of 0x1B:
          escProcessing = true
        # Locking shift / Single shift
        of 0x0F:
          lockGL = codeG[0].addr
        of 0x0E:
          lockGL = codeG[1].addr
        of 0x19:
          singleGL = codeG[2].addr
        of 0x1D:
          singleGL = codeG[3].addr
        # Character size
        of 0x88:
          csize = ord(CSIZE.SSZ)
        of 0x89:
          csize = ord(CSIZE.MSZ)
        of 0x8A:
          csize = ord(CSIZE.NSZ)
        of 0x8B:
          csizeProcessing = true
        # Space
        of 0x20:
          if IS_2BYTE_SIZE[csize]:
            result &= "　"
          else:
            result &= ' '
        else:
          discard
