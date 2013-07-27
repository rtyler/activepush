
fs = require "fs"
path = require "path"
http = require "http"
express = require "express"
socket_io = require "socket.io"
merge = require "deepmerge"
logger = require "winston"
{ Stomp } = require "stomp"
{ EventEmitter } = require "events"
require "js-yaml"

exports.loadConfiguration = (environment = "development") ->
  deflt = require("#{__dirname}/config/default.yml") or {}
  overlay = require("#{__dirname}/config/#{environment}.yml") or {}
  merge deflt, overlay

createSocketIOServer = (config, subscriptions) ->
  app = express()
  server = http.createServer app
  io = socket_io.listen server, log: false
  server.listen config.http.port
  logger.info "SOCKET.IO listening on port %s", config.http.port

  io.sockets.on "connection", (socket) ->
    logger.debug "SOCKET.IO connection"
    socket.on "error", (error) ->
      logger.warn "SOCKET.IO error: %s", error
    socket.on "subscribe", (push_id) ->
      logger.info "SOCKET.IO subscribed: %s", push_id
      listener = (message) ->
        logger.debug "SOCKET.IO send push_id=%s message=%s", push_id, message
        socket.send message
      subscriptions.addListener push_id, listener
      socket.on "disconnect", ->
        logger.info "SOCKET.IO disconnected: %s", push_id
        subscriptions.removeListener push_id, listener

  { app, io, server }

createStompConnection = (config, subscriptions) ->
  host = config.stomp.hosts[0]
  stomp = new ReconnectingStomp host
  stomp.connect()
  stomp.on "connected", ->
    logger.info "STOMP connected: %s:%s%s", host.host, host.port, config.stomp.inbox
    stomp.subscribe { destination: config.stomp.inbox, ack: "client" }, (body, headers) ->
      push_id = headers.push_id
      message = body[0]
      # logger.trace "STOMP receive push_id=%s message=%s", push_id, message
      subscriptions.emit push_id, message

  stomp.on "error", (error) ->
    logger.error "STOMP error: %s", error
    # stomp.disconnect()

  stomp.on "disconnected", (_) ->
    logger.error "STOMP disconnected: %s:%s", host.host, host.port

  stomp

createHealthEndpoint = (config, stomp, io, subscriptions) ->
  (req, res) ->
    res.json
      stomp:
        host: stomp.host
        port: stomp.port
      http:
        port: config.http.port
      metrics:
        running: true
        log:
          enabled: true
          level: config.logging.level
          filename: config.logging.file
        subscriptions: getSubscriptionsMetrics(subscriptions)
        connections: getConnectionsMetrics(io)

getConnectionsMetrics = (io) ->
  count: io.sockets.clients().length

getSubscriptionsMetrics = (subscriptions) ->
  stats =
    push_ids: {}
    total: 0
  for name, value of subscriptions._events
    count = if Array.isArray(value) then value.length else 1
    stats.push_ids[name] = count
    stats.total += count
  stats

exports.stompPublish = (host, destination, push_id, message) ->
  stomp = new Stomp host
  stomp.connect()
  stomp.on "connected", ->
    stomp.send
      destination: destination
      push_id: push_id
      body: message
      persistent: false
    , false
    stomp.disconnect()
  stomp.on "error", (error) ->
    console.warn "stompPublish error", error

exports.start = (config, callback) ->
  # Configure logging
  if config.logging.file
    logger.remove logger.transports.Console
    logger.add logger.transports.File,
      filename: config.logging.file
  logger.level = (config.logging.level or "info").toLowerCase()

  # EventEmitter used to keep track of subscriptions
  subscriptions = new EventEmitter()

  # Create Socket.io server
  { app, io, server } = createSocketIOServer(config, subscriptions)

  # Create STOMP connection
  stomp = createStompConnection(config, subscriptions)

  # Health endpoint
  app.get "/health", createHealthEndpoint(config, stomp, io, subscriptions)

  # Demo page and sending endpoint.
  app.get "/", (req, res) ->
    res.sendfile "#{__dirname}/demo.html"
  app.post "/send", express.json(), (req, res) ->
    exports.stompPublish stomp, config.stomp.inbox, req.body.push_id, req.body.message
    res.send 200

  stomp.on "connected", ->
    callback?(null)

  stop: (callback) ->
    logger.info "Shutting down..."
    stomp.disconnect()
    server.close()
    process.nextTick ->
      callback?(null)

exports.main = (args) ->
  exports.start exports.loadConfiguration args[0]

# Subclass of Stomp that automatically tries to reconnect, similar options to Ruby STOMP gem
class ReconnectingStomp extends Stomp
  constructor: (args) ->
    Stomp.call @, args

    @initial_reconnect_delay  = args.initial_reconnect_delay or 1
    @max_reconnect_delay      = args.max_reconnect_delay or 30.0
    @use_exponential_back_off = if args.use_exponential_back_off? then args.use_exponential_back_off else true
    @back_off_multiplier      = args.back_off_multiplier or 2
    @max_reconnect_attempts   = args.max_reconnect_attempts or 0

    @_resetReconnection()
    @on "connected", @_resetReconnection
    @on "disconnected", @_reconnect

  _reconnect: =>
    if @reconnectTimer?
      return
    if @max_reconnect_attempts > 0 and @reconnectCount >= @max_reconnect_attempts
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

if require.main is module
  exports.main process.argv[2..]
