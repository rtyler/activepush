
Q = require "q"
merge = require "deepmerge"

Producer = require("./common").Module

class StompProducer extends Producer
  constructor: (options) ->
    Producer.call @, options

  getHealth: ->
    name: "stomp"
    host: @options.host
    port: @options.port
    inbox: @options.inbox

{ Stomp } = require "stomp"
{ ReconnectingStomp } = require "./reconnecting-stomp"

# Library #1: stomp
class NodeStompProducer extends StompProducer

  start: ->
    deferred = Q.defer()
    options = merge(@options.host, debug: false)
    # @stomp = new Stomp options
    @stomp = new ReconnectingStomp options
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

StompProducer = NodeStompProducer

# Library #2: stompit
# stompit = require "stompit"
# class StompitProducer extends StompProducer

#   start: ->
#     deferred = Q.defer()
#     @stomp = stompit.connect host: @options.host, port: @options.port, =>
#       @_onConnected()
#       deferred.resolve()
#     deferred.promise

#   stop: ->
#     Q.try =>
#       @stomp.disconnect()

#   _onConnected: =>
#     @stomp.subscribe { destination: @options.inbox }, @_onMessage
#     @logger.info "STOMP connected: %s:%s%s", @options.host, @options.port, @options.inbox

#   _onMessage: (message) =>
#     body = ""
#     message.on "data", (data) ->
#       body += data.toString("utf-8")
#     message.on "end", =>
#       push_id = message.headers.push_id
#       @logger.debug "STOMP receive push_id=%s message=%s", push_id, body
#       @subscriptions.emit push_id, body

#   publish: (push_id, message) ->
#     frame = @stomp.send(
#       destination: @options.inbox
#       push_id: push_id
#       persistent: false
#     )
#     Q.ninvoke(frame, "end", message)

# StompitProducer.publish = (options, push_id, message) ->
#   console.log "options", options
#   stomp = new StompitProducer options
#   stomp.start().then ->
#     stomp.publish(push_id, message)
#   .then ->
#     stomp.stop()

# StompProducer = StompitProducer

module.exports = { Producer, StompProducer }
