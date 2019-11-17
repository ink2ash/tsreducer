import tables
from algorithm import fill

import ./crc32
import ./pidbuffer


const PACKET_SIZE : int = 188

type PIDContinuityCounterTuple = tuple[pid : int, continuityCounter : int]
var pidContinuityCounters : Table[int, int] = (
  newSeq[PIDContinuityCounterTuple](0).toTable
)

type ReducedSectionTuple = tuple[pidCRC : int, reducedSection : seq[byte]]
var reducedSections : Table[int, seq[byte]] = (
  newSeq[ReducedSectionTuple](0).toTable
)

proc createContinuityCounter(pid : int) : bool {.discardable.}
proc incContinuityCounter(pid : int, n : int) : void
proc reducePAT*(section : seq[byte]) : seq[byte]
proc reducePMT*(section : seq[byte]) : seq[byte]
proc reduceSection*(pid : int, section : seq[byte]) : seq[byte]
proc makeTSPacket*(pid : int, section : seq[byte]) : seq[seq[byte]]


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

    elif isPMT(pid):
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