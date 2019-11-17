import logging
import tables
from strutils import toHex


const PACKET_SIZE : int = 188

type PIDBuffer = object
  ## PID section buffer object.
  ##
  ## **Attributes:**
  ## - ``header`` : ``seq[byte]``
  ##     The header of the first packet.
  ## - ``adaptation`` : ``seq[byte]``
  ##     The adaptation field of the first packet.
  ## - ``section`` : ``array[4096, byte]``
  ##     The section of packets.
  ## - ``size`` : ``int``
  ##     The section size.
  ## - ``pos`` : ``int``
  ##     The position of ``section``.
  ## - ``sectionType`` : ``int``
  ##     - 1: PMT
  ##     - 2: ES
  ##     - 3: PCR
  ##     - 0: Other
  ## - ``continuityCounter`` : ``int``
  ##     The continuity counter of the first packet.
  ## - ``existsDrop`` : ``bool``
  ##     Whether the packet drop exists or not.
  header : seq[byte]
  adaptation : seq[byte]
  section : array[4096, byte]
  size : int
  pos : int
  sectionType : int
  continuityCounter : int
  existsDrop : bool

type PIDBufferTuple = tuple[pid : int, buf : PIDBuffer]
var pidBufs : Table[int, PIDBuffer] = newSeq[PIDBufferTuple](0).toTable


proc isPMT*(pid : int) : bool
proc isES*(pid : int) : bool
proc isPCR*(pid : int) : bool
proc existsPIDBuffer*(pid : int) : bool
proc registerPIDBuffer*(pid : int,
                        sectionTypeStr : string = "") : bool {.discardable.}
proc storePIDBuffer*(pid : int, packet : seq[byte],
                     hasDualSection : var bool) : bool
proc loadHeader*(pid : int) : seq[byte]
proc loadAdaptation*(pid : int) : seq[byte]
proc loadSection*(pid : int) : seq[byte]


proc isPMT(pid : int) : bool =
  ## Whether ``pid`` indicates PMT or not.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``pid`` indicates PMT or not.
  result = pidBufs[pid].sectionType == 1


proc isES(pid : int) : bool =
  ## Whether ``pid`` indicates ES or not.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``pid`` indicates ES or not.
  result = pidBufs[pid].sectionType == 2


proc isPCR(pid : int) : bool =
  ## Whether ``pid`` indicates PCR or not.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``pid`` indicates PCR or not.
  result = pidBufs[pid].sectionType == 3


proc existsPIDBuffer(pid : int) : bool =
  ## Whether ``pid`` is in ``pidBufs`` or not.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``pid`` is in ``pidBufs`` or not.
  result = pid in pidBufs


proc registerPIDBuffer(pid : int,
                       sectionTypeStr : string = "") : bool {.discardable.} =
  ## Register ``pid`` in ``pidBufs``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``sectionTypeStr`` : ``string`` (default: ``""``)
  ##     String of section type ("PMT", "ES", "PCR" or "").
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether new registration is successful or not.
  if existsPIDBuffer(pid):
    return false

  case sectionTypeStr
  of "PMT":
    pidBufs[pid] = PIDBuffer(sectionType: 1, continuityCounter: -1)
  of "ES":
    pidBufs[pid] = PIDBuffer(sectionType: 2, continuityCounter: -1)
  of "PCR":
    pidBufs[pid] = PIDBuffer(sectionType: 3, continuityCounter: -1)
  else:
    pidBufs[pid] = PIDBuffer(sectionType: 0, continuityCounter: -1)

  return true


