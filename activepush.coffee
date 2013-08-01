
http = require "http"
{ EventEmitter } = require "events"
Q = require "q"

express = require "express"
logger = require "winston"

config = exports.config = require "./lib/config"
{ SocketIOConsumer } = require "./lib/consumers"
{ StompProducer } = require "./lib/producers"

class SubscriptionBroker extends EventEmitter
  constructor: ->
    EventEmitter.call @
    @messageCount = 0
  emit: ->
    @messageCount++
    EventEmitter::emit.apply @, arguments

  getHealth: ->
    health =
      name: "subscriptions"
      push_ids: {}
      subscriptions: 0
      messages: @messageCount
    for name, value of @_events
      count = if Array.isArray(value) then value.length else 1
      health.push_ids[name] = count
      health.total += count
    health

class ActivePush
  constructor: (config) ->
    @config = config

  start: ->

    @logger = logger
    # Configure logging
    if @config.logging.file
      @logger.remove logger.transports.Console
      @logger.add logger.transports.File,
        filename: @config.logging.file
    @logger.level = (@config.logging.level or "info").toLowerCase()

    @subscriptions = new SubscriptionBroker()

    # Create STOMP producer
    @producer = new StompProducer
      logger: @logger
      subscriptions: @subscriptions
      inbox: @config.stomp.inbox
      host: @config.stomp.hosts[0].host
      port: @config.stomp.hosts[0].port

    # Create Socket.io consumer
    @app = express()
    @server = http.createServer @app
    @consumer = new SocketIOConsumer @server,
      logger: @logger
      subscriptions: @subscriptions
      port: @config.http.port

    # Health endpoint
    @app.get "/health", @_healthEndpoint

    # Demo page and sending endpoint.
    @app.get "/", (req, res) ->
      res.sendfile "#{__dirname}/demo.html"
    @app.post "/send", express.json(), (req, res) =>
      @producer.publish req.body.push_id, req.body.message
      res.send 200

    Q.all([
      @consumer.start()
      @producer.start()
    ]).then =>
      @

  stop: ->
    Q.all([
      @consumer.stop()
      @producer.stop()
    ])

  _healthEndpoint: (req, res) =>
    health =
      log:
        enabled: true
        level: @config.logging.level
        filename: @config.logging.file
    for component in [@subscriptions, @producer, @consumer]
      object = component.getHealth()
      health[object.name] = object
      delete object.name
    res.json health

exports.ActivePush = ActivePush

exports.main = (args) ->
  activepush = new ActivePush(config.loadConfiguration(args[0]))
  activepush.start().then ->
    activepush.logger.info "Ready..."
    process.on "SIGINT", ->
      activepush.logger.info "Shutting down..."
      activepush.stop().then ->
        process.exit(1)
      .done()

if require.main is module
  exports.main(process.argv[2..]).done()
