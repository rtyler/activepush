
Q = require "q"
QStep = require "q-step"
wd = require "wd"
merge = require "deepmerge"

integration = require "./integration-common"

# HACK: Delay before checking received messages to ensure all messages get delivered.
# Increase this value if tests are failiing non-deterministically.
# TODO: better way to detect all messages have been delivered?
WAIT_TIME = 200

DEFAULT_CONFIG =
  browser:
    browserName: "firefox"

LOCAL_CONFIG =
  host: "localhost"
  port: 4444

SAUCE_CONFIG =
  host: "ondemand.saucelabs.com"
  port: 80
  username: process.env["SAUCE_USER"]
  password: process.env["SAUCE_KEY"]

if process.env["SAUCE_USER"]?
  CONFIG = merge(DEFAULT_CONFIG, SAUCE_CONFIG)
else
  CONFIG = merge(DEFAULT_CONFIG, LOCAL_CONFIG)

exports.initIntegrationTests = (config = {}) ->
  config = merge(CONFIG, config)

  integration.initIntegrationTests
    name: "webdriver-#{config.browser.browserName}"
    createClient: (port, push_id) ->
      browser = wd.promiseRemote(config.host, config.port, config.username, config.password)
      QStep(
        -> browser.init(config.browser)
        -> browser.get("http://localhost:#{port}/\##{push_id}")
        -> browser.waitForCondition("!!window.messages", 5000)
        ->
          ->
            Q.delay(WAIT_TIME).then ->
              browser.eval("window.messages").then (messages) ->
                messages
              .fin ->
                browser.quit()
      )

# exports.initIntegrationTests()
exports.initIntegrationTests(browser: browserName: "chrome")
