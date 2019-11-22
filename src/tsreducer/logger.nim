## logger
##
## Copyright (c) 2019 ink2ash
##
## This software is released under the MIT License.
## http://opensource.org/licenses/mit-license.php

import logging


var consoleLog : ConsoleLogger = newConsoleLogger(
  levelThreshold=lvlInfo,
  fmtStr="[$datetime] [$levelname] -- $appname: ",
  useStderr=true
)
addHandler(consoleLog)
