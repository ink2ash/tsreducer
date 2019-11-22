## timestamp
##
## Copyright (c) 2019 ink2ash
##
## This software is released under the MIT License.
## http://opensource.org/licenses/mit-license.php

import tables
from strformat import fmt
from times import DateTime, parse, toTime, toUnix


type FirstTimeTuple = tuple[timeId : int, firstTime : int]
var firstTimes : Table[int, int] = newSeq[FirstTimeTuple](0).toTable

type RelPCR2JST = object
  pcr : int
  jst : int
var relPCR2JST : RelPCR2JST = RelPCR2JST(pcr: -1, jst: -1)


proc mjd2timestamp*(timeData : seq[byte]) : int
proc duration2sec*(durationData : seq[byte]) : int
proc byte2pcr*(pcrData : seq[byte]) : int
proc byte2xts*(xtsData : seq[byte]) : int
proc pcr2byte*(pcr : int, pcrOrgData : seq[byte]) : seq[byte]
proc xts2byte*(xts : int, xtsOrgData : seq[byte]) : seq[byte]
proc calcTimeId*(pid : int, timeTypeStr : string) : int
proc existsFirstTime(timeId : int) : bool
proc registerFirstTime*(timeId : int, time : int) : bool {.discardable.}
proc getFirstTime(timeId : int) : int
proc modifyTime*(timeId : int, time : int) : int
proc registerRelPCR*(pcr : int) : bool {.discardable.}
proc registerRelJST*(jst : int) : bool {.discardable.}
proc getRelPCR*() : int
proc getRelJST*() : int


proc mjd2timestamp(timeData : seq[byte]) : int =
  ## Convert MJD (Japan time) to JST timestamp.
  ##
  ## **Parameters:**
  ## - ``timeData`` : ``seq[byte]``
  ##     Byte sequence of MJD (Japan time).
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     JST timestamp.
  let
    mjd : int = (int(timeData[0]) shl 8) or int(timeData[1])
    yy : int = int((float(mjd) - 15078.2) / 365.25)
    mm : int = int((float(mjd) - 14956.1 - float(int(float(yy) * 365.25))) /
                   30.6001)
    k : int = if mm == 14 and mm == 15: 1 else: 0
    year : int = 1900 + yy + k
    month : int = mm - 1 - k * 12
    day : int = (mjd - 14956 - int(float(yy) * 365.25) -
                 int(float(mm) * 30.6001))
    hour   : int = int(timeData[2] shr 4) * 10 + int(timeData[2] and 0x0F)
    minute : int = int(timeData[3] shr 4) * 10 + int(timeData[3] and 0x0F)
    second : int = int(timeData[4] shr 4) * 10 + int(timeData[4] and 0x0F)
    dtStr : string = fmt"{year:04}" & "-" & fmt"{month:02}" & "-" &
                     fmt"{day:02}" & "T" & fmt"{hour:02}" & ":" &
                     fmt"{minute:02}" & ":" & fmt"{second:02}" & "+09:00"
    dt : DateTime = parse(dtStr, "yyyy-MM-dd\'T\'HH:mm:sszzz")
  result = int(dt.toTime().toUnix())


proc duration2sec(durationData : seq[byte]) : int =
  ## Convert ``durationData`` to second.
  ##
  ## **Parameters:**
  ## - ``durationData`` : ``seq[byte]``
  ##     Byte sequence of duration.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     Duration second.
  let
    hour   : int = (int(durationData[0] shr 4) * 10 +
                    int(durationData[0] and 0x0F))
    minute : int = (int(durationData[1] shr 4) * 10 +
                    int(durationData[1] and 0x0F))
    second : int = (int(durationData[2] shr 4) * 10 +
                    int(durationData[2] and 0x0F))
  result = hour * 3600 + minute * 60 + second


proc byte2pcr(pcrData : seq[byte]) : int =
  ## Convert ``pcrData`` to 27MHz PCR.
  ##
  ## **Parameters:**
  ## - ``pcrData`` : ``seq[byte]``
  ##     Byte sequence of PCR.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     27MHz PCR.
  let
    pcrBase : int = ((int(pcrData[0]) shl 25) or (int(pcrData[1]) shl 17) or
                     (int(pcrData[2]) shl  9) or (int(pcrData[3]) shl  1) or
                     (int(pcrData[4]) shr  7))
    pcrExtension : int = ((int(pcrData[4]) and 0x01) shl 8) or int(pcrData[5])
  result = pcrBase * 300 + pcrExtension


proc byte2xts(xtsData : seq[byte]) : int =
  ## Convert ``xtsData`` to 90kHHz PTS/DTS.
  ##
  ## **Parameters:**
  ## - ``xtsData`` : ``seq[byte]``
  ##     Byte sequence of PTS/DTS.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     90kHHz PTS/DTS.
  let xts : int = ((int(xtsData[0] and 0x0E) shl 29) or
                   (int(xtsData[1])          shl 22) or
                   (int(xtsData[2] shr 1)    shl 15) or
                   (int(xtsData[3])          shl  7) or
                   (int(xtsData[4])          shr  1))
  result = xts


