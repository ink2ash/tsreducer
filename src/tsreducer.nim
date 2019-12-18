## tsreducer
##
## Copyright (c) 2019 ink2ash
##
## This software is released under the MIT License.
## http://opensource.org/licenses/mit-license.php

import logging
import parseopt
from os import `/`, moveFile, splitFile
from strformat import fmt
from strutils import parseInt, rsplit, join

import ./tsreducer/crc32
import ./tsreducer/epgevent
import ./tsreducer/logger
import ./tsreducer/packetio
import ./tsreducer/packetproc
import ./tsreducer/pidbuffer
import ./tsreducer/timestamp


const
  Version : string = "tsreducer 1.0.0"
  Usage : string = """
tsreducer - Reduce MPEG-2 TS file size
  (c) 2019 ink2ash
Usage: tsreducer [options] inputfile [options]
Options:
  --dstdir:DIR            set destination directory path (default: ".")
  --tmpdir:DIR            set temporary directory path (default: "/tmp")
  -o:FILE, --output:FILE  set output filename
  -s, --split             split by programs
  --margin:INT            set split margin seconds (default: 0)
  -w, --wraparound        avoid PCR/PTS/DTS wrap-around problem
  -p, --progress          show progress
  -v, --version           write tsreducer's version
  -h, --help              show this help
"""

var
  # Option variables
  inputFileName : string = ""
  dstdirPath : string = "."
  tmpdirPath : string = "/tmp"
  splitFlag : bool = false
  splitMargin : int = 0
  # Other variables
  outputFiles : array[2, File]
  tmpFileNames : array[2, string] = ["unknown0", "unknown1"]
  mainFileId : int = 0
  isBothFileOpen : bool = false
  prevEventId : int = 0x10000
  nextEventId : int = 0x10000


proc fileWriter(packet : seq[byte] = @[], flush : bool = false) : void
proc manageFiles(pid : int, packet : seq[byte]) : void
proc parseOptions() : void
proc main() : void


proc fileWriter(packet : seq[byte] = @[], flush : bool = false) : void =
  ## Write a file or files.
  ##
  ## **Parameters:**
  ## - ``packet`` : ``seq[byte]`` (defalt: ``@[]``)
  ##     Output packet.
  ## - ``flush`` : ``bool`` (default: ``false``)
  ##     Whether to force output or not.
  packetio.writePacket(outputFiles[mainFileId], packet=packet, flush=flush)
  if isBothFileOpen:
    let subFileId : int = 1 - mainFileId
    packetio.writePacket(outputFiles[subFileId], packet=packet, flush=flush)


proc manageFiles(pid : int, packet : seq[byte]) : void =
  ## Manage files by PCR.
  ##
  ## **Parameters:**
  ## - ``pid`` : ``int``
  ##     Packet identifier.
  ## - ``packet`` : ``seq[byte]``
  ##     A packet of MPEG-2 TS.
  let existsAdaptation : bool = ((packet[3] shr 5) and 0x01) == 1
  if existsAdaptation:
    let existsPCR : bool = ((packet[5] shr 4) and 0x01) == 1
    if existsPCR:
      let
        pcrSeq : seq[byte] = packet[6..11]
        timeId : int = timestamp.calcTimeId(pid, "PCR")
      var pcr : int = timestamp.byte2pcr(pcrSeq)
      if not packetproc.wraparoundFlag:
        pcr = timestamp.modifyTime(timeId, pcr)

      let
        secOffset : int = int((pcr - timestamp.getRelPcr()) / 27_000_000)
        currTimestamp : int = timestamp.getRelJST() + secOffset
        marginPrevEventId : int = (
          epgevent.searchEventId(currTimestamp - splitMargin)
        )
        marginNextEventId : int = (
          epgevent.searchEventId(currTimestamp + splitMargin)
        )
        deltaPrevEventId : int = (
          epgevent.searchEventId(currTimestamp - splitMargin - 1)
        )
        deltaNextEventId : int = (
          epgevent.searchEventId(currTimestamp + splitMargin + 1)
        )

      if (marginPrevEventId != deltaPrevEventId and
          prevEventId != deltaPrevEventId):
        prevEventId = deltaPrevEventId
        log(lvlDebug, fmt"prev -> curr ",
                      fmt"{epgevent.getEventName(prevEventId)} ",
                      fmt"-> {epgevent.getEventName(marginPrevEventId)}")

        fileWriter(flush=true)

        close(outputFiles[mainFileId])
        isBothFileOpen = false

        if tmpFileNames[mainFileId][0..^2] == "unknown":
          moveFile(
            tmpdirPath / tmpFileNames[mainFileId],
            dstdirPath / fmt"{epgevent.getEventStartTime(prevEventId)}_" &
                         fmt"{epgevent.getEventName(prevEventId)}.m2ts"
          )
        else:
          moveFile(tmpdirPath / tmpFileNames[mainFileId],
                   dstdirPath / tmpFileNames[mainFileId])

        mainFileId = 1 - mainFileId

      if (marginNextEventId != deltaNextEventId and
          nextEventId != deltaNextEventId):
        if marginNextEventId != 0x10000:
          nextEventId = deltaNextEventId
          log(lvlDebug, fmt"curr -> next ",
                        fmt"{epgevent.getEventName(marginNextEventId)} ",
                        fmt"-> {epgevent.getEventName(nextEventId)}")

          fileWriter(flush=true)

          let subFileId : int = 1 - mainFileId
          tmpFileNames[subFileId] = (
            fmt"{epgevent.getEventStartTime(nextEventId)}_" &
            fmt"{epgevent.getEventName(nextEventId)}.m2ts"
          )
          outputFiles[subFileId] = open(tmpdirPath / tmpFileNames[subFileId],
                                        fmWrite)
          isBothFileOpen = true


