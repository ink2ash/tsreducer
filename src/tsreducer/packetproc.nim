import tables
from algorithm import fill

import ./aribdecode
import ./epgevent
import ./crc32
import ./pidbuffer
import ./timestamp


const PACKET_SIZE : int = 188

type PIDContinuityCounterTuple = tuple[pid : int, continuityCounter : int]
var pidContinuityCounters : Table[int, int] = (
  newSeq[PIDContinuityCounterTuple](0).toTable
)

type ReducedSectionTuple = tuple[pidCRC : int, reducedSection : seq[byte]]
var reducedSections : Table[int, seq[byte]] = (
  newSeq[ReducedSectionTuple](0).toTable
)

var programId : int = 0x10000


proc createContinuityCounter(pid : int) : bool {.discardable.}
proc incContinuityCounter(pid : int, n : int) : void
proc reducePAT(section : seq[byte]) : seq[byte]
proc reducePMT(section : seq[byte]) : seq[byte]
proc reduceSection*(pid : int, section : seq[byte]) : seq[byte]
proc makeTSPacket*(pid : int, section : seq[byte]) : seq[seq[byte]]
proc parseEIT(section : seq[byte]) : void
proc parseTDT(section : seq[byte]) : void
proc parseSI*(pid : int, section : seq[byte]) : void
proc modifyPCR(pid : int, packet : seq[byte]) : seq[byte]
proc modifyES(pid : int, packet : seq[byte]) : seq[byte]
proc modifyPacketTime*(pid : int, packet : seq[byte]) : seq[byte]


# --------------- Util --------------------------------------------------------
proc createContinuityCounter(pid : int) : bool {.discardable.} =
  ## Create continuity counter.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether created or not.
  result = false
  if not (pid in pidContinuityCounters):
    pidContinuityCounters[pid] = 0
    result = true


proc incContinuityCounter(pid : int, n : int) : void =
  ## Increment continuity counter.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``n`` : ``int``
  ##     Number to increment continuity counter.
  pidContinuityCounters[pid] = (pidContinuityCounters[pid] + n) and 0x0F


# --------------- Reducer -----------------------------------------------------
proc reducePAT(section : seq[byte]) : seq[byte] =
  ## Reduce PAT sections.
  ##
  ## **Parameters:**
  ## - ``section`` : ``seq[byte]``
  ##     Original PAT section data.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Reduced PAT section data.
  result = section[0..7]

  # Extract information of NIT/PMT
  let progCnt : int = (section.len - 12) div 4
  for i in 0..<progCnt:
    result &= section[(4 * i + 8)..<(4 * i + 12)]

    let
      progNumId : int = ((int(section[4 * i + 8]) shl 8) or
                         int(section[4 * i + 9]))
      progPID : int = (((int(section[4 * i + 10]) and 0x1F) shl 8) or
                       int(section[4 * i + 11]))

    if progNumId == 0x0000:
      # NIT
      pidbuffer.registerPIDBuffer(progPID)
    else:
      # PMT
      programId = progNumId
      pidbuffer.registerPIDBuffer(progPID, "PMT")
      # Register ONLY first PMT
      break


proc reducePMT(section : seq[byte]) : seq[byte] =
  ## Reduce PMT sections.
  ##
  ## **Parameters:**
  ## - ``section`` : ``seq[byte]``
  ##     Original PMT section data.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Reduced PMT section data.
  let pcrPID : int = (((int(section[8]) and 0x1F) shl 8) or
                      int(section[9]))
  pidbuffer.registerPIDBuffer(pcrPID, "PCR")

  # Descriptors field 1
  var descPos : int = 12
  let progInfoLength : int = (((int(section[10]) and 0x0F) shl 8) or
                              int(section[11]))
  while descPos < progInfoLength + 12:
    let
      descTag : int = int(section[descPos])
      descLength : int = int(section[descPos + 1])
    if descTag == 0x09:
      # Register ECM
      let ecmPID : int = (((int(section[descPos + 4]) and 0x1F) shl 8) or
                          int(section[descPos + 5]))
      pidbuffer.registerPIDBuffer(ecmPID)
      break
    descPos += descLength + 2

  var pos : int = progInfoLength + 12
  result = section[0..<pos]

  # Stream
  while pos < section.len - 4:
    let
      streamId : int = int(section[pos])
      esPID : int = (((int(section[pos + 1]) and 0x1F) shl 8) or
                     int(section[pos + 2]))
      esInfoLength : int = (((int(section[pos + 3]) and 0x0F) shl 8) or
                            int(section[pos + 4]))

    # Leave following streams
    # - ITU-T Rec. H.262|ISO/IEC 13818-2 Video or ISO/IEC 11172-2
    #   constrained parameter video stream
    # - AVC video stream as defined in ITU-T Rec. H.264|ISO/IEC 14496-10 Video
    # - ISO/IEC 13818-7 Audio with ADTS transport syntax
    # - ITU-T Rec. H.222.0|ISO/IEC 13818-1 PES packets containing private data
    if (streamId == 0x02 or streamId == 0x1B or
        streamId == 0x0F or streamId == 0x06):
      pidbuffer.registerPIDBuffer(esPID, "ES")
      result &= section[pos..(pos+esInfoLength + 4)]

    pos += esInfoLength + 5


