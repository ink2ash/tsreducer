import tables


type EPGEvent = object
  startTimestamp : int
  duration : int
  name : string

type EPGEventTuple = tuple[eventId : int, epgEvent : EPGEvent]
var epgEvents : Table[int, EPGEvent] = newSeq[EPGEventTuple](0).toTable


proc existsEvent(eventId : int) : bool
proc registerEvent*(eventId : int, startTimestamp : int, duration : int,
                    name : string) : bool {.discardable.}
proc getEventName*(eventId : int) : string
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