proc parseOptions() : void =
  ## Parse command line arguments.
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      inputFileName = key
    of cmdLongOption, cmdShortOption:
      case key
      of "dstdir":
        dstdirPath = val
      of "tmpdir":
        tmpdirPath = val
      of "output", "o":
        tmpFileNames[0] = val
        if '/' in val:
          log(lvlFatal, "Invalid output filename")
          quit(1)
      of "split", "s":
        splitFlag = true
      of "margin":
        try:
          splitMargin = parseInt(val)
          if splitMargin < 0:
            log(lvlFatal, "Invalid value of split margin.")
            quit(1)
        except ValueError:
          log(lvlFatal, "Invalid value of split margin.")
          quit(1)
      of "wraparound", "w":
        packetproc.wraparoundFlag = true
      of "progress", "p":
        packetio.progressFlag = true
      of "version", "v":
        echo Version
        quit(0)
      of "help", "h":
        echo Usage
        quit(0)
      else:
        log(lvlFatal, "Invalid option")
        quit(1)
    of cmdEnd:
      discard
  if inputFileName == "":
    log(lvlFatal, "Invalid input file")
    quit(1)
  if not splitFlag and tmpFileNames[0] == "unknown0":
    let splitInputFile : tuple[dir : string, name : string, ext : string] = (
      splitFile(inputFileName)
    )
    tmpFileNames[0] = splitInputFile.name & ".reduced" & splitInputFile.ext


proc main() : void =
  ## Main process.
  parseOptions()

  let inputFile : File = open(inputFileName, fmRead)
  defer:
    close(inputFile)

  outputFiles[mainFileId] = open(tmpdirPath / tmpFileNames[mainFileId],
                                 fmWrite)

  pidbuffer.registerPIDBuffer(0x0000)  # PAT
  pidbuffer.registerPIDBuffer(0x0011)  # SDT/BAT
  pidbuffer.registerPIDBuffer(0x0012)  # EIT
  pidbuffer.registerPIDBuffer(0x0014)  # TDT/TOT

  var progressThread : Thread[void]
  if packetio.progressFlag:
    createThread(progressThread, packetio.progressMonitor)

  try:
    for packet in packetio.readPacket(inputFile):
      var packet : seq[byte] = packet

      let pid : int = ((int(packet[1]) and 0x1F) shl 8) or int(packet[2])
      if not pidbuffer.existsPIDBuffer(pid):
        continue

      if pidbuffer.isPCR(pid) or pidbuffer.isES(pid):
        packet = packetproc.modifyPacketTime(pid, packet)

        if pidbuffer.isPCR(pid) and splitFlag:
          manageFiles(pid, packet)

        fileWriter(packet=packet)
      else:
        var hasDualSection : bool = true
        while hasDualSection:
          let isFull : bool = pidbuffer.storePIDBuffer(pid, packet,
                                                      hasDualSection)
          if not isFull:
            continue

          let section : seq[byte] = pidbuffer.loadSection(pid)

          if pid == 0x0000 or isPMT(pid) or pid == 0x0011:
            let
              reducedSection : seq[byte] = packetproc.reduceSection(pid,
                                                                    section)
              reducedPackets : seq[seq[byte]] = (
                packetproc.makeTSPacket(pid, reducedSection)
              )
            for reducedPacket in reducedPackets:
              fileWriter(packet=reducedPacket)
          else:
            packetproc.parseSI(pid, section)
            fileWriter(packet=packet)


  except:
    let
      e : ref Exception = getCurrentException()
      msg : string = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg

  finally:
    fileWriter(flush=true)

    close(outputFiles[mainFileId])
    if tmpFileNames[mainFileId][0..^2] == "unknown":
      moveFile(
        tmpdirPath / tmpFileNames[mainFileId],
        dstdirPath / fmt"{epgevent.getEventStartTime(prevEventId)}_" &
                     fmt"{epgevent.getEventName(prevEventId)}.m2ts"
      )
    else:
      moveFile(tmpdirPath / tmpFileNames[mainFileId],
               dstdirPath / tmpFileNames[mainFileId])

  if packetio.progressFlag:
    packetio.progressFlag = false
    joinThread(progressThread)


when isMainModule:
  main()