proc pcr2byte(pcr : int, pcrOrgData : seq[byte]) : seq[byte] =
  ## Convert 27MHz PCR to ``seq[byte]``.
  ##
  ## **Parameters:**
  ## - ``pcr`` : ``int``
  ##     27MHz PCR.
  ## - ``pcrOrgData`` : ``seq[byte]``
  ##     Byte sequence of original PCR.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Byte sequence of PCR.
  let
    pcrBase : int = pcr div 300
    pcrExtension : int = pcr mod 300

  result = pcrOrgData
  result[0] = byte(pcrBase shr 25)
  result[1] = byte((pcrBase shr 17) and 0xFF)
  result[2] = byte((pcrBase shr  9) and 0xFF)
  result[3] = byte((pcrBase shr  1) and 0xFF)
  result[4] = (byte((pcrBase shl  7) and 0x80) or (pcrOrgData[4] and 0x7E) or
               byte(pcrExtension shr 8))
  result[5] = byte(pcrExtension and 0xFF)


proc xts2byte(xts : int, xtsOrgData : seq[byte]) : seq[byte] =
  ## Convert 90kHz PTS/DTS to ``seq[byte]``.
  ##
  ## **Parameters:**
  ## - ``xts`` : ``int``
  ##     90kHz PTS/DTS.
  ## - ``xtsOrgData`` : ``seq[byte]``
  ##     Byte sequence of original PTS/DTS.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Byte sequence of PTS/DTS.
  result = xtsOrgData
  result[0] = byte(xts shr 29) or (xtsOrgData[0] and 0xF1)
  result[1] = byte((xts shr 22) and 0xFF)
  result[2] = byte((xts shr 14) and 0xFE) or (xtsOrgData[2] and 0x01)
  result[3] = byte((xts shr  7) and 0xFF)
  result[4] = byte((xts shl  1) and 0xFE) or (xtsOrgData[4] and 0x01)


proc calcTimeId(pid : int, timeTypeStr : string) : int =
  ## Calculate ``timeId`` from ``pid`` and ``timeTypeStr``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``timeTypeStr`` : ``string``
  ##     String of time type ("PCR", "PTS" or "DTS").
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     Value calculated from packet identifier and
  ##     time type ("PCR", "PTS" or "DTS").
  case timeTypeStr
  of "PCR":
    result = 0x00000 or pid
  of "PTS":
    result = 0x10000 or pid
  of "DTS":
    result = 0x20000 or pid
  else    :
    result = 0x100000


proc existsFirstTime(timeId : int) : bool =
  ## Whether ``timeId`` is in ``firstTimes`` or not.
  ##
  ## **Parameters:**
  ## - ``timeId`` : ``int``
  ##     Value calculated from packet identifier and
  ##     time type ("PCR", "PTS" or "DTS").
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``timeId`` is in ``firstTimes`` or not.
  result = timeId in firstTimes


proc registerFirstTime(timeId : int, time : int) : bool {.discardable.} =
  ## Register ``timeId`` in ``firstTimes``.
  ##
  ## **Parameters:**
  ## - ``timeId`` : ``int``
  ##     Value calculated from packet identifier and
  ##     time type ("PCR", "PTS" or "DTS").
  ## - ``time`` : ``int``
  ##     First 27MHz PCR or 90kHz PTS/DTS.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether new registration is successful or not.
  result = false

  if not existsFirstTime(timeId):
    firstTimes[timeId] = time
    result = true


proc getFirstTime(timeId : int) : int =
  ## Get First 27MHz PCR or 90kHz PTS/DTS of ``timeId``.
  ##
  ## **Parameters:**
  ## - ``timeId`` : ``int``
  ##     Value calculated from packet identifier and
  ##     time type ("PCR", "PTS" or "DTS").
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     First 27MHz PCR or 90kHz PTS/DTS.
  result = firstTimes[timeId]


proc modifyTime(timeId : int, time : int) : int =
  ## Modify 27MHz PCR or 90kHz PTS/DTS based on 01:00:00.
  ##
  ## **Parameters:**
  ## - ``timeId`` : ``int``
  ##     Value calculated from packet identifier and
  ##     time type ("PCR", "PTS" or "DTS").
  ## - ``time`` : ``int``
  ##     Original 27MHz PCR or 90kHz PTS/DTS.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     Modified 27MHz PCR or 90kHz PTS/DTS.
  let typeBit : int = timeId shr 16
  case typeBit
  # PCR
  of 0:
    # 1[hour] * 60[min] * 60[sec] * 27_000_000[Hz]
    result = time - getFirstTime(timeId) + int(97_200_000_000)
  # PTS/DTS
  of 1, 2:
    # 1[hour] * 60[min] * 60[sec] * 90_000[Hz]
    result = time - getFirstTime(timeId) + int(324_000_000)
  else:
    result = time


proc registerRelPCR(pcr : int) : bool {.discardable.} =
  ## Register ``pcr`` in ``relPCR2JST``.
  ##
  ## **Parameters:**
  ## - ``pcr`` : ``int``
  ##     27MHz PCR.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether new registration is successful or not.
  if relPCR2JST.jst < 0:
    relPCR2JST.pcr = pcr
    result = true
  else:
    result = false


proc registerRelJST(jst : int) : bool {.discardable.} =
  ## Register ``jst`` in ``relPCR2JST``.
  ##
  ## **Parameters:**
  ## - ``jst`` : ``int``
  ##     JST timestamp.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether new registration is successful or not.
  if relPCR2JST.jst < 0:
    if relPCR2JST.pcr < 0:
      result = false
    else:
      relPCR2JST.jst = jst
      result = true
  else:
    result = false


proc getRelPCR() : int =
  ## Get 27MHz PCR from ``relPCR2JST``.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     27MHz PCR.
  result = relPCR2JST.pcr


proc getRelJST() : int =
  ## Get JST timestamp from ``relPCR2JST``.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     JST timestamp.
  result = relPCR2JST.jst
