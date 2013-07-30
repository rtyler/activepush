
require "js-yaml"
merge = require "deepmerge"

exports.loadConfiguration = (environment = "development") ->
  deflt = require("#{__dirname}/../config/default.yml") or {}
  overlay = require("#{__dirname}/../config/#{environment}.yml") or {}
  merge deflt, overlay