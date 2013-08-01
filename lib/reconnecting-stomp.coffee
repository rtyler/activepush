
{ Stomp } = require "stomp"

# Subclass of Stomp that automatically tries to reconnect, similar options to Ruby STOMP gem
class exports.ReconnectingStomp extends Stomp
  constructor: (args) ->
    Stomp.apply @, arguments

    @initial_reconnect_delay  = args.initial_reconnect_delay or 1
    @max_reconnect_delay      = args.max_reconnect_delay or 30.0
    @use_exponential_back_off = if args.use_exponential_back_off? then args.use_exponential_back_off else true
    @back_off_multiplier      = args.back_off_multiplier or 2
    @max_reconnect_attempts   = args.max_reconnect_attempts or 0

    @_resetReconnection()
    @on "connected", @_resetReconnection

  # Hook emit to intercept "disconnect" error.
  # Kind of hacky. Should we wrap the class instead?
  emit: (name, object) ->
    if name is "disconnected"
      unless @max_reconnect_attempts > 0 and @reconnectCount >= @max_reconnect_attempts
        @_reconnect()
        return
    Stomp::emit.apply @, arguments

  _reconnect: =>
    if @reconnectTimer?
      return
    if @use_exponential_back_off
      @reconnectDelay = Math.min(@max_reconnect_delay * 1000, @reconnectDelay * @back_off_multiplier)
    @reconnectTimer = setTimeout =>
      @max_reconnect_attempts++
      @connect()
      delete @reconnectTimer
    , @reconnectDelay

  _resetReconnection: =>
    @reconnectCount = 0
    @reconnectTimer = null
    @reconnectDelay = @initial_reconnect_delay * 1000
