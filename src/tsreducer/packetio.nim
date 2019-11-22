import logging
from os import sleep
from strformat import fmt
from times import Time, getTime, nanosecond, toUnix


const
  PACKET_SIZE : int = 188
  PACKET_NUM : int = 100000

var
  progressFlag* : bool = false
  readPacketSize : int = 0
  readTotalPacketNum : int = 0
  writeTotalPacketNum : int = 0


proc humanReadable(value : float) : (float, string)
proc progressMonitor*() : void {.thread.}
proc detectTSPacket(f : File) : (int, int)
proc writePacket*(f : File, packet : seq[byte] = @[],
                  flush : bool = false) : int {.discardable.}


# --------------- Util --------------------------------------------------------
proc humanReadable(value : float) : (float, string) =
  ## Convert to human-readable format.
  ##
  ## **Parameters:**
  ## - ``value`` : ``float``
  ##     Target value.
  ##
  ## **Returns:**
  ## - ``result`` : ``(float, string)``
  ##   - Human-readable format value.
  ##   - Metric prefix．
  var value : float = value
  let metricPrefixes : array[5, string] = [" ", "k", "M", "G", "T"]

  for metricPrefix in metricPrefixes:
    if value < 1000.0:
      result = (value, metricPrefix)
      return result
    value /= 1000.0

  result = (value, metricPrefixes[^1])


# --------------- Progress ----------------------------------------------------
proc progressMonitor() : void {.thread.} =
  ## Display progress.
  let sleepMilliSec : int = 1000
  var
    prevReadTotalPacketNum : int = 0
    prevWriteTotalPacketNum : int = 0
    prevTime : Time = getTime()
    finalFlag : bool = not progressFlag

  while progressFlag or (not finalFlag):
    if not progressFlag:
      finalFlag = true

    if readPacketSize == 0:
      sleep(sleepMilliSec)
      continue

    let
      currReadTotalPacketNum : int = readTotalPacketNum
      currWriteTotalPacketNum : int = writeTotalPacketNum
      currTime : Time = getTime()
      deltaSec : float = (
        float(currTime.toUnix() - prevTime.toUnix()) +
        1e-09 * float(currTime.nanosecond() - prevTime.nanosecond())
      )
      readSpeed : float = (
        float(readPacketSize *
              (currReadTotalPacketNum - prevReadTotalPacketNum)) / deltaSec
      )
      writeSpeed : float = (
        float(PACKET_SIZE *
              (currWriteTotalPacketNum - prevWriteTotalPacketNum)) / deltaSec
      )
      (readableReadSpeed, readSpeedMetricPrefix) = humanReadable(readSpeed)
      (readableWriteSpeed, writeSpeedMetricPrefix) = humanReadable(writeSpeed)
      (readableReadTotalBytes, readTotalBytesMetricPrefix) = (
        humanReadable(float(readPacketSize * currReadTotalPacketNum))
      )
      (readableWriteTotalBytes, writeTotalBytesMetricPrefix) = (
        humanReadable(float(PACKET_SIZE * currWriteTotalPacketNum))
      )

    prevReadTotalPacketNum = currReadTotalPacketNum
    prevWriteTotalPacketNum = currWriteTotalPacketNum
    prevTime = currTime

    stdout.write("Read: ", fmt"{readableReadSpeed:5.1f}", " ",
                 readSpeedMetricPrefix, "B/sec [",
                 fmt"{readableReadTotalBytes:5.1f}", " ",
                 readTotalBytesMetricPrefix, "B] / ",
                 "Write: ", fmt"{readableWriteSpeed:5.1f}", " ",
                 writeSpeedMetricPrefix, "B/sec [",
                 fmt"{readableWriteTotalBytes:5.1f}", " ",
                 writeTotalBytesMetricPrefix, "B]\r")
    stdout.flushFile

    sleep(sleepMilliSec)

  echo ""


