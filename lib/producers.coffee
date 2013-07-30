
Q = require "q"
Producer = require("./common").Module

# Library #1: stomp
{ Stomp } = require "stomp"
class NodeStompProducer extends Producer
  constructor: (options) ->
    Producer.call @, options

  start: ->
    deferred = Q.defer()
    @stomp = new Stomp merge(@options.host, debug: true)
    # stomp = new ReconnectingStomp host
    @stomp.connect()
    @stomp.on "connected", =>
      @_onConnected()
      deferred.resolve()
    @stomp.on "disconnected", =>
      @logger.error "STOMP disconnected: %s:%s", @options.host, @options.port
      deferred.reject()
    @stomp.on "error", (error) =>
      @logger.error "STOMP error: %s", error
    deferred.promise

  stop: ->
    Q.try =>
      @stomp.disconnect()

  _onConnected: =>
    @logger.info "STOMP connected: %s:%s%s", @options.host, @options.port, @options.inbox
    @stomp.subscribe { destination: @options.inbox, ack: "client" }, @_onMessage

  _onMessage: (body, headers) =>
    push_id = headers.push_id
    message = body[0]
    @logger.debug "STOMP receive push_id=%s message=%s", push_id, message
    @subscriptions.emit push_id, message

  publish: (push_id, message) ->
    @stomp.send
      destination: @options.inbox
      push_id: push_id
      body: message
      persistent: false
    , false

NodeStompProducer.publish = (options, push_id, message) ->
  console.log "options", options
  stomp = new NodeStompProducer options
  stomp.start().then ->
    stomp.publish(push_id, message)
    stomp.stop()

# # Subclass of Stomp that automatically tries to reconnect, similar options to Ruby STOMP gem
# class ReconnectingStomp extends Stomp
#   constructor: (args) ->
#     Stomp.call @, args

#     @initial_reconnect_delay  = args.initial_reconnect_delay or 1
#     @max_reconnect_delay      = args.max_reconnect_delay or 30.0
#     @use_exponential_back_off = if args.use_exponential_back_off? then args.use_exponential_back_off else true
#     @back_off_multiplier      = args.back_off_multiplier or 2
#     @max_reconnect_attempts   = args.max_reconnect_attempts or 0

#     @_resetReconnection()
#     @on "connected", @_resetReconnection
#     @on "disconnected", @_reconnect

#   _reconnect: =>
#     if @reconnectTimer?
#       return
#     if @max_reconnect_attempts > 0 and @reconnectCount >= @max_reconnect_attempts
#       return
#     if @use_exponential_back_off
#       @reconnectDelay = Math.min(@max_reconnect_delay * 1000, @reconnectDelay * @back_off_multiplier)
#     @reconnectTimer = setTimeout =>
#       @max_reconnect_attempts++
#       @connect()
#       delete @reconnectTimer
#     , @reconnectDelay

#   _resetReconnection: =>
#     @reconnectCount = 0
#     @reconnectTimer = null
#     @reconnectDelay = @initial_reconnect_delay * 1000

# Library #2: stompit
stompit = require "stompit"
class StompitProducer extends Producer
  constructor: (options) ->
    Producer.call @, options

  start: ->
    deferred = Q.defer()
    @stomp = stompit.connect host: @options.host, port: @options.port, =>
      @_onConnected()
      deferred.resolve()
    deferred.promise

  stop: ->
    Q.try =>
      @stomp.disconnect()

  _onConnected: =>
    @stomp.subscribe { destination: @options.inbox }, @_onMessage
    @logger.info "STOMP connected: %s:%s%s", @options.host, @options.port, @options.inbox

  _onMessage: (message) =>
    body = ""
    message.on "data", (data) ->
      body += data.toString("utf-8")
    message.on "end", =>
      push_id = message.headers.push_id
      @logger.debug "STOMP receive push_id=%s message=%s", push_id, body
      @subscriptions.emit push_id, body

  getHealth: ->
    name: "stomp"
    host: @options.host
    port: @options.port
    inbox: @options.inbox

  publish: (push_id, message) ->
    @stomp.send(
      destination: @options.inbox
      push_id: push_id
      persistent: false
    ).end(message)

StompitProducer.publish = (options, push_id, message) ->
  console.log "options", options
  stomp = new StompitProducer options
  stomp.start().then ->
    stomp.publish(push_id, message)
    stomp.stop()

# Default to one of the two:
# StompProducer = NodeStompProducer
StompProducer = StompitProducer

module.exports = { Producer, StompProducer }