proc reduceSection(pid : int, section : seq[byte]) : seq[byte] =
  ## Reduce sections (mainly PAT and PMT).
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``section`` : ``seq[byte]``
  ##     Original section data.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Reduced section data.
  createContinuityCounter(pid)

  let
    orgCRCint : int = ((int(section[^4]) shl 24) or
                       (int(section[^3]) shl 16) or
                       (int(section[^2]) shl 8) or
                       int(section[^1]))
    pidCRC : int = (pid shl 32) or orgCRCint

  if pidCRC in reducedSections:
    result = reducedSections[pidCRC]
  else:
    if pid == 0x0000:
      # PAT
      result = reducePAT(section)

    elif pidbuffer.isPMT(pid):
      # PMT
      result = reducePMT(section)

    result[1] = (result[1] and 0xF0) or byte((result.len + 1) shr 8)
    result[2] = byte((result.len + 1) and 0xFF)

    let reducedCRC : seq[byte] = crc32.crc32(result)
    result &= reducedCRC

    reducedSections[pidCRC] = result


proc makeTSPacket(pid : int, section : seq[byte]) : seq[seq[byte]] =
  ## Make TS packets from a section.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``section`` : ``seq[byte]``
  ##     Section data.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Sequence of TS packets.
  var section : seq[byte] = section
  let
    continuityCounter : int = pidContinuityCounters[pid]
    adaptation : seq[byte] = pidbuffer.loadAdaptation(pid)
    packetNum : int = ((adaptation.len + section.len + 1) div
                       (PACKET_SIZE - 4) +
                       int((adaptation.len + section.len + 1) mod
                           (PACKET_SIZE - 4) > 0))

  incContinuityCounter(pid, packetNum)

  for i in 0..<packetNum:
    var
      packet : seq[byte] = @[]
      header : seq[byte] = pidbuffer.loadHeader(pid)
    header[3] = (header[3] and 0xF0) or byte((continuityCounter + i) and 0x0F)

    if i == 0:
      let pointerField : seq[byte] = @[byte(0x00)]
      packet &= header & adaptation & pointerField
    elif i > 0:
      # Set `payload_unit_start_indicator` at 0
      header[1] = header[1] and 0xBF
      # Set first bit of `adaptation_field_control` at 0
      header[3] = header[3] and 0xDF
      packet &= header

    let remainingLength : int = PACKET_SIZE - packet.len
    if remainingLength < section.len:
      packet &= section[0..<remainingLength]
      section = section[remainingLength..^1]
    else:
      let paddingLength : int = remainingLength - section.len
      var paddingSeq : seq[byte] = newSeq[byte](paddingLength)
      paddingSeq.fill(byte(0xFF))
      packet &= section & paddingSeq

    result.add(packet)


# --------------- SI ----------------------------------------------------------
proc parseEIT(section : seq[byte]) : void =
  ## Parse EIT sections.
  ##
  ## **Parameters:**
  ## - ``section`` : ``seq[byte]``
  ##     EIT section data.
  let
    tableId : int = int(section[0])
    serviceId : int = (int(section[3]) shl 8) or int(section[4])

  if tableId == 0x4E and programId == serviceId:
    var pos : int = 14
    while pos < section.len - 4:
      let
        eventId : int = (int(section[pos]) shl 8) or int(section[pos + 1])
        startTimeSeq : seq[byte] = section[(pos + 2)..(pos + 6)]
        durationSeq : seq[byte] = section[(pos + 7)..(pos + 9)]
        startTimestamp : int = timestamp.mjd2timestamp(startTimeSeq)
        duration : int = timestamp.duration2sec(durationSeq)
        descLoopLength : int = (((int(section[pos + 10]) and 0x0F) shl 8) or
                                int(section[pos + 11]))

      var descPos : int = pos + 12
      while descPos < pos + descLoopLength + 12:
        let
          descTag : int = int(section[descPos])
          descLength : int = int(section[descPos + 1])
          descField : seq[byte] = section[descPos..<(descPos + descLength + 2)]

        if descTag == 0x4D:
          let
            eventNameLength : int = int(descField[5])
            eventNameSeq : seq[byte] = descField[6..(5 + eventNameLength)]
            eventName : string = aribdecode.aribdecode(eventNameSeq, false)
            # textCharSeq : seq[byte] = descField[(7 + eventNameLength)..^1]
            # textChar : string = aribdecode.aribdecode(textCharSeq, false)
          epgevent.registerEvent(eventId, startTimestamp, duration, eventName)

        descPos += descLength + 2

      pos += descLoopLength + 12


