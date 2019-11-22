import tables
from strutils import replace
from times import DateTime, format, fromUnix, local


type EPGEvent = object
  startTimestamp : int
  duration : int
  name : string

type EPGEventTuple = tuple[eventId : int, epgEvent : EPGEvent]
var epgEvents : Table[int, EPGEvent] = newSeq[EPGEventTuple](0).toTable
epgEvents[0x10000] = EPGEvent(startTimestamp: 0, duration: 0, name: "Unknown")


proc existsEvent(eventId : int) : bool
proc registerEvent*(eventId : int, startTimestamp : int, duration : int,
                    name : string) : bool {.discardable.}
proc setUnknownStartTimestamp*(startTimestamp : int) : bool {.discardable.}
proc getEventName*(eventId : int) : string
proc getEventStartTime*(eventId : int) : string
proc searchEventId*(timestamp : int) : int


proc existsEvent(eventId : int) : bool =
  ## Whether ``eventId`` is in ``epgEvents`` or not.
  ##
  ## **Parameters:**
  ## - ``eventId`` : ``int``
  ##     EPG event identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``bool``
  ##     Whether ``eventId`` is in ``epgEvents`` or not.
  result = eventId in epgEvents


proc registerEvent(eventId : int, startTimestamp : int, duration : int,
                   name : string) : bool {.discardable.} =
  ## Register ``eventId`` in ``epgEvents``.
  ##
  ## **Parameters:**
  ## - ``eventId`` : ``int``
  ##     EPG event identifier.
  ## - ``startTimestamp`` : ``int``
  ##     EPG event start timestamp.
  ## - ``duration`` : ``int``
  ##     EPG event duration time.
  ## - ``name`` : ``string``
  ##     EPG event name.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether new registration is successful or not.
  result = false

  if not existsEvent(eventId):
    epgEvents[eventId] = EPGEvent(startTimestamp: startTimestamp,
                                  duration: duration, name: name)
    result = true


proc setUnknownStartTimestamp*(startTimestamp : int) : bool {.discardable.} =
  ## Set ``startTimestamp`` of "Unknown" event (eventId = 0x10000).
  ##
  ## Only if ``startTimestamp`` of "Unknown" event is 0, this function will
  ## be successful.
  ##
  ## **Parameters:**
  ## - ``startTimestamp`` : ``int``
  ##     "Unknown" event start timestamp.
  ##
  ## **Returns:** (discardable)
  ## - ``result`` : ``bool``
  ##     Whether setting value is successful or not.
  result = false

  if epgEvents[0x10000].startTimestamp == 0:
    epgEvents[0x10000].startTimestamp = startTimestamp
    result = true


proc getEventName(eventId : int) : string =
  ## Get EPG event name from ``epgEvents``.
  ##
  ## **Parameters:**
  ## - ``eventId`` : ``int``
  ##     EPG event identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     EPG event name.
  if (not existsEvent(eventId)) or eventId == 0x10000:
    result = "Unknown"
  else:
    result = epgEvents[eventId].name


proc getEventStartTime(eventId : int) : string =
  ## Get EPG event start time from ``epgEvents``.
  ##
  ## **Parameters:**
  ## - ``eventId`` : ``int``
  ##     EPG event identifier.
  ##
  ## **Returns:**
  ## - ``result`` : ``string``
  ##     EPG event start time as format "yyMMdd_HHmm".
  var eventId : int = eventId

  if not existsEvent(eventId):
    eventId = 0x10000

  let
    startTimestamp : int = epgEvents[eventId].startTimestamp
    startDateTime : DateTime = startTimestamp.fromUnix().local()

  result = startDateTime.format("yyMMdd-HHmmss")
  result = result.replace("-", "_")


proc searchEventId(timestamp : int) : int =
  ## Search ``eventId`` from ``timestamp``.
  ##
  ## **Parameters:**
  ## - ``timestamp`` : ``int``
  ##     Timestamp.
  ##
  ## **Returns:**
  ## - ``result`` : ``int``
  ##     EPG event identifier.
  result = 0x10000

  for eventId, epgEvent in epgEvents:
    if (timestamp >= epgEvent.startTimestamp and
        timestamp <  epgEvent.startTimestamp + epgEvent.duration):
      result = eventId
      break
