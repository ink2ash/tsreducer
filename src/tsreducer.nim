import logging
import parseopt
from strutils import rsplit, join

import ./tsreducer/crc32
import ./tsreducer/logger
import ./tsreducer/packetio
import ./tsreducer/packetproc
import ./tsreducer/pidbuffer


const
  Version : string = "tsreducer 0.1.0"
  Usage : string = """
tsreducer - Reduce MPEG-2 TS file size
  (c) 2019 ink2ash
Usage: tsreducer [options] inputfile [options]
Options:
  -o:FILE, --output:FILE  set output filename
  -p, --progress          show progress
  -v, --version           write tsreducer's version
  -h, --help              show this help
"""

var
  inputFileName : string = ""
  outputFileName : string


proc parseOptions() : void =
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      inputFileName = key
    of cmdLongOption, cmdShortOption:
      case key
      of "output", "o":
        outputFileName = val
      of "progress", "p":
        packetio.progressFlag = true
      of "version", "v":
        echo Version
        quit(0)
      of "help", "h":
        echo Usage
        quit(0)
    of cmdEnd:
      discard
  if inputFileName == "":
    log(lvlFatal, "Invalid input file")
    quit(1)
  if outputFileName == "":
    outputFileName = inputFileName.rsplit('.', 1).join(".reduced.")


proc main() : void =
  parseOptions()

  let
    inputFile : File = open(inputFileName, fmRead)
    outputFile : File = open(outputFileName, fmWrite)

  pidbuffer.registerPIDBuffer(0x0000)  # PAT
  pidbuffer.registerPIDBuffer(0x0011)  # SDT/BAT
  pidbuffer.registerPIDBuffer(0x0012)  # EIT
  pidbuffer.registerPIDBuffer(0x0014)  # TDT/TOT

  var progressThread : Thread[void]
  if packetio.progressFlag:
    createThread(progressThread, packetio.progressMonitor)

  try:
    for packet in packetio.readPacket(inputFile):
      let pid : int = ((int(packet[1]) and 0x1F) shl 8) or int(packet[2])
      if not pidbuffer.existsPIDBuffer(pid):
        continue

      if not (pid == 0x0000 or isPMT(pid)):
        packetio.writePacket(outputFile, packet=packet)
        continue

      var hasDualSection : bool = true

      while hasDualSection:
        var isFull : bool = pidbuffer.storePIDBuffer(pid, packet,
                                                     hasDualSection)
        if not isFull:
          continue

        let section : seq[byte] = loadSection(pid)

        if pid == 0x0000 or isPMT(pid):
          let
            reducedSection : seq[byte] = packetproc.reduceSection(pid, section)
            reducedPackets : seq[seq[byte]] = (
              packetproc.makeTSPacket(pid, reducedSection)
            )
          for reducedPacket in reducedPackets:
            packetio.writePacket(outputFile, packet=reducedPacket)

  except:
    let
      e : ref Exception = getCurrentException()
      msg : string = getCurrentExceptionMsg()
    echo "Got exception ", repr(e), " with message ", msg

  finally:
    packetio.writePacket(outputFile, flush=true)

  if packetio.progressFlag:
    packetio.progressFlag = false
    joinThread(progressThread)

  close(inputFile)
  close(outputFile)


when isMainModule:
  main()
