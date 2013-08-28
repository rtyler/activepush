
Q = require "q"
http = require "http"
express = require "express"
winston = require "winston"
optimist = require "optimist"

{ SubscriptionBroker } = require "./lib/subscription-broker"
{ SocketIOConsumer } = require "./lib/consumers"
{ StompProducer } = require "./lib/producers"

config = exports.config = require "./lib/config"

class exports.ActivePush
  constructor: (config) ->
    @config = config

    @logger = @config.logger or winston
    # Configure logging
    if @config.logging.file
      @logger.remove @logger.transports.Console
      @logger.add @logger.transports.File,
        filename: @config.logging.file
    @logger.level = (@config.logging.level or "info").toLowerCase()

  start: ->
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

    @_initializePrivateEndpoints(@app)
    # Put these on another port by doing the following:
    # privateApp = express()
    # privateApp.listen(@config.http.port + 1)
    # @_initializePrivateEndpoints(privateApp)

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

  _initializePrivateEndpoints: (app) ->
    # Health endpoint
    @app.get "/health", @_healthEndpoint

    # Demo page and sending endpoint.
    @app.get "/", (req, res) ->
      res.sendfile "#{__dirname}/demo.html"
    @app.post "/send", express.json(), (req, res) =>
      @producer.publish req.body.push_id, req.body.message
      res.send 200

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

exports.main = ->
  options = optimist
    .usage("Start ActivePush server.\nUsage: activepush [OPTIONS] [ENVIRONMENT]")
    .boolean(["h", "v"])
    .alias("c", "config")
    .describe("c", "Specify a configuration file")
    .alias("h", "help")
    .describe("h", "Show command line options and exit")
    .alias("v", "version")
    .describe("v", "Show version and exit")

  if options.argv.help
    options.showHelp()
    process.exit()
  if options.argv.version
    console.log "v" + require("#{__dirname}/package.json").version
    process.exit()

  configName = options.argv.config or options.argv._[0]

  configuration = config.loadConfiguration(configName)
  activepush = new exports.ActivePush(configuration)
  activepush.start().then ->
    activepush.logger.info "Started with environment: #{activepush.config.environment}"
    process.on "SIGINT", ->
      activepush.logger.info "Shutting down..."
      activepush.stop().then ->
        process.exit(1)
      .done()
  .done()

if require.main is module
  exports.main()
