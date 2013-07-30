
{ EventEmitter } = require "events"

class exports.Module extends EventEmitter
  constructor: (options) ->
    EventEmitter.call @
    @options = options
    @logger = options.logger or nullLogger
    @subscriptions = options.subscriptions


nullLogger = {}
nullLogger.error = nullLogger.warn = nullLogger.info = nullLogger.debug = (->)
