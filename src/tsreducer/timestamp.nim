from strformat import fmt
from times import DateTime, parse, toTime, toUnix


proc mjd2timestamp*(timeData : seq[byte]) : int
proc duration2sec*(durationData : seq[byte]) : int


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