proc parseTDT(section : seq[byte]) : void =
  ## Parse TDT sections.
  ##
  ## **Parameters:**
  ## - ``section`` : ``seq[byte]``
  ##     TDT section data.
  let
    jstSeq : seq[byte] = section[3..7]
    jst : int = timestamp.mjd2timestamp(jstSeq)
  timestamp.registerRelJST(jst)


proc parseSI(pid : int, section : seq[byte]) : void =
  ## Parse SI sections (mainly EIT and TDT).
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``section`` : ``seq[byte]``
  ##     SI section data.
  if pid == 0x0012:
    parseEIT(section)
  elif pid == 0x0014:
    parseTDT(section)


# --------------- Time --------------------------------------------------------
proc modifyPCR(pid : int, packet : seq[byte]) : seq[byte] =
  ## Modify PCR packets so that 27MHz PCR is based on 01:00:00.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``packet`` : ``seq[byte]``
  ##     Original PCR packet.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Modified PCR packet.
  result = packet

  let existsAdaptation : bool = ((packet[3] shr 5) and 0x01) == 1
  if existsAdaptation:
    let existsPCR : bool = ((packet[5] shr 4) and 0x01) == 1
    if existsPCR:
      let
        pcrSeq : seq[byte] = packet[6..11]
        timeId : int = timestamp.calcTimeId(pid, "PCR")
      var pcr : int = timestamp.byte2pcr(pcrSeq)
      timestamp.registerFirstTime(timeId, pcr)
      pcr = timestamp.modifyTime(timeId, pcr)
      timestamp.registerRelPCR(pcr)
      result[6..11] = timestamp.pcr2byte(pcr, pcrSeq)


proc modifyES(pid : int, packet : seq[byte]) : seq[byte] =
  ## Modify ES packets so that 90kHz PTS/DTS is based on 01:00:00.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``packet`` : ``seq[byte]``
  ##     Original ES packet.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Modified ES packet.
  result = packet

  let payloadUnitStart : bool = ((packet[1] shr 6) and 0x01) == 1
  if payloadUnitStart:
    var payloadPos : int = 4

    let existsAdaptation : bool = ((packet[3] shr 5) and 0x01) == 1
    if existsAdaptation:
      let adaptationLength : int = int(packet[payloadPos])
      payloadPos += adaptationLength + 1

    if (packet[payloadPos] == 0x00 and
        packet[payloadPos + 1] == 0x00 and
        packet[payloadPos + 2] == 0x01 and
        (packet[payloadPos + 6] shr 6) == 0x02):
      let
        existsPTS : bool = (packet[payloadPos + 7] shr 7) == 1
        existsDTS : bool = ((packet[payloadPos + 7] shr 6) and 0x01) == 1

      payloadPos += 9

      if existsPTS:
        let timeId : int = timestamp.calcTimeId(pid, "PTS")
        var
          ptsSeq : seq[byte] = packet[payloadPos..(payloadPos + 4)]
          pts : int = timestamp.byte2xts(ptsSeq)
        timestamp.registerFirstTime(timeId, pts)
        pts = timestamp.modifyTime(timeId, pts)
        result[payloadPos..(payloadPos + 4)] = timestamp.xts2byte(pts, ptsSeq)
        payloadPos += 5

      if existsDTS:
        let timeId : int = timestamp.calcTimeId(pid, "DTS")
        var
          dtsSeq : seq[byte] = packet[payloadPos..(payloadPos + 4)]
          dts : int = timestamp.byte2xts(dtsSeq)
        timestamp.registerFirstTime(timeId, dts)
        dts = timestamp.modifyTime(timeId, dts)
        result[payloadPos..(payloadPos + 4)] = timestamp.xts2byte(dts, dtsSeq)
        payloadPos += 5


proc modifyPacketTime(pid : int, packet : seq[byte]) : seq[byte] =
  ## Modify packets so that 27MHz PCR or 90kHz PTS/DTS is based on 01:00:00.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``packet`` : ``seq[byte]``
  ##     Original PCR or PTS/DTS packet.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Modified PCR or PTS/DTS packet.
  result = packet

  if pidbuffer.isPCR(pid):
    result = modifyPCR(pid, packet)
  elif pidbuffer.isES(pid):
    result = modifyES(pid, packet)