# --------------- Read --------------------------------------------------------
proc detectTSPacket(f : File) : (int, int) =
  ## Detect the start position of the first packet and packet size.
  ##
  ## **Parameters:**
  ## - ``f`` : ``File``
  ##     Input MPEG-2 TS file.
  ##
  ## **Returns:**
  ## - ``result`` : ``(int, int)``
  ##   - Position of the first MPEG-2 TS sync word.
  ##   - Packet size of input MPEG-2 TS file.
  result = (0, 0)

  # The max MPEG-2 TS packet size is 208-byte.
  # Check the first 208*5-byte.
  var data : array[1040, byte]
  let readSize : int = readBytes(f, data, 0, 1040)
  if readSize != 1040:
    # Exclude files less than 208*5-byte.
    log(lvlFatal, "Invalid MPEG-2 TS file.")
    quit(1)

  f.setFilePos(0)

  # The MPEG-2 TS packet size is
  # either 188-byte, 192-byte, 204-byte, or 208-byte.
  let packetSizes : array[4, int] = [188, 192, 204, 208]
  block detect:
    for pos in 0..<208:
      if data[pos] != 0x47:
        continue

      for size in packetSizes:
        var validFlag : bool = true
        for num in 1..((1040 - pos) div size):
          if data[pos + size * num] != 0x47:
            validFlag = false
            break

        if validFlag:
          result = (pos, size)
          break detect


iterator readPacket*(f : File) : seq[byte] =
  ## Read packets.
  ##
  ## Read `PACKET_NUM` packets together into `readChunk`,
  ## and then extract each packet.
  ##
  ## **Parameters:**
  ## - ``f`` : ``File``
  ##     Input MPEG-2 TS file.
  ##
  ## **Yields:**
  ## - ``packet`` : ``seq[byte]``
  ##     Byte sequence of MPEG-2 TS packet.
  # Detect the start position of the first packet and packet size.
  let (startPos, packetSize) = detectTSPacket(f)
  readPacketSize = packetSize
  if packetSize == 0:
    log(lvlFatal, "Invalid MPEG-2 TS file.")
    quit(1)

  f.setFilePos(startPos)

  # Read `PACKET_NUM` packets together into `readChunk`.
  var
    readChunk : seq[byte] = newSeq[byte](packetSize * PACKET_NUM)
    loopFlag : bool = true

  while loopFlag:
    let chunkSize : int = readBytes(f, readChunk, 0, packetSize * PACKET_NUM)
    if chunkSize == 0:
      break
    elif chunkSize < packetSize * PACKET_NUM:
      loopFlag = false

    # Extract one packet from `readChunk`.
    for i in 0..<(chunkSize div packetSize):
      let packet : seq[byte] = readChunk[(packetSize * i)..<(
                                          packetSize * (i + 1))]

      if packet[0] == 0x47:
        yield packet
      else:
        log(lvlFatal, "Lost sync-byte.")
        quit(1)

      inc(readTotalPacketNum)


# --------------- Write -------------------------------------------------------
var
  writeChunk : seq[byte] = newSeq[byte](PACKET_SIZE * PACKET_NUM)
  writeChunkIdx : int = 0


proc writePacket(f : File, packet : seq[byte] = @[],
                 flush : bool = false) : int {.discardable.} =
  ## Write packets.
  ##
  ## Once store in `writeChunk`, and then output all.
  ##
  ## **Parameters:**
  ## - ``f`` : ``File``
  ##     Output MPEG-2 TS file.
  ## - ``packet`` : ``seq[byte]`` (defalt: ``@[]``)
  ##     Output packet.
  ## - ``flush`` : ``bool`` (default: ``false``)
  ##     Whether to force output or not.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``int``
  ##     Size of output bytes.
  result = 0
  if flush:
    result = writeBytes(f, writeChunk, 0, PACKET_SIZE * writeChunkIdx)
    writeTotalPacketNum += writeChunkIdx
    writeChunkIdx = 0
  else:
    # Output if `PACKET_NUM` packets are stored in `writeChunk`.
    if writeChunkIdx == PACKET_NUM:
      result = writeBytes(f, writeChunk, 0, PACKET_SIZE * PACKET_NUM)
      writeTotalPacketNum += writeChunkIdx
      writeChunkIdx = 0

    writeChunk[(PACKET_SIZE * writeChunkIdx)..<(
                PACKET_SIZE * (writeChunkIdx + 1))] = packet
    inc(writeChunkIdx)
