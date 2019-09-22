import logging


var consoleLog : ConsoleLogger = newConsoleLogger(
  levelThreshold=lvlInfo,
  fmtStr="[$datetime] [$levelname] -- $appname: ",
  useStderr=true
)
addHandler(consoleLog)