proc storePIDBuffer(pid : int, packet : seq[byte],
                    hasDualSection : var bool) : bool =
  ## Store section data in ``pidBufs``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``packet`` : ``seq[byte]``
  ##     A packet of MPEG-2 TS.
  ## - ``hasDualSection`` : ``var bool``
  ##     Whether ``packet`` has a dual section or not.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether section data is complete or not.
  hasDualSection = false

  var
    payloadUnitStart : bool = ((packet[1] shr 6) and 0x01) == 1
    existsAdaptation : bool = ((packet[3] shr 5) and 0x01) == 1
    existsError : bool = (packet[1] shr 7) == 1
    continuityCounter : int = int(packet[3] and 0x0F)
    isDiscontinuity : bool = false

  if existsError:
    log(lvlWarn, "Transport Error: PID = ", pid.toHex[^4..^1])
    pidBufs[pid].existsDrop = true
    return false

  if payloadUnitStart:
    # Header
    pidBufs[pid].header = packet[0..3]

    var payloadPos : int = 4

    # Adaptation field
    if existsAdaptation:
      var adaptationLength : int = int(packet[payloadPos])
      pidBufs[pid].adaptation = packet[payloadPos..
                                       (payloadPos + adaptationLength)]
      if adaptationLength > 0:
        isDiscontinuity = (packet[payloadPos + 1] shr 7) == 1
      payloadPos += adaptationLength + 1
    else:
      pidBufs[pid].adaptation = @[]

    var pointerField = int(packet[payloadPos])
    payloadPos += 1

    # Maybe has a dual section
    if pidBufs[pid].size != pidBufs[pid].pos:
      if isDiscontinuity:
        pidBufs[pid].continuityCounter = continuityCounter
      else:
        if continuityCounter != (pidBufs[pid].continuityCounter + 1) mod 16:
          log(lvlWarn, "Invalid discontinuity: PID = ", pid.toHex[^4..^1])
          pidBufs[pid].existsDrop = true
          return false

      if pidBufs[pid].pos > 0 and pidBufs[pid].pos < pidBufs[pid].size:
        pidBufs[pid].section[
          pidBufs[pid].pos..<(pidBufs[pid].pos + pointerField)
        ] = packet[payloadPos..<(payloadPos + pointerField)]
        pidBufs[pid].pos += pointerField
        hasDualSection = true
        return not pidBufs[pid].existsDrop

    payloadPos += pointerField

    # ES is NOT supported
    if isES(pid):
      return false

    # New section
    var
      sectionLength : int = ((int(packet[payloadPos + 1]) and 0x0F) shl 8) or
                             int(packet[payloadPos + 2])
      payloadSize : int = sectionLength + 3

    pidBufs[pid].size = payloadSize
    pidBufs[pid].pos = 0
    pidBufs[pid].existsDrop = existsError
    pidBufs[pid].continuityCounter = continuityCounter

    if payloadPos + payloadSize <= PACKET_SIZE:
      # Section is completed in one packet
      pidBufs[pid].section[
        pidBufs[pid].pos..<(pidBufs[pid].pos + payloadSize)
      ] = packet[payloadPos..<(payloadPos + payloadSize)]
      pidBufs[pid].pos += payloadSize

      if pidBufs[pid].size != pidBufs[pid].pos:
        log(lvlWarn, "Exists drop: PID = ", pid.toHex[^4..^1])
        pidBufs[pid].pos = pidBufs[pid].size
        pidBufs[pid].existsDrop = true

      return not pidBufs[pid].existsDrop
    else:
      # Section is divided into two or more packets
      pidBufs[pid].section[
        pidBufs[pid].pos..<(pidBufs[pid].pos + (PACKET_SIZE - payloadPos))
      ] = packet[payloadPos..<PACKET_SIZE]
      pidBufs[pid].pos += PACKET_SIZE - payloadPos
  else:
    if (pidBufs[pid].size == 0) or pidBufs[pid].existsDrop:
      return false

    if continuityCounter != (pidBufs[pid].continuityCounter + 1) mod 16:
      log(lvlWarn, "Invalid discontinuity: PID = ", pid.toHex[^4..^1])
      pidBufs[pid].existsDrop = true
      return false

    pidBufs[pid].continuityCounter = continuityCounter

    if pidBufs[pid].size - pidBufs[pid].pos <= PACKET_SIZE - 4:
      pidBufs[pid].section[
        pidBufs[pid].pos..<pidBufs[pid].size
      ] = packet[4..<(4 + (pidBufs[pid].size - pidBufs[pid].pos))]
      pidBufs[pid].pos += pidBufs[pid].size - pidBufs[pid].pos

      if pidBufs[pid].size != pidBufs[pid].pos:
        log(lvlWarn, "Exists drop: PID = ", pid.toHex[^4..^1])
        pidBufs[pid].pos = pidBufs[pid].size
        pidBufs[pid].existsDrop = true

      return not pidBufs[pid].existsDrop
    else:
      pidBufs[pid].section[
        pidBufs[pid].pos..<(pidBufs[pid].pos + (PACKET_SIZE - 4))
      ] = packet[4..<PACKET_SIZE]
      pidBufs[pid].pos += PACKET_SIZE - 4

  return false


proc loadHeader(pid : int) : seq[byte] =
  ## Load header from ``pidBufs``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Byte sequence of header.
  result = pidBufs[pid].header


proc loadAdaptation(pid : int) : seq[byte] =
  ## Load adaptation field from ``pidBufs``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Byte sequence of adaptation field.
  result = pidBufs[pid].adaptation


proc loadSection(pid : int) : seq[byte] =
  ## Load section from ``pidBufs``.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``seq[byte]``
  ##     Byte sequence of section.
  result = pidBufs[pid].section[0..<pidBufs[pid].size]
